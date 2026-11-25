package updater

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"time"

	"github.com/y-miyazaki/config/cmd/terraform/internal/modulefile"
)

const (
	dirPerm  = 0o750
	filePerm = 0o600

	// backupRoot is the directory (inside the target directory) holding restore points.
	backupRoot = ".terraform_backups"

	// logKeyDir is the structured log key for a directory path.
	logKeyDir = "dir"

	// lockFileName is the provider lock file that `terraform init -upgrade` rewrites.
	lockFileName = ".terraform.lock.hcl"

	// noBackup marks a backups entry for a file that did not exist before the update;
	// rollback removes such a file instead of restoring it.
	noBackup = ""
)

// rootMarkers are files whose presence marks a Terraform project root,
// independent of the selected environment.
var rootMarkers = []string{"main.tf", "versions.tf", "providers.tf"}

// apply updates every pending module one at a time, verifying each with a plan
// comparison unless NoPlan is set, and records the outcome in sum.
func (u *Updater) apply(ctx context.Context, pending map[string]*pendingModule, sum *Summary) error {
	if err := u.setupBackupDir(); err != nil {
		return fmt.Errorf("set up backup directory: %w", err)
	}
	// Without a baseline there is nothing to compare against, so --no-plan skips it.
	if !u.opts.NoPlan {
		if err := u.createBaselines(ctx, pending); err != nil {
			return fmt.Errorf("create baselines: %w", err)
		}
	}
	// Sorted so that runs are reproducible and the progress counter is stable.
	sources := slices.Sorted(maps.Keys(pending))
	for i, source := range sources {
		p := pending[source]
		printf(u.out, "🔄 [%d/%d] Processing module: %s\n", i+1, len(sources), source)
		if err := u.applyOne(ctx, source, p); err != nil {
			u.log.Error("Module update failed and was rolled back", logKeySource, source, logKeyError, err)
			sum.Failed = append(sum.Failed, source)
			// A cancelled run must stop; other failures only affect this module.
			if ctxErr := ctx.Err(); ctxErr != nil {
				return fmt.Errorf("apply: %w", ctxErr)
			}
			continue
		}
		entry := fmt.Sprintf("%s (%s -> %s) [%d files]", source, p.current, p.latest, len(p.files))
		if u.opts.NoPlan {
			entry += " (no plan mode)"
		}
		sum.Updated = append(sum.Updated, entry)
		u.log.Info("Module updated", logKeySource, source, "version", p.latest, "files", len(p.files))
	}
	return nil
}

// applyOne updates all files of one module and verifies the result. On any
// failure every touched file is restored from its backup.
func (u *Updater) applyOne(ctx context.Context, source string, p *pendingModule) error {
	backups := make(map[string]string, len(p.files))
	for _, file := range p.files {
		backup, err := u.backup(file)
		if err != nil {
			u.rollback(backups)
			return fmt.Errorf("backup %s: %w", file, err)
		}
		backups[file] = backup
		// Only blocks that are older than latest change: another block of the same
		// source may be pinned at a newer version and must not be downgraded.
		changed, err := modulefile.UpdateFile(ctx, file, source, p.latest, func(current string) bool {
			return isNewer(p.latest, current)
		})
		// A file that no longer contains the module cannot be verified; treat it as a failure.
		if err == nil && changed == 0 {
			err = fmt.Errorf("%w: %s in %s", ErrNoModuleMatched, source, file)
		}
		if err != nil {
			u.rollback(backups)
			return fmt.Errorf("update %s: %w", file, err)
		}
	}
	if u.opts.NoPlan {
		return nil
	}
	// Validation runs `terraform init -upgrade`, which also rewrites the provider
	// lock file; it must be restored together with the .tf files on failure.
	if err := u.backupLockFiles(p.files, backups); err != nil {
		u.rollback(backups)
		return fmt.Errorf("backup lock files: %w", err)
	}
	if err := u.validateFiles(ctx, p.files); err != nil {
		u.rollback(backups)
		return fmt.Errorf("validate %s: %w", source, err)
	}
	return nil
}

// backup copies file into the backup directory and returns the copy's path.
func (u *Updater) backup(file string) (string, error) {
	data, err := os.ReadFile(filepath.Clean(file))
	if err != nil {
		return "", fmt.Errorf("read %s: %w", file, err)
	}
	// The sequence number keeps backups of same-named files from different directories apart.
	u.backupSeq++
	dst := filepath.Join(u.backupDir, fmt.Sprintf("%03d_%s.bak", u.backupSeq, filepath.Base(file)))
	if err = os.WriteFile(dst, data, filePerm); err != nil {
		return "", fmt.Errorf("write %s: %w", dst, err)
	}
	return dst, nil
}

