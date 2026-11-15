package updater

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/y-miyazaki/config/cmd/terraform/internal/registry"
)

var errTestBoom = errors.New("boom")

const (
	vpcSource = "acme/vpc/aws"

	vpcModule = `module "vpc" {
  source  = "acme/vpc/aws"
  version = "1.0.0"
}
`
	rootFile = "main.tf"
)

type fakeResolver struct {
	versions map[string]string
	errs     map[string]error
	calls    int
}

func (f *fakeResolver) LatestEligible(_ context.Context, source string, _ time.Duration) (string, error) {
	f.calls++
	if err, ok := f.errs[source]; ok {
		return "", err
	}
	if v, ok := f.versions[source]; ok {
		return v, nil
	}
	return "", registry.ErrNotRegistrySource
}

type fakeRunner struct {
	showFn         func(planFile string) string
	calls          []string
	initCalls      int
	planCalls      int
	failInitOnCall int
	failPlanOnCall int
}

func (f *fakeRunner) Init(_ context.Context, dir string, args ...string) (string, error) {
	f.initCalls++
	f.calls = append(f.calls, "init "+filepath.Base(dir)+" "+strings.Join(args, " "))
	if f.failInitOnCall == f.initCalls {
		return "init output", errTestBoom
	}
	return "", nil
}

func (f *fakeRunner) Validate(_ context.Context, dir string) (string, error) {
	f.calls = append(f.calls, "validate "+filepath.Base(dir))
	return "", nil
}

func (f *fakeRunner) Plan(_ context.Context, dir string, args ...string) (string, error) {
	f.planCalls++
	f.calls = append(f.calls, "plan "+filepath.Base(dir))
	if f.failPlanOnCall == f.planCalls {
		return "plan output", errTestBoom
	}
	return "", nil
}

func (f *fakeRunner) Show(_ context.Context, _, planFile string) (string, error) {
	if f.showFn != nil {
		return f.showFn(planFile), nil
	}
	return "plan: no changes", nil
}

func writeProject(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
			t.Fatalf("setup: %v", err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatalf("setup: %v", err)
		}
	}
	return dir
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path) //nolint:gosec // G304 - the path is a test temp file
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}

