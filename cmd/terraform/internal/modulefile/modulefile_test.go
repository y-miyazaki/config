package modulefile

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const fixture = `# module "commented" { source = "x/y/aws" version = "9.9.9" }
module "a" {
  source         = "terraform-aws-modules/vpc/aws"
  engine_version = "3.0.0"
  tags           = { x = "${var.y}" }
  note           = "}{ unbalanced"
  version        = "3.0.0" # keep this comment
}

module "b" {
  source  = "terraform-aws-modules/rds/aws"
  version = "3.0.0"

  nested {
    version = "0.0.1"
  }
}

module "c" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.0.0"
}

module "dynamic" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = var.s3_version
}

module "local" {
  source = "./modules/local"
}

module "heredoc" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "1.0.0"
  policy  = <<EOT
{ "a": "source = \"fake/mod/aws\""
EOT
}
`

func TestExtract(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		src     string
		want    []Ref
		wantErr error
	}{
		{
			name: "literal source and version only",
			src:  fixture,
			want: []Ref{
				{Source: "terraform-aws-modules/vpc/aws", Version: "3.0.0"},
				{Source: "terraform-aws-modules/rds/aws", Version: "3.0.0"},
				{Source: "terraform-aws-modules/vpc/aws", Version: "3.0.0"},
				{Source: "terraform-aws-modules/sqs/aws", Version: "1.0.0"},
			},
		},
		{name: "empty file", src: ""},
		{name: "invalid hcl", src: `module "a" {`, wantErr: ErrParse},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := Extract([]byte(tt.src), "main.tf")
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("Extract() error = %v, want %v", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("Extract() unexpected error: %v", err)
			}
			if !slices.Equal(got, tt.want) {
				t.Fatalf("Extract() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestUpdate(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		source      string
		version     string
		wantChanged int
		wantHas     []string
		wantErr     error
		src         string
	}{
		{
			name:        "updates every module with the matching source",
			source:      "terraform-aws-modules/vpc/aws",
			version:     "4.1.0",
			wantChanged: 2,
			wantHas: []string{
				`"4.1.0" # keep this comment`,
				`engine_version = "3.0.0"`,
				`version = "0.0.1"`,
				`version = var.s3_version`,
				`# module "commented" { source = "x/y/aws" version = "9.9.9" }`,
				"terraform-aws-modules/rds/aws\"\n  version = \"3.0.0\"",
			},
		},
		{name: "no module matches", source: "nonexistent/x/aws", version: "4.1.0"},
		{name: "non-literal version is skipped", source: "terraform-aws-modules/s3-bucket/aws", version: "9.0.0"},
		{name: "invalid hcl", src: `module "a" {`, source: "x", version: "1", wantErr: ErrParse},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			src := fixture
			if tt.src != "" {
				src = tt.src
			}
			out, changed, err := Update([]byte(src), "main.tf", tt.source, tt.version)
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("Update() error = %v, want %v", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("Update() unexpected error: %v", err)
			}
			if changed != tt.wantChanged {
				t.Fatalf("Update() changed = %d, want %d", changed, tt.wantChanged)
			}
			if tt.wantChanged == 0 && string(out) != src {
				t.Fatalf("Update() modified content although nothing matched")
			}
			for _, want := range tt.wantHas {
				if !strings.Contains(string(out), want) {
					t.Errorf("Update() output missing %q\n%s", want, out)
				}
			}
			if tt.wantChanged > 0 && strings.Count(string(out), `"`+tt.version+`"`) != tt.wantChanged {
				t.Errorf("Update() expected %d occurrences of %q\n%s", tt.wantChanged, tt.version, out)
			}
		})
	}
}

func TestExtractFile(t *testing.T) {
	t.Parallel()

	file := filepath.Join(t.TempDir(), "main.tf")
	if err := os.WriteFile(file, []byte(fixture), 0o600); err != nil {
		t.Fatalf("setup: %v", err)
	}
	refs, err := ExtractFile(context.Background(), file)
	if err != nil {
		t.Fatalf("ExtractFile() unexpected error: %v", err)
	}
	if len(refs) != 4 {
		t.Fatalf("ExtractFile() = %v, want 4 refs", refs)
	}
	if _, err = ExtractFile(context.Background(), filepath.Join(t.TempDir(), "missing.tf")); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("ExtractFile(missing) error = %v, want fs.ErrNotExist", err)
	}
}

func TestUpdateFile(t *testing.T) {
	t.Parallel()

	file := filepath.Join(t.TempDir(), "main.tf")
	if err := os.WriteFile(file, []byte(fixture), 0o640); err != nil {
		t.Fatalf("setup: %v", err)
	}
	changed, err := UpdateFile(context.Background(), file, "terraform-aws-modules/rds/aws", "5.0.0")
	if err != nil || changed != 1 {
		t.Fatalf("UpdateFile() = %d, %v, want 1, nil", changed, err)
	}
	b, err := os.ReadFile(file) //nolint:gosec // G304 - the path is a test temp file
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if !strings.Contains(string(b), `version = "5.0.0"`) {
		t.Errorf("file not updated:\n%s", b)
	}
	info, err := os.Stat(file)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Mode().Perm() != 0o640 {
		t.Errorf("mode = %v, want 0640", info.Mode().Perm())
	}
	if changed, err = UpdateFile(context.Background(), file, "nonexistent/x/aws", "1.0.0"); err != nil || changed != 0 {
		t.Errorf("UpdateFile(no match) = %d, %v, want 0, nil", changed, err)
	}
	if _, err = UpdateFile(context.Background(), filepath.Join(t.TempDir(), "missing.tf"), "s", "1"); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("UpdateFile(missing) error = %v, want fs.ErrNotExist", err)
	}
}

func TestFileFunctionsCanceledContext(t *testing.T) {
	t.Parallel()

	file := filepath.Join(t.TempDir(), "main.tf")
	if err := os.WriteFile(file, []byte(fixture), 0o600); err != nil {
		t.Fatalf("setup: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if _, err := ExtractFile(ctx, file); !errors.Is(err, context.Canceled) {
		t.Errorf("ExtractFile(canceled) error = %v, want context.Canceled", err)
	}
	if _, err := UpdateFile(ctx, file, "terraform-aws-modules/rds/aws", "5.0.0"); !errors.Is(err, context.Canceled) {
		t.Errorf("UpdateFile(canceled) error = %v, want context.Canceled", err)
	}
	b, err := os.ReadFile(file) //nolint:gosec // G304 - the path is a test temp file
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if string(b) != fixture {
		t.Errorf("file modified despite canceled context")
	}
}
