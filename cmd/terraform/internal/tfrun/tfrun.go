// Package tfrun runs Terraform CLI commands in a working directory.
package tfrun

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
)

const (
	// terraformBin is always looked up on PATH; the command name is never configurable.
	terraformBin = "terraform"
	// flagNoColor keeps terraform output free of ANSI colors.
	flagNoColor = "-no-color"
)

// Runner executes the terraform binary found on PATH.
type Runner struct{}

// Init runs "terraform init" with args in dir and returns the combined output.
func (Runner) Init(ctx context.Context, dir string, args ...string) (string, error) {
	out, err := combined(ctx, dir, append([]string{"init", flagNoColor}, args...))
	if err != nil {
		return out, fmt.Errorf("terraform init: %w", err)
	}
	return out, nil
}

// Plan runs "terraform plan" with args in dir and returns the combined output.
func (Runner) Plan(ctx context.Context, dir string, args ...string) (string, error) {
	out, err := combined(ctx, dir, append([]string{"plan", flagNoColor, "-input=false"}, args...))
	if err != nil {
		return out, fmt.Errorf("terraform plan: %w", err)
	}
	return out, nil
}

// Show renders a saved plan file as text. Only stdout is returned; stderr is
// attached to the error on failure.
func (Runner) Show(ctx context.Context, dir, planFile string) (string, error) {
	var stdout, stderr bytes.Buffer
	cmd := newCommand(ctx, dir, []string{"show", flagNoColor, planFile})
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("terraform show: %w: %s", err, stderr.String())
	}
	return stdout.String(), nil
}

// Validate runs "terraform validate" in dir and returns the combined output.
func (Runner) Validate(ctx context.Context, dir string) (string, error) {
	out, err := combined(ctx, dir, []string{"validate", flagNoColor})
	if err != nil {
		return out, fmt.Errorf("terraform validate: %w", err)
	}
	return out, nil
}

// combined runs terraform with args in dir and returns stdout and stderr together.
func combined(ctx context.Context, dir string, args []string) (string, error) {
	out, err := newCommand(ctx, dir, args).CombinedOutput()
	return string(out), err //nolint:wrapcheck // the exported callers add the command name as context
}

// newCommand builds the terraform command for args, running in dir.
func newCommand(ctx context.Context, dir string, args []string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, terraformBin, args...) //nolint:gosec // G204 - the command is the constant "terraform" and args are built by this program
	cmd.Dir = dir
	return cmd
}
