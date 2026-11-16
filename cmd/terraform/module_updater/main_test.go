package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/y-miyazaki/config/cmd/terraform/internal/registry"
)

const testModule = `module "vpc" {
  source  = "acme/vpc/aws"
  version = "1.0.0"
}
`

type stubResolver struct{ version string }

func (s stubResolver) LatestEligible(_ context.Context, _ string, _ time.Duration) (string, error) {
	if s.version == "" {
		return "", registry.ErrNoEligibleVersion
	}
	return s.version, nil
}

// stubRunner pretends terraform works; the current plan differs from the baseline
// when changed is set.
type stubRunner struct{ changed bool }

func (stubRunner) Init(context.Context, string, ...string) (string, error)     { return "", nil }
func (stubRunner) Validate(context.Context, string) (string, error)            { return "", nil }
func (stubRunner) Plan(context.Context, string, ...string) (string, error)     { return "", nil }
func (s stubRunner) Show(_ context.Context, _, planFile string) (string, error) {
	if s.changed && strings.HasSuffix(planFile, ".terraform_current.plan") {
		return "changed", nil
	}
	return "same", nil
}

func newProject(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.tf"), []byte(testModule), 0o600); err != nil {
		t.Fatalf("setup: %v", err)
	}
	return dir
}

func TestRun(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		args       func(dir string) []string
		deps       deps
		wantCode   int
		wantStdout string
		wantStderr string
		wantFile   string
	}{
		{
			name:       "check only lists modules",
			args:       func(d string) []string { return []string{"module_updater", "--check-only", d} },
			deps:       deps{resolver: stubResolver{}, runner: stubRunner{}},
			wantStdout: "Found: acme/vpc/aws (current: 1.0.0) in main.tf",
			wantFile:   `"1.0.0"`,
		},
		{
			name:       "dry run reports the update",
			args:       func(d string) []string { return []string{"module_updater", "-d", d} },
			deps:       deps{resolver: stubResolver{version: "2.0.0"}, runner: stubRunner{}},
			wantStdout: "[dry-run]",
			wantFile:   `"1.0.0"`,
		},
		{
			name:       "update with verified plan",
			args:       func(d string) []string { return []string{"module_updater", d} },
			deps:       deps{resolver: stubResolver{version: "2.0.0"}, runner: stubRunner{}},
			wantStdout: "Modules updated: 1",
			wantFile:   `"2.0.0"`,
		},
		{
			name:       "no plan mode skips terraform",
			args:       func(d string) []string { return []string{"module_updater", "--no-plan", "--min-release-age", "0", d} },
			deps:       deps{resolver: stubResolver{version: "2.0.0"}, runner: stubRunner{}},
			wantStdout: "(no plan mode)",
			wantFile:   `"2.0.0"`,
		},
		{
			name:       "plan difference fails the run and rolls back",
			args:       func(d string) []string { return []string{"module_updater", d} },
			deps:       deps{resolver: stubResolver{version: "2.0.0"}, runner: stubRunner{changed: true}},
			wantCode:   exitError,
			wantStdout: "Modules failed: 1",
			wantStderr: "1 module(s) failed to update",
			wantFile:   `"1.0.0"`,
		},
		{
			name:       "missing directory argument is a usage error",
			args:       func(string) []string { return []string{"module_updater"} },
			deps:       deps{resolver: stubResolver{}, runner: stubRunner{}},
			wantCode:   exitUsage,
			wantStderr: "exactly one terraform directory is required",
		},
		{
			name:       "invalid minimum age is a usage error",
			args:       func(d string) []string { return []string{"module_updater", "--min-release-age", "soon", d} },
			deps:       deps{resolver: stubResolver{}, runner: stubRunner{}},
			wantCode:   exitUsage,
			wantStderr: "invalid minimum release age",
		},
		{
			name:       "unreadable directory is a runtime error",
			args:       func(string) []string { return []string{"module_updater", "/nonexistent/terraform"} },
			deps:       deps{resolver: stubResolver{}, runner: stubRunner{}},
			wantCode:   exitError,
			wantStderr: "no such file",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := newProject(t)
			var stdout, stderr bytes.Buffer
			code := run(context.Background(), tt.args(dir), &stdout, &stderr, tt.deps)
			if code != tt.wantCode {
				t.Fatalf("run() = %d, want %d (stderr: %s)", code, tt.wantCode, stderr.String())
			}
			if !strings.Contains(stdout.String(), tt.wantStdout) {
				t.Errorf("stdout = %q, want to contain %q", stdout.String(), tt.wantStdout)
			}
			if !strings.Contains(stderr.String(), tt.wantStderr) {
				t.Errorf("stderr = %q, want to contain %q", stderr.String(), tt.wantStderr)
			}
			if tt.wantFile != "" {
				b, err := os.ReadFile(filepath.Join(dir, "main.tf")) //nolint:gosec // G304 - the path is a test temp file
				if err != nil {
					t.Fatalf("read back: %v", err)
				}
				if !strings.Contains(string(b), tt.wantFile) {
					t.Errorf("main.tf = %q, want to contain %q", b, tt.wantFile)
				}
			}
		})
	}
}

func TestParseMinAge(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		value   string
		want    time.Duration
		wantErr error
	}{
		{name: "days", value: "7d", want: 7 * 24 * time.Hour},
		{name: "zero days", value: "0d", want: 0},
		{name: "plain zero", value: "0", want: 0},
		{name: "hours", value: "72h", want: 72 * time.Hour},
		{name: "surrounding spaces", value: " 3d ", want: 3 * 24 * time.Hour},
		{name: "negative days", value: "-1d", wantErr: ErrInvalidMinAge},
		{name: "negative duration", value: "-5h", wantErr: ErrInvalidMinAge},
		{name: "not a number", value: "xd", wantErr: ErrInvalidMinAge},
		{name: "too many days", value: "99999d", wantErr: ErrInvalidMinAge},
		{name: "empty", value: "", wantErr: ErrInvalidMinAge},
		{name: "garbage", value: "soon", wantErr: ErrInvalidMinAge},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := parseMinAge(tt.value)
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("parseMinAge(%q) error = %v, want %v", tt.value, err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseMinAge(%q) unexpected error: %v", tt.value, err)
			}
			if got != tt.want {
				t.Fatalf("parseMinAge(%q) = %v, want %v", tt.value, got, tt.want)
			}
		})
	}
}
