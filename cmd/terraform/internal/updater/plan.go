package updater

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	// baselinePlan and currentPlan are the plan file names inside a project's artifact directory.
	baselinePlan = ".terraform_baseline.plan"
	currentPlan  = ".terraform_current.plan"
)

// artifactDir returns the per-project directory for plan files inside the backup directory.
func (u *Updater) artifactDir(project string) (string, error) {
	// Flatten the project path into one directory name so projects never collide.
	rel := strings.ReplaceAll(strings.TrimPrefix(project, string(filepath.Separator)), string(filepath.Separator), "__")
	dir := filepath.Join(u.backupDir, rel)
	if err := os.MkdirAll(dir, dirPerm); err != nil {
		return "", fmt.Errorf("create artifact directory: %w", err)
	}
	return dir, nil
}

// backendArgs returns the init arguments for terraform.<env>.tfbackend when it exists.
func (u *Updater) backendArgs(project string) []string {
	name := "terraform." + u.opts.Env + ".tfbackend"
	if fileExists(filepath.Join(project, name)) {
		return []string{"-reconfigure", "-backend-config=" + name}
	}
	return nil
}

// createBaseline initialises the project and saves its plan before any update.
func (u *Updater) createBaseline(ctx context.Context, project string) error {
	out, err := u.runner.Init(ctx, project, append([]string{"-input=false"}, u.backendArgs(project)...)...)
	if err != nil {
		u.reportFailure("BASELINE INIT", out)
		return fmt.Errorf("init %s: %w", project, err)
	}
	dir, err := u.artifactDir(project)
	if err != nil {
		return fmt.Errorf("baseline plan %s: %w", project, err)
	}
	planFile := filepath.Join(dir, baselinePlan)
	out, err = u.runner.Plan(ctx, project, append([]string{"-lock=false", "-out=" + planFile}, u.varFileArgs(project)...)...)
	if err != nil {
		u.reportFailure("BASELINE PLAN", out)
		return fmt.Errorf("baseline plan %s: %w", project, err)
	}
	u.log.Info("Baseline plan created", "project", project)
	return nil
}

// createBaselines creates a baseline plan for every project touched by pending.
// A failure aborts the run: without a baseline no update can be verified.
func (u *Updater) createBaselines(ctx context.Context, pending map[string]*pendingModule) error {
	var files []string
	for _, p := range pending {
		files = append(files, p.files...)
	}
	// Every affected project needs its own baseline, even when several modules share it.
	for _, project := range uniqueProjects(files) {
		u.log.Info("Creating baseline plan", "project", project)
		if err := u.createBaseline(ctx, project); err != nil {
			return fmt.Errorf("cannot proceed without baseline plans: %w", err)
		}
		u.baselines[project] = true
	}
	return nil
}

// reportDiff explains how the current plan differs from the baseline.
func (u *Updater) reportDiff(baseline, current string) {
	u.log.Warn("Infrastructure changes detected between baseline and current plan")
	if !u.opts.Verbose {
		u.log.Info("Use --verbose to see detailed plan content differences")
		return
	}
	// Verbose mode prints the full diff plus the resource counts the shell script used to show.
	lines := diffLines(baseline, current)
	printf(u.out, "===== TERRAFORM SHOW DIFFERENCES =====\n%s\n", strings.Join(lines, "\n"))
	added, removed, modified := countChanges(lines)
	printf(u.out, "Resources to be added: %d\nResources to be removed: %d\nResources to be modified: %d\n", added, removed, modified)
}

// reportFailure prints the command output of a failed step in verbose mode.
func (u *Updater) reportFailure(title, output string) {
	u.log.Error("Terraform step failed", "step", title)
	// The raw output can be long, so it is only shown when the user asks for it.
	if u.opts.Verbose {
		printf(u.out, "===== %s ERROR OUTPUT =====\n%s\n", title, output)
	}
}

// validateProject re-initialises the project with the updated modules, runs
// validate and plan, and requires the plan to equal the baseline plan.
func (u *Updater) validateProject(ctx context.Context, project string) error {
	// -upgrade makes terraform download the module versions that were just written.
	out, err := u.runner.Init(ctx, project, append([]string{"-input=false", "-upgrade"}, u.backendArgs(project)...)...)
	if err != nil {
		u.reportFailure("INIT", out)
		return fmt.Errorf("init after update: %w", err)
	}
	out, err = u.runner.Validate(ctx, project)
	if err != nil {
		u.reportFailure("VALIDATE", out)
		return fmt.Errorf("validate: %w", err)
	}
	dir, err := u.artifactDir(project)
	if err != nil {
		return fmt.Errorf("current plan: %w", err)
	}
	currentFile := filepath.Join(dir, currentPlan)
	out, err = u.runner.Plan(ctx, project, append([]string{"-lock=false", "-out=" + currentFile}, u.varFileArgs(project)...)...)
	if err != nil {
		u.reportFailure("CURRENT PLAN", out)
		return fmt.Errorf("current plan: %w", err)
	}
	baseline, err := u.runner.Show(ctx, project, filepath.Join(dir, baselinePlan))
	if err != nil {
		return fmt.Errorf("show baseline plan: %w", err)
	}
	current, err := u.runner.Show(ctx, project, currentFile)
	if err != nil {
		return fmt.Errorf("show current plan: %w", err)
	}
	// Identical rendered plans mean the module bump changes nothing in the infrastructure.
	if baseline == current {
		u.log.Info("No infrastructure changes detected", "project", project)
		return nil
	}
	u.reportDiff(baseline, current)
	return ErrPlanChanged
}

// varFileArgs returns the plan arguments for terraform.<env>.tfvars when it exists.
func (u *Updater) varFileArgs(project string) []string {
	name := "terraform." + u.opts.Env + ".tfvars"
	if fileExists(filepath.Join(project, name)) {
		return []string{"-var-file=" + name}
	}
	return nil
}
