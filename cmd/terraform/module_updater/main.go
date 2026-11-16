// Package main is the entry point of module_updater, a CLI that moves the
// Terraform registry modules of a directory to the newest version that has been
// published for a minimum amount of time, and verifies every update by
// comparing terraform plans before and after the change.
//
// Usage:
//
//	module_updater [options] <terraform_directory>
//
// Every module is updated on its own. Unless --no-plan is given, a baseline plan
// is created first and an update is rolled back when the plan after the update
// differs from the baseline. Versions younger than --min-release-age (default
// 7d) are never selected, which keeps freshly published releases out.
//
// Build with `make build` in cmd/terraform; the linux/arm64 binary is committed
// at scripts/terraform/module_updater.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/urfave/cli/v3"

	"github.com/y-miyazaki/config/cmd/terraform/internal/registry"
	"github.com/y-miyazaki/config/cmd/terraform/internal/tfrun"
	"github.com/y-miyazaki/config/cmd/terraform/internal/updater"
)

const (
	// exitError is the exit status for runtime failures and failed module updates.
	exitError = 1
	// exitUsage is the exit status for wrong command line usage.
	exitUsage = 2

	// defaultMinReleaseAge keeps releases younger than a week out of reach.
	defaultMinReleaseAge = "7d"
	// defaultEnv selects terraform.dev.tfvars / terraform.dev.tfbackend.
	defaultEnv = "dev"
	// defaultTimeout is the default upper bound of a whole run.
	defaultTimeout = 30 * time.Minute

	hoursPerDay = 24
	// maxMinAgeDays rejects absurd values that would overflow a time.Duration.
	maxMinAgeDays = 36500
)

var (
	// ErrInvalidMinAge is returned for an unparsable --min-release-age.
	ErrInvalidMinAge = errors.New("invalid minimum release age")

	// version is set at build time via -ldflags "-X main.version=...".
	version = "dev"
)

// deps are the collaborators of a run; tests replace them.
type deps struct {
	resolver updater.Resolver
	runner   updater.Runner
}

// exitCoder is implemented by errors that carry a process exit status.
type exitCoder interface {
	ExitCode() int
}

// exitStatusError is an error that carries the exit status of the process.
type exitStatusError struct {
	cause error
	msg   string
	code  int
}

func (e *exitStatusError) Error() string {
	if e.cause != nil {
		return e.cause.Error()
	}
	return e.msg
}

func (e *exitStatusError) ExitCode() int { return e.code }

func (e *exitStatusError) Unwrap() error { return e.cause }

func main() {
	d := deps{resolver: registry.New(), runner: tfrun.Runner{}}
	os.Exit(run(context.Background(), os.Args, os.Stdout, os.Stderr, d))
}

// run executes the CLI and maps the resulting error to a process exit status.
func run(ctx context.Context, args []string, stdout, stderr io.Writer, d deps) int {
	err := newApp(stdout, stderr, d).Run(ctx, args)
	if err == nil {
		return 0
	}
	if msg := err.Error(); msg != "" {
		printf(stderr, "module_updater: %v\n", msg)
	}
	var coder exitCoder
	if errors.As(err, &coder) {
		return coder.ExitCode()
	}
	return exitError
}

// newApp builds the CLI application writing to the given streams.
func newApp(stdout, stderr io.Writer, d deps) *cli.Command {
	return &cli.Command{
		Name:      "module_updater",
		Usage:     "Update Terraform registry modules and verify each update with a plan comparison",
		ArgsUsage: "<terraform_directory>",
		Version:   version,
		Writer:    stdout,
		ErrWriter: stderr,
		// run maps errors to exit statuses, so the library must not call os.Exit itself.
		ExitErrHandler: func(context.Context, *cli.Command, error) {},
		Flags: []cli.Flag{
			&cli.BoolFlag{Name: "verbose", Usage: "Show debug logs and detailed plan differences"},
			&cli.BoolFlag{Name: "dry-run", Aliases: []string{"d"}, Usage: "List the updates without changing files"},
			&cli.BoolFlag{Name: "check-only", Aliases: []string{"c"}, Usage: "List the modules found without looking up versions"},
			&cli.BoolFlag{Name: "recursive", Aliases: []string{"r"}, Usage: "Search sub-directories for Terraform files"},
			&cli.BoolFlag{Name: "no-plan", Usage: "Skip the baseline and verification plans"},
			&cli.StringFlag{
				Name:  "min-release-age",
				Usage: "Only select versions published at least this long ago (for example 7d, 72h; 0 disables)",
				Value: defaultMinReleaseAge,
			},
			&cli.StringFlag{
				Name:    "env",
				Usage:   "Environment selecting terraform.<env>.tfvars and terraform.<env>.tfbackend",
				Sources: cli.EnvVars("ENV"),
				Value:   defaultEnv,
			},
			&cli.DurationFlag{
				Name:  "timeout",
				Usage: "Maximum total execution time (for example 30m, 2h). Set 0 to disable",
				Value: defaultTimeout,
			},
		},
		Action: action(stdout, stderr, d),
	}
}