func TestUpdaterRun(t *testing.T) {
	t.Parallel()

	changedCurrent := func(planFile string) string {
		if strings.HasSuffix(planFile, currentPlan) {
			return "plan: changes"
		}
		return "plan: no changes"
	}
	noPlan := func(o *Options) { o.NoPlan = true }
	vpc := map[string]string{vpcSource: "2.0.0"}

	tests := []struct {
		name         string
		files        map[string]string
		opts         func(*Options)
		versions     map[string]string
		errs         map[string]error
		runner       *fakeRunner
		wantErr      error
		wantTotal    int
		wantUpdated  []string
		wantFailed   []string
		wantFiles    map[string]string
		wantOut      []string
		wantCalls    int
		wantResolver int
	}{
		{
			name:      "check only reports modules without changes",
			files:     map[string]string{rootFile: vpcModule},
			opts:      func(o *Options) { o.CheckOnly = true },
			runner:    &fakeRunner{},
			wantTotal: 1,
			wantOut:   []string{"Found: acme/vpc/aws (current: 1.0.0)"},
			wantFiles: map[string]string{rootFile: `"1.0.0"`},
		},
		{
			name:         "dry run lists updates and leaves files alone",
			files:        map[string]string{rootFile: vpcModule},
			opts:         func(o *Options) { o.DryRun = true },
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"[dry-run]"},
			wantOut:      []string{"Update available: acme/vpc/aws: 1.0.0 -> 2.0.0"},
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "no plan mode updates without terraform",
			files:        map[string]string{rootFile: vpcModule},
			opts:         noPlan,
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"acme/vpc/aws (1.0.0 -> 2.0.0) [1 files] (no plan mode)"},
			wantFiles:    map[string]string{rootFile: `"2.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "unchanged plan keeps the update",
			files:        map[string]string{rootFile: vpcModule},
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"acme/vpc/aws (1.0.0 -> 2.0.0) [1 files]"},
			wantFiles:    map[string]string{rootFile: `"2.0.0"`},
			wantCalls:    5,
			wantResolver: 1,
		},
		{
			name:         "changed plan rolls the update back",
			files:        map[string]string{rootFile: vpcModule},
			versions:     vpc,
			runner:       &fakeRunner{showFn: changedCurrent},
			wantTotal:    1,
			wantFailed:   []string{vpcSource},
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "baseline failure aborts before touching files",
			files:        map[string]string{rootFile: vpcModule},
			versions:     vpc,
			runner:       &fakeRunner{failInitOnCall: 1},
			wantErr:      errTestBoom,
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "failing current plan rolls back",
			files:        map[string]string{rootFile: vpcModule},
			versions:     vpc,
			runner:       &fakeRunner{failPlanOnCall: 2},
			wantTotal:    1,
			wantFailed:   []string{vpcSource},
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "same version is not an update",
			files:        map[string]string{rootFile: vpcModule},
			opts:         noPlan,
			versions:     map[string]string{vpcSource: "1.0.0"},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "never downgrades a newer version",
			files:        map[string]string{rootFile: strings.Replace(vpcModule, "1.0.0", "5.0.0", 1)},
			opts:         noPlan,
			versions:     map[string]string{vpcSource: "4.0.0"},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"5.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "constraint above the candidate is kept",
			files:        map[string]string{rootFile: strings.Replace(vpcModule, `"1.0.0"`, `">= 6.0"`, 1)},
			opts:         noPlan,
			versions:     map[string]string{vpcSource: "5.9.0"},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `">= 6.0"`},
			wantResolver: 1,
		},
		{
			name:         "constraint below the candidate is replaced by the version",
			files:        map[string]string{rootFile: strings.Replace(vpcModule, `"1.0.0"`, `"~> 1.0"`, 1)},
			opts:         noPlan,
			versions:     map[string]string{vpcSource: "1.2.0"},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"(~> 1.0 -> 1.2.0)"},
			wantFiles:    map[string]string{rootFile: `"1.2.0"`},
			wantResolver: 1,
		},
		{
			name:         "non registry module is skipped",
			files:        map[string]string{rootFile: vpcModule},
			opts:         noPlan,
			errs:         map[string]error{vpcSource: registry.ErrNotRegistrySource},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "no version old enough is skipped",
			files:        map[string]string{rootFile: vpcModule},
			opts:         noPlan,
			errs:         map[string]error{vpcSource: registry.ErrNoEligibleVersion},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "registry failure is skipped",
			files:        map[string]string{rootFile: vpcModule},
			opts:         noPlan,
			errs:         map[string]error{vpcSource: errTestBoom},
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantFiles:    map[string]string{rootFile: `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "same source in two files is updated everywhere",
			files:        map[string]string{rootFile: vpcModule, "other.tf": vpcModule},
			opts:         noPlan,
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    2,
			wantUpdated:  []string{"[2 files]"},
			wantFiles:    map[string]string{rootFile: `"2.0.0"`, "other.tf": `"2.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "changed plan rolls back every file of the module",
			files:        map[string]string{rootFile: vpcModule, "other.tf": vpcModule},
			versions:     vpc,
			runner:       &fakeRunner{showFn: changedCurrent},
			wantTotal:    2,
			wantFailed:   []string{vpcSource},
			wantFiles:    map[string]string{rootFile: `"1.0.0"`, "other.tf": `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "subdirectories are ignored without recursion",
			files:        map[string]string{"sub/main.tf": vpcModule},
			opts:         noPlan,
			versions:     vpc,
			runner:       &fakeRunner{},
			wantFiles:    map[string]string{"sub/main.tf": `"1.0.0"`},
			wantResolver: 0,
		},
		{
			name:         "recursion finds nested modules",
			files:        map[string]string{"sub/main.tf": vpcModule, ".terraform/ignored.tf": vpcModule},
			opts:         func(o *Options) { o.NoPlan = true; o.Recursive = true },
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"[1 files]"},
			wantFiles:    map[string]string{"sub/main.tf": `"2.0.0"`, ".terraform/ignored.tf": `"1.0.0"`},
			wantResolver: 1,
		},
		{
			name:         "unparsable file is skipped",
			files:        map[string]string{rootFile: vpcModule, "bad.tf": `module "a" {`},
			opts:         noPlan,
			versions:     vpc,
			runner:       &fakeRunner{},
			wantTotal:    1,
			wantUpdated:  []string{"[1 files]"},
			wantFiles:    map[string]string{rootFile: `"2.0.0"`},
			wantResolver: 1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := writeProject(t, tt.files)
			opts := Options{Dir: dir, Env: "dev", MinReleaseAge: 7 * 24 * time.Hour}
			if tt.opts != nil {
				tt.opts(&opts)
			}
			resolver := &fakeResolver{versions: tt.versions, errs: tt.errs}
			var out bytes.Buffer
			u := New(opts, resolver, tt.runner, slog.New(slog.NewTextHandler(io.Discard, nil)), &out)

			sum, err := u.Run(context.Background())

			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("Run() error = %v, want %v", err, tt.wantErr)
				}
			} else if err != nil {
				t.Fatalf("Run() unexpected error: %v", err)
			}
			if sum.Total != tt.wantTotal {
				t.Errorf("Total = %d, want %d", sum.Total, tt.wantTotal)
			}
			assertContains(t, "Updated", sum.Updated, tt.wantUpdated)
			if len(sum.Updated) != len(tt.wantUpdated) {
				t.Errorf("Updated = %v, want %d entries", sum.Updated, len(tt.wantUpdated))
			}
			if !slices.Equal(sum.Failed, tt.wantFailed) {
				t.Errorf("Failed = %v, want %v", sum.Failed, tt.wantFailed)
			}
			for name, want := range tt.wantFiles {
				if got := readFile(t, filepath.Join(dir, name)); !strings.Contains(got, want) {
					t.Errorf("%s = %q, want to contain %q", name, got, want)
				}
			}
			for _, want := range tt.wantOut {
				if !strings.Contains(out.String(), want) {
					t.Errorf("output %q missing %q", out.String(), want)
				}
			}
			if tt.wantCalls != 0 && len(tt.runner.calls) != tt.wantCalls {
				t.Errorf("terraform calls = %v, want %d", tt.runner.calls, tt.wantCalls)
			}
			if resolver.calls != tt.wantResolver {
				t.Errorf("resolver calls = %d, want %d", resolver.calls, tt.wantResolver)
			}
			if _, statErr := os.Stat(filepath.Join(dir, backupRoot)); !errors.Is(statErr, os.ErrNotExist) {
				t.Errorf("backup directory was left behind (stat error: %v)", statErr)
			}
		})
	}
}

