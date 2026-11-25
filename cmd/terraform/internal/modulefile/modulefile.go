// Package modulefile reads and rewrites the version of Terraform module blocks
// with the HCL parser, so strings, comments, heredocs and nested blocks never
// confuse the result.
package modulefile

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/hashicorp/hcl/v2/hclwrite"
	"github.com/zclconf/go-cty/cty"
)

const (
	blockModule   = "module"
	attrSource    = "source"
	attrVersion   = "version"
	tempFileMatch = ".*"
)

// ErrParse is returned when a file is not valid HCL.
var ErrParse = errors.New("parse HCL")

// Ref is a module block whose source and version are string literals.
type Ref struct {
	Source  string
	Version string
}

// Extract returns the module blocks of src that have a literal source and version.
func Extract(src []byte, filename string) ([]Ref, error) {
	f, err := parse(src, filename)
	if err != nil {
		return nil, fmt.Errorf("extract modules: %w", err)
	}
	var refs []Ref
	for _, block := range f.Body().Blocks() {
		if block.Type() != blockModule {
			continue
		}
		source, ok := literalAttr(block.Body(), attrSource)
		if !ok || source == "" {
			continue
		}
		version, ok := literalAttr(block.Body(), attrVersion)
		if !ok || version == "" {
			continue
		}
		refs = append(refs, Ref{Source: source, Version: version})
	}
	return refs, nil
}

// Update sets version on every module block of src whose literal source equals
// source and that already has a literal version for which shouldUpdate returns
// true (nil updates every such block). shouldUpdate receives the block's current
// version, so blocks already at or beyond version are left alone instead of being
// downgraded. It returns the new content and the number of blocks changed; src is
// returned untouched when nothing matched.
func Update(src []byte, filename, source, version string, shouldUpdate func(current string) bool) (out []byte, changed int, err error) {
	f, err := parse(src, filename)
	if err != nil {
		return nil, 0, fmt.Errorf("update modules: %w", err)
	}
	for _, block := range f.Body().Blocks() {
		if block.Type() != blockModule {
			continue
		}
		got, ok := literalAttr(block.Body(), attrSource)
		if !ok || got != source {
			continue
		}
		current, hasVersion := literalAttr(block.Body(), attrVersion)
		if !hasVersion {
			continue
		}
		if shouldUpdate != nil && !shouldUpdate(current) {
			continue
		}
		block.Body().SetAttributeValue(attrVersion, cty.StringVal(version))
		changed++
	}
	if changed == 0 {
		return src, 0, nil
	}
	return f.Bytes(), changed, nil
}

// ExtractFile runs Extract on the file at path. It returns early when ctx is done.
func ExtractFile(ctx context.Context, path string) ([]Ref, error) {
	if err := ctx.Err(); err != nil {
		return nil, fmt.Errorf("extract %s: %w", path, err)
	}
	src, err := readFile(path)
	if err != nil {
		return nil, fmt.Errorf("extract file: %w", err)
	}
	refs, err := Extract(src, path)
	if err != nil {
		return nil, fmt.Errorf("extract file: %w", err)
	}
	return refs, nil
}

// UpdateFile runs Update on the file at path and replaces the file atomically
// when at least one block changed. shouldUpdate filters blocks as in Update. It
// returns the number of blocks changed and returns early when ctx is done.
func UpdateFile(ctx context.Context, path, source, version string, shouldUpdate func(current string) bool) (int, error) {
	if err := ctx.Err(); err != nil {
		return 0, fmt.Errorf("update %s: %w", path, err)
	}
	src, err := readFile(path)
	if err != nil {
		return 0, fmt.Errorf("update file: %w", err)
	}
	out, changed, err := Update(src, path, source, version, shouldUpdate)
	if err != nil {
		return 0, fmt.Errorf("update file: %w", err)
	}
	if changed == 0 {
		return 0, nil
	}
	err = writeFileAtomic(path, out)
	if err != nil {
		return 0, fmt.Errorf("update file: %w", err)
	}
	return changed, nil
}

func parse(src []byte, filename string) (*hclwrite.File, error) {
	f, diags := hclwrite.ParseConfig(src, filename, hcl.InitialPos)
	if diags.HasErrors() {
		return nil, fmt.Errorf("%w %s: %s", ErrParse, filename, diags.Error())
	}
	return f, nil
}

// literalAttr returns the value of a top-level attribute when it is a plain
// quoted string without interpolation.
func literalAttr(body *hclwrite.Body, name string) (string, bool) {
	attr := body.GetAttribute(name)
	if attr == nil {
		return "", false
	}
	tokens := attr.Expr().BuildTokens(nil)
	if len(tokens) < 2 || tokens[0].Type != hclsyntax.TokenOQuote || tokens[len(tokens)-1].Type != hclsyntax.TokenCQuote {
		return "", false
	}
	var value []byte
	for _, t := range tokens[1 : len(tokens)-1] {
		if t.Type != hclsyntax.TokenQuotedLit {
			return "", false
		}
		value = append(value, t.Bytes...)
	}
	return string(value), true
}

func readFile(path string) ([]byte, error) {
	src, err := os.ReadFile(filepath.Clean(path)) //nolint:gosec // G304 - the path is a CLI argument by design
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return src, nil
}

// writeFileAtomic replaces path (or the target of a symlink at path) with data
// via a temp file next to it, preserving the original file mode.
func writeFileAtomic(path string, data []byte) error {
	// Replace the symlink's target, not the link itself, so the link survives the update.
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return fmt.Errorf("resolve %s: %w", path, err)
	}
	info, err := os.Stat(target)
	if err != nil {
		return fmt.Errorf("stat %s: %w", path, err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), filepath.Base(target)+tempFileMatch)
	if err != nil {
		return fmt.Errorf("create temp file for %s: %w", path, err)
	}
	tmpName := tmp.Name()
	// Best-effort cleanup: after a successful rename the temp file no longer exists.
	defer func() { _ = os.Remove(tmpName) }()
	_, err = tmp.Write(data)
	if err != nil {
		_ = tmp.Close() // best effort: the write error is the one worth returning
		return fmt.Errorf("write %s: %w", tmpName, err)
	}
	err = tmp.Close()
	if err != nil {
		return fmt.Errorf("close %s: %w", tmpName, err)
	}
	err = os.Chmod(tmpName, info.Mode().Perm())
	if err != nil {
		return fmt.Errorf("chmod %s: %w", tmpName, err)
	}
	err = os.Rename(tmpName, target)
	if err != nil {
		return fmt.Errorf("replace %s: %w", path, err)
	}
	return nil
}
