// Package updater moves Terraform registry modules to the newest version that
// is old enough, and verifies each change by comparing terraform plans before
// and after the update, rolling the change back when the plans differ.
package updater

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"time"

	"github.com/y-miyazaki/config/cmd/terraform/internal/modulefile"
	"github.com/y-miyazaki/config/cmd/terraform/internal/registry"
)

const (
	terraformExt    = ".tf"
	terraformDotDir = ".terraform"

	// logKeySource is the structured log key for a module source address.
	logKeySource = "source"
)

var (
	// ErrPlanChanged is returned when the plan after an update differs from the baseline.
	ErrPlanChanged = errors.New("plan differs from baseline")
	// ErrNoModuleMatched is returned when an update did not change any module block.
	ErrNoModuleMatched = errors.New("no module block matched")

	// versionNumber extracts the numeric part of a version or constraint such as "~> 5.0".
	versionNumber = regexp.MustCompile(`\d+(?:\.\d+)*`)
)

// Resolver finds the version a module should be moved to.
type Resolver interface {
	// LatestEligible returns the newest version of a module source that was
	// published at least the given duration ago.
	LatestEligible(_ context.Context, _ string, _ time.Duration) (string, error)
}

// Runner runs terraform commands in a project directory; each method returns
// the command output (also on failure).
type Runner interface {
	// Init runs terraform init with extra arguments in a directory.
	Init(_ context.Context, _ string, _ ...string) (string, error)
	// Validate runs terraform validate in a directory.
	Validate(_ context.Context, _ string) (string, error)
	// Plan runs terraform plan with extra arguments in a directory.
	Plan(_ context.Context, _ string, _ ...string) (string, error)
	// Show renders a saved plan file (directory, plan file) as text.
	Show(_ context.Context, _, _ string) (string, error)
}

// Options configures a run.
type Options struct {
	// Dir is the absolute Terraform directory to process.
	Dir string
	// Env selects terraform.<Env>.tfvars and terraform.<Env>.tfbackend.
	Env string
	// MinReleaseAge is the minimum time a version must have been published.
	MinReleaseAge time.Duration
	Verbose       bool
	DryRun        bool
	CheckOnly     bool
	Recursive     bool
	NoPlan        bool
}

// Summary is the outcome of a run.
type Summary struct {
	Updated []string
	Failed  []string
	Total   int
}

// Updater runs the module update workflow. It is not safe for concurrent use.
type Updater struct {
	resolver      Resolver
	runner        Runner
	log           *slog.Logger
	out           io.Writer
	baselines     map[string]bool
	backupDir     string
	opts          Options
	backupSeq     int
	restoreFailed bool
}

// moduleUse is one module block found in a Terraform file.
type moduleUse struct {
	file    string
	source  string
	version string
}

// pendingModule is an update that is going to be applied to one module source.
type pendingModule struct {
	latest  string
	current string
	files   []string
}

// New returns an Updater. User-facing progress goes to out, diagnostics to logger.
func New(opts Options, resolver Resolver, runner Runner, logger *slog.Logger, out io.Writer) *Updater {
	return &Updater{
		opts:      opts,
		resolver:  resolver,
		runner:    runner,
		log:       logger,
		out:       out,
		baselines: make(map[string]bool),
	}
}

// Run scans the directory and applies the updates allowed by the options.
// A non-nil error means the run could not complete; failed modules are
// reported in Summary.Failed instead.
func (u *Updater) Run(ctx context.Context) (Summary, error) {
	var sum Summary
	uses, err := u.scan(ctx)
	if err != nil {
		return sum, fmt.Errorf("scan: %w", err)
	}
	sum.Total = len(uses)
	pending, err := u.discover(ctx, uses, &sum)
	if err != nil {
		return sum, fmt.Errorf("discover updates: %w", err)
	}
	if len(pending) == 0 {
		return sum, nil
	}
	defer u.cleanup()
	err = u.apply(ctx, pending, &sum)
	if err != nil {
		return sum, fmt.Errorf("apply updates: %w", err)
	}
	return sum, nil
}