func assertContains(t *testing.T, name string, got, wants []string) {
	t.Helper()
	for _, want := range wants {
		if !slices.ContainsFunc(got, func(s string) bool { return strings.Contains(s, want) }) {
			t.Errorf("%s = %v, want an entry containing %q", name, got, want)
		}
	}
}

func TestUpdaterRunCanceledContext(t *testing.T) {
	t.Parallel()

	dir := writeProject(t, map[string]string{rootFile: vpcModule})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	u := New(Options{Dir: dir, Env: "dev"}, &fakeResolver{}, &fakeRunner{}, slog.New(slog.NewTextHandler(io.Discard, nil)), io.Discard)

	if _, err := u.Run(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("Run() error = %v, want context.Canceled", err)
	}
}

func TestUpdaterRunMissingDirectory(t *testing.T) {
	t.Parallel()

	u := New(Options{Dir: filepath.Join(t.TempDir(), "missing"), Env: "dev"}, &fakeResolver{}, &fakeRunner{}, slog.New(slog.NewTextHandler(io.Discard, nil)), io.Discard)
	if _, err := u.Run(context.Background()); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("Run() error = %v, want os.ErrNotExist", err)
	}
}

func TestUpdaterUsesEnvironmentFiles(t *testing.T) {
	t.Parallel()

	dir := writeProject(t, map[string]string{
		rootFile:                vpcModule,
		"terraform.stg.tfvars":  "",
		"terraform.stg.tfbackend": "",
	})
	runner := &fakeRunner{}
	u := New(Options{Dir: dir, Env: "stg"}, &fakeResolver{versions: map[string]string{vpcSource: "2.0.0"}}, runner, slog.New(slog.NewTextHandler(io.Discard, nil)), io.Discard)

	if _, err := u.Run(context.Background()); err != nil {
		t.Fatalf("Run() unexpected error: %v", err)
	}
	joined := strings.Join(runner.calls, "\n")
	if !strings.Contains(joined, "-reconfigure -backend-config=terraform.stg.tfbackend") {
		t.Errorf("init calls missing backend config:\n%s", joined)
	}
}

