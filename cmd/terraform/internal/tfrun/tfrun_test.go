package tfrun

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// useFakeTerraform puts an executable named terraform first (and only) on PATH.
// It prints its working directory and arguments, and fails when the first
// argument equals failOn. Tests using it change PATH and so cannot run in parallel.
func useFakeTerraform(t *testing.T, failOn string) {
	t.Helper()
	dir := t.TempDir()
	script := "#!/bin/sh\n" +
		"echo \"cwd=$(pwd) args=$*\"\n" +
		"if [ \"$1\" = \"" + failOn + "\" ]; then echo boom >&2; exit 3; fi\n"
	if err := os.WriteFile(filepath.Join(dir, "terraform"), []byte(script), 0o700); err != nil { //nolint:gosec // G306 - the test double must be executable
		t.Fatalf("setup: %v", err)
	}
	t.Setenv("PATH", dir)
}

//nolint:paralleltest // t.Setenv changes PATH for the whole process
func TestRunner(t *testing.T) {
	dir := t.TempDir()
	tests := []struct {
		name    string
		failOn  string
		call    func(r Runner) (string, error)
		want    []string
		wantErr bool
	}{
		{
			name:   "init passes args in dir",
			failOn: "never",
			call:   func(r Runner) (string, error) { return r.Init(context.Background(), dir, "-upgrade") },
			want:   []string{"cwd=" + dir, "args=init -no-color -upgrade"},
		},
		{
			name:   "validate",
			failOn: "never",
			call:   func(r Runner) (string, error) { return r.Validate(context.Background(), dir) },
			want:   []string{"args=validate -no-color"},
		},
		{
			name:   "plan is non-interactive",
			failOn: "never",
			call:   func(r Runner) (string, error) { return r.Plan(context.Background(), dir, "-lock=false") },
			want:   []string{"args=plan -no-color -input=false -lock=false"},
		},
		{
			name:   "show returns stdout",
			failOn: "never",
			call:   func(r Runner) (string, error) { return r.Show(context.Background(), dir, "x.plan") },
			want:   []string{"args=show -no-color x.plan"},
		},
		{
			name:    "failure keeps output and wraps error",
			failOn:  "plan",
			call:    func(r Runner) (string, error) { return r.Plan(context.Background(), dir) },
			want:    []string{"boom"},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) { //nolint:paralleltest // see above
			useFakeTerraform(t, tt.failOn)
			out, err := tt.call(Runner{})
			if (err != nil) != tt.wantErr {
				t.Fatalf("error = %v, wantErr %v", err, tt.wantErr)
			}
			for _, want := range tt.want {
				if !strings.Contains(out, want) {
					t.Errorf("output %q missing %q", out, want)
				}
			}
		})
	}
}

//nolint:paralleltest // t.Setenv changes PATH for the whole process
func TestRunnerMissingBinary(t *testing.T) {
	// An empty directory as PATH means no terraform can be found.
	t.Setenv("PATH", t.TempDir())

	if _, err := (Runner{}).Validate(context.Background(), t.TempDir()); err == nil {
		t.Fatal("Validate() without terraform on PATH returned nil error")
	}
	if _, err := (Runner{}).Show(context.Background(), t.TempDir(), "x"); err == nil {
		t.Fatal("Show() without terraform on PATH returned nil error")
	}
}