func action(stdout, stderr io.Writer, d deps) cli.ActionFunc {
	return func(ctx context.Context, cmd *cli.Command) error {
		if cmd.NArg() != 1 {
			return &exitStatusError{msg: "exactly one terraform directory is required", code: exitUsage}
		}
		minAge, err := parseMinAge(cmd.String("min-release-age"))
		if err != nil {
			return &exitStatusError{cause: err, code: exitUsage}
		}
		dir, err := filepath.Abs(cmd.Args().First())
		if err != nil {
			return &exitStatusError{cause: err, code: exitError}
		}
		runCtx, cancel := createRunContext(ctx, cmd.Duration("timeout"))
		defer cancel()

		opts := updater.Options{
			Dir:           dir,
			Env:           cmd.String("env"),
			MinReleaseAge: minAge,
			Verbose:       cmd.Bool("verbose"),
			DryRun:        cmd.Bool("dry-run"),
			CheckOnly:     cmd.Bool("check-only"),
			Recursive:     cmd.Bool("recursive"),
			NoPlan:        cmd.Bool("no-plan"),
		}
		level := slog.LevelInfo
		if opts.Verbose {
			level = slog.LevelDebug
		}
		logger := slog.New(slog.NewTextHandler(stderr, &slog.HandlerOptions{Level: level}))
		logger.Info("Module updater started", "directory", dir, "min_release_age", minAge.String(), "env", opts.Env)

		sum, err := updater.New(opts, d.resolver, d.runner, logger, stdout).Run(runCtx)
		printSummary(stdout, &sum)
		if err != nil {
			return &exitStatusError{cause: err, code: exitError}
		}
		if len(sum.Failed) > 0 {
			return &exitStatusError{msg: fmt.Sprintf("%d module(s) failed to update", len(sum.Failed)), code: exitError}
		}
		return nil
	}
}

// createRunContext cancels on SIGINT/SIGTERM and, when timeout > 0, after timeout.
func createRunContext(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	signalCtx, stop := signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
	if timeout <= 0 {
		return signalCtx, stop
	}
	timeoutCtx, cancel := context.WithTimeout(signalCtx, timeout)
	return timeoutCtx, func() {
		cancel()
		stop()
	}
}

// parseMinAge parses "7d" style day counts as well as time.ParseDuration values.
func parseMinAge(value string) (time.Duration, error) {
	trimmed := strings.TrimSpace(value)
	if days, ok := strings.CutSuffix(trimmed, "d"); ok {
		n, err := strconv.Atoi(days)
		if err != nil || n < 0 || n > maxMinAgeDays {
			return 0, fmt.Errorf("%w: %q", ErrInvalidMinAge, trimmed)
		}
		return time.Duration(n) * hoursPerDay * time.Hour, nil
	}
	d, err := time.ParseDuration(trimmed)
	if err != nil || d < 0 {
		return 0, fmt.Errorf("%w: %q", ErrInvalidMinAge, trimmed)
	}
	return d, nil
}

func printSummary(w io.Writer, sum *updater.Summary) {
	printf(w, "\n📊 Update Summary\n")
	printf(w, "  Total modules scanned: %d\n", sum.Total)
	printf(w, "  Modules updated: %d\n", len(sum.Updated))
	printf(w, "  Modules failed: %d\n", len(sum.Failed))
	if len(sum.Updated) > 0 {
		printf(w, "\n✅ Updated modules:\n")
		for _, m := range sum.Updated {
			printf(w, "  - %s\n", m)
		}
	}
	if len(sum.Failed) > 0 {
		printf(w, "\n❌ Failed to update modules:\n")
		for _, m := range sum.Failed {
			printf(w, "  - %s\n", m)
		}
	}
}

// printf writes formatted output to w. A failed write to stdout/stderr has no
// other channel to be reported on, so the error is intentionally dropped.
func printf(w io.Writer, format string, args ...any) {
	_, _ = fmt.Fprintf(w, format, args...)
}