func TestProjectRoot(t *testing.T) {
	t.Parallel()

	dir := writeProject(t, map[string]string{
		"app/main.tf":          "",
		"app/modules/x/y.tf":   "",
		"lonely/inner/only.tf": "",
	})
	tests := []struct {
		name string
		file string
		want string
	}{
		{name: "file next to marker", file: "app/main.tf", want: "app"},
		{name: "walks up to the marker", file: "app/modules/x/y.tf", want: "app"},
		{name: "falls back to the file directory", file: "lonely/inner/only.tf", want: "lonely/inner"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := projectRoot(filepath.Join(dir, tt.file))
			if want := filepath.Join(dir, tt.want); got != want {
				t.Fatalf("projectRoot(%q) = %q, want %q", tt.file, got, want)
			}
		})
	}
}

func TestIsNewer(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		latest  string
		current string
		want    bool
	}{
		{name: "newer", latest: "2.0.0", current: "1.0.0", want: true},
		{name: "equal", latest: "1.0.0", current: "1.0.0"},
		{name: "older", latest: "1.0.0", current: "2.0.0"},
		{name: "constraint pins to newer", latest: "1.2.0", current: "~> 1.0", want: true},
		{name: "constraint already above", latest: "5.9.0", current: ">= 6.0"},
		{name: "no number is replaced", latest: "1.0.0", current: "latest", want: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := isNewer(tt.latest, tt.current); got != tt.want {
				t.Fatalf("isNewer(%q, %q) = %v, want %v", tt.latest, tt.current, got, tt.want)
			}
		})
	}
}

func TestDiffLines(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		a, b string
		want []string
	}{
		{name: "identical", a: "a\nb", b: "a\nb"},
		{name: "changed middle line", a: "a\nb\nc", b: "a\nx\nc", want: []string{"-b", "+x"}},
		{name: "added line", a: "a\nc", b: "a\nb\nc", want: []string{"+b"}},
		{name: "removed line", a: "a\nb\nc", b: "a\nc", want: []string{"-b"}},
		{name: "everything differs", a: "a", b: "b", want: []string{"-a", "+b"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := diffLines(tt.a, tt.b); !slices.Equal(got, tt.want) {
				t.Fatalf("diffLines() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDiffLinesLargeInputFallsBack(t *testing.T) {
	t.Parallel()

	var a, b []string
	for i := range 3000 {
		a = append(a, "a"+string(rune('0'+i%10)))
		b = append(b, "b"+string(rune('0'+i%10)))
	}
	got := diffLines(strings.Join(a, "\n"), strings.Join(b, "\n"))
	if len(got) != len(a)+len(b) {
		t.Fatalf("diffLines() returned %d lines, want %d", len(got), len(a)+len(b))
	}
}

func TestCountChanges(t *testing.T) {
	t.Parallel()

	lines := []string{
		"+resource \"aws_x\" \"y\"",
		"+data.aws_z.w",
		"-resource \"aws_old\" \"o\"",
		"+  ~ attr = 1",
		"-/+ replace (force replacement)",
		"+plain",
	}
	added, removed, modified := countChanges(lines)
	if added != 2 || removed != 1 || modified != 2 {
		t.Fatalf("countChanges() = %d, %d, %d, want 2, 1, 2", added, removed, modified)
	}
}