// discover decides which modules should be updated and, in dry-run mode,
// records them. It returns the updates to apply grouped by module source.
func (u *Updater) discover(ctx context.Context, uses []moduleUse, sum *Summary) (map[string]*pendingModule, error) {
	pending := make(map[string]*pendingModule)
	// The registry is asked once per source; "" remembers sources without a usable version.
	latestBySource := make(map[string]string)
	for i := range uses {
		use := &uses[i]
		name := filepath.Base(use.file)
		u.log.Info("Found module", logKeySource, use.source, "current", use.version, "file", name)
		if u.opts.CheckOnly {
			printf(u.out, "📦 Found: %s (current: %s) in %s\n", use.source, use.version, name)
			continue
		}
		latest, seen := latestBySource[use.source]
		if !seen {
			var err error
			latest, err = u.resolver.LatestEligible(ctx, use.source, u.opts.MinReleaseAge)
			if err != nil {
				if ctxErr := ctx.Err(); ctxErr != nil {
					return nil, fmt.Errorf("resolve versions: %w", ctxErr)
				}
				u.logSkip(use.source, err)
				latest = ""
			}
			latestBySource[use.source] = latest
		}
		if latest == "" {
			continue
		}
		if !isNewer(latest, use.version) {
			u.log.Info("Module is up to date or newer", logKeySource, use.source, "current", use.version, "latest", latest)
			continue
		}
		printf(u.out, "📦 Update available: %s: %s -> %s in %s\n", use.source, use.version, latest, name)
		if u.opts.DryRun {
			sum.Updated = append(sum.Updated, fmt.Sprintf("%s (%s -> %s) [dry-run]", use.source, use.version, latest))
			continue
		}
		p := pending[use.source]
		if p == nil {
			p = &pendingModule{latest: latest, current: use.version}
			pending[use.source] = p
		}
		if !slices.Contains(p.files, use.file) {
			p.files = append(p.files, use.file)
		}
	}
	return pending, nil
}

// logSkip explains why a module was not considered for an update.
func (u *Updater) logSkip(source string, err error) {
	switch {
	case errors.Is(err, registry.ErrNotRegistrySource):
		u.log.Info("Skipping non-registry module", logKeySource, source)
	case errors.Is(err, registry.ErrNoEligibleVersion):
		u.log.Info("Skipping module: no version old enough", logKeySource, source)
	default:
		u.log.Warn("Could not determine latest version; skipping", logKeySource, source, "error", err)
	}
}

// scan returns every module block with literal source and version.
func (u *Updater) scan(ctx context.Context) ([]moduleUse, error) {
	files, err := u.terraformFiles()
	if err != nil {
		return nil, fmt.Errorf("list terraform files: %w", err)
	}
	var uses []moduleUse
	for _, file := range files {
		refs, extractErr := modulefile.ExtractFile(ctx, file)
		if extractErr != nil {
			if ctxErr := ctx.Err(); ctxErr != nil {
				return nil, fmt.Errorf("scan: %w", ctxErr)
			}
			u.log.Warn("Skipping unparsable file", "file", file, "error", extractErr)
			continue
		}
		for i := range refs {
			uses = append(uses, moduleUse{file: file, source: refs[i].Source, version: refs[i].Version})
		}
	}
	return uses, nil
}

// terraformFiles lists the .tf files of the directory (and its sub-directories
// when Recursive is set), skipping the .terraform working directories.
func (u *Updater) terraformFiles() ([]string, error) {
	var files []string
	if !u.opts.Recursive {
		entries, err := os.ReadDir(u.opts.Dir)
		if err != nil {
			return nil, fmt.Errorf("read directory %s: %w", u.opts.Dir, err)
		}
		for _, e := range entries {
			if e.Type().IsRegular() && filepath.Ext(e.Name()) == terraformExt {
				files = append(files, filepath.Join(u.opts.Dir, e.Name()))
			}
		}
		return files, nil
	}
	err := filepath.WalkDir(u.opts.Dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return fmt.Errorf("walk %s: %w", path, err)
		}
		if d.IsDir() && d.Name() == terraformDotDir {
			return fs.SkipDir
		}
		if d.Type().IsRegular() && filepath.Ext(path) == terraformExt {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("scan %s: %w", u.opts.Dir, err)
	}
	return files, nil
}

// isNewer reports whether latest is strictly newer than the version in current.
// A current value without any number (for example "latest") is always replaced.
func isNewer(latest, current string) bool {
	base := versionNumber.FindString(current)
	if base == "" {
		return true
	}
	return registry.CompareVersions(latest, base) > 0
}

// printf writes progress to w; a failed write to the user's terminal has no
// other channel to be reported on.
func printf(w io.Writer, format string, args ...any) {
	_, _ = fmt.Fprintf(w, format, args...)
}