// backupLockFiles records the provider lock file of every project that contains
// one of files into backups. A project without a lock file is recorded as
// noBackup so that a lock file created by init is removed again on rollback.
func (u *Updater) backupLockFiles(files []string, backups map[string]string) error {
	for _, project := range uniqueProjects(files, u.opts.Env) {
		lock := filepath.Join(project, lockFileName)
		if !fileExists(lock) {
			backups[lock] = noBackup
			continue
		}
		backup, err := u.backup(lock)
		if err != nil {
			return fmt.Errorf("backup %s: %w", lock, err)
		}
		backups[lock] = backup
	}
	return nil
}

// cleanup removes this run's backup directory unless a rollback failed.
func (u *Updater) cleanup() {
	if u.backupDir == "" {
		return
	}
	// A failed rollback means the backup is the only copy of the original file.
	if u.restoreFailed {
		u.log.Warn("Keeping backup directory because a rollback failed", logKeyDir, u.backupDir)
		return
	}
	if err := os.RemoveAll(u.backupDir); err != nil {
		u.log.Warn("Could not remove backup directory", logKeyDir, u.backupDir, logKeyError, err)
		return
	}
	// Best effort: the parent only goes away when no earlier run left restore points in it.
	if err := os.Remove(filepath.Dir(u.backupDir)); err != nil && !errors.Is(err, os.ErrNotExist) {
		u.log.Debug("Backup root kept", logKeyDir, filepath.Dir(u.backupDir))
	}
}

// rollback restores files from their backups. A file that cannot be restored
// keeps the backup directory alive so the original can be recovered by hand.
func (u *Updater) rollback(backups map[string]string) {
	for file, backup := range backups {
		if backup == noBackup {
			if err := os.Remove(file); err != nil && !errors.Is(err, os.ErrNotExist) {
				u.restoreFailed = true
				u.log.Error("Rollback failed; remove the file by hand", "file", file, logKeyError, err)
			}
			continue
		}
		data, err := os.ReadFile(filepath.Clean(backup))
		if err == nil {
			err = os.WriteFile(file, data, filePerm)
		}
		if err != nil {
			u.restoreFailed = true
			u.log.Error("Rollback failed; restore the file from the backup", "file", file, "backup", backup, logKeyError, err)
			continue
		}
		u.log.Info("Rolled back", "file", file)
	}
}

// setupBackupDir creates this run's timestamped backup directory.
func (u *Updater) setupBackupDir() error {
	u.backupDir = filepath.Join(u.opts.Dir, backupRoot, time.Now().Format("20060102_150405"))
	if err := os.MkdirAll(u.backupDir, dirPerm); err != nil {
		return fmt.Errorf("create backup directory: %w", err)
	}
	u.log.Info("Backup directory created", logKeyDir, u.backupDir)
	return nil
}

// validateFiles verifies every project that contains one of files.
func (u *Updater) validateFiles(ctx context.Context, files []string) error {
	for _, project := range uniqueProjects(files, u.opts.Env) {
		// A project without a baseline cannot be compared; the baseline step already warned.
		if !u.baselines[project] {
			u.log.Warn("Skipping validation for project without baseline", "project", project)
			continue
		}
		u.log.Info("Validating project", "project", project)
		if err := u.validateProject(ctx, project); err != nil {
			return fmt.Errorf("project %s: %w", project, err)
		}
	}
	return nil
}

// uniqueProjects returns the sorted, de-duplicated project roots of files.
func uniqueProjects(files []string, env string) []string {
	seen := make(map[string]struct{}, len(files))
	for _, file := range files {
		seen[projectRoot(file, env)] = struct{}{}
	}
	return slices.Sorted(maps.Keys(seen))
}

// projectRoot walks up from file looking for files that mark a Terraform
// project root (the common markers plus the files of the selected env); it
// falls back to the file's own directory.
func projectRoot(file, env string) string {
	markers := append([]string{"terraform." + env + ".tfbackend", "terraform." + env + ".tfvars"}, rootMarkers...)
	dir := filepath.Dir(file)
	// The loop ends at the filesystem root, which is never treated as a project.
	for cur := dir; cur != filepath.Dir(cur); cur = filepath.Dir(cur) {
		for _, marker := range markers {
			if fileExists(filepath.Join(cur, marker)) {
				return cur
			}
		}
	}
	return dir
}

// fileExists reports whether path is an existing regular file (or symlink to one).
func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
