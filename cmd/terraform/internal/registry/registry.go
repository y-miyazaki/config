// Package registry looks up module versions on the public Terraform Registry
// and only offers versions that have been published for a minimum amount of
// time, so a freshly published (possibly compromised) release is never picked
// up right away.
package registry

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	defaultBaseURL = "https://registry.terraform.io"
	defaultTimeout = 10 * time.Second

	// maxBodyBytes bounds how much of a registry response is read.
	maxBodyBytes = 8 << 20
	// maxVersionLookups bounds the per-version requests made to find an old enough version.
	maxVersionLookups = 20

	publicRegistryHost = "registry.terraform.io"
	// sourceParts is the number of path parts of <namespace>/<name>/<provider>.
	sourceParts = 3
	// pathSep separates the parts of module sources and registry URL paths.
	pathSep = "/"
)

var (
	// ErrNotRegistrySource is returned for sources that are not public registry modules
	// (git, local paths, private registries).
	ErrNotRegistrySource = errors.New("not a public registry module source")
	// ErrNoEligibleVersion is returned when no version is old enough.
	ErrNoEligibleVersion = errors.New("no version old enough")
	// ErrUnexpectedStatus is returned for a non-200 registry response.
	ErrUnexpectedStatus = errors.New("unexpected registry response status")
	// ErrNotFound is returned (together with ErrUnexpectedStatus) for a 404 registry response.
	ErrNotFound = errors.New("registry resource not found")

	// releaseVersion matches plain numeric versions; pre-releases are never offered.
	releaseVersion = regexp.MustCompile(`^\d+(\.\d+)*$`)
	// sourcePart restricts the characters allowed in a source path part (SEC-01).
	sourcePart = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]*$`)
)

// Module identifies a module on the public registry.
type Module struct {
	Namespace string
	Name      string
	Provider  string
}

// Client queries the Terraform Registry. The zero value is not usable; use New.
type Client struct {
	http    *http.Client
	now     func() time.Time
	baseURL string
}

// Option customises a Client.
type Option func(*Client)

// versionsResponse is the payload of the registry's list-versions endpoint.
type versionsResponse struct {
	Modules []moduleVersions `json:"modules"`
}

// moduleVersions holds the versions of one module in a versionsResponse.
type moduleVersions struct {
	Versions []versionEntry `json:"versions"`
}

// versionEntry is one version in a versionsResponse.
type versionEntry struct {
	Version string `json:"version"`
}

// versionDetail is the payload of the registry's single-version endpoint.
type versionDetail struct {
	PublishedAt string `json:"published_at"` //nolint:tagliatelle // the registry API uses snake_case
}

// WithBaseURL overrides the registry base URL (used by tests).
func WithBaseURL(baseURL string) Option {
	return func(c *Client) { c.baseURL = strings.TrimRight(baseURL, pathSep) }
}

// WithHTTPClient overrides the HTTP client.
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.http = h }
}

// WithClock overrides the clock used to evaluate the minimum age (used by tests).
func WithClock(now func() time.Time) Option {
	return func(c *Client) { c.now = now }
}

// New returns a Client for the public Terraform Registry.
func New(opts ...Option) *Client {
	c := &Client{
		baseURL: defaultBaseURL,
		http:    &http.Client{Timeout: defaultTimeout},
		now:     time.Now,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// ParseSource extracts the registry module from a module source address.
// A "//subdir" suffix is ignored and an explicit registry.terraform.io host is accepted.
func ParseSource(source string) (Module, error) {
	// Anything that names a transport, a VCS host or a path is not a registry address.
	if strings.Contains(source, "::") || strings.Contains(source, "://") ||
		strings.HasPrefix(source, "git@") || strings.HasPrefix(source, "github.com/") ||
		strings.HasPrefix(source, "~") || strings.HasPrefix(source, pathSep) || strings.HasPrefix(source, ".") {
		return Module{}, fmt.Errorf("%w: %q", ErrNotRegistrySource, source)
	}
	base, _, _ := strings.Cut(source, "//")
	parts := strings.Split(base, pathSep)
	if len(parts) == sourceParts+1 && parts[0] == publicRegistryHost {
		parts = parts[1:]
	}
	if len(parts) != sourceParts {
		return Module{}, fmt.Errorf("%w: %q", ErrNotRegistrySource, source)
	}
	for _, part := range parts {
		if !sourcePart.MatchString(part) {
			return Module{}, fmt.Errorf("%w: %q", ErrNotRegistrySource, source)
		}
	}
	return Module{Namespace: parts[0], Name: parts[1], Provider: parts[2]}, nil
}

// CompareVersions compares two dotted numeric versions: -1, 0 or 1.
// Missing segments count as 0 and non-numeric segments as 0.
func CompareVersions(a, b string) int {
	as, bs := strings.Split(a, "."), strings.Split(b, ".")
	for i := range max(len(as), len(bs)) {
		if c := cmp.Compare(segment(as, i), segment(bs, i)); c != 0 {
			return c
		}
	}
	return 0
}

// segment returns the i-th numeric segment of a split version, or 0.
func segment(parts []string, i int) int {
	if i >= len(parts) {
		return 0
	}
	n, err := strconv.Atoi(parts[i])
	if err != nil {
		return 0
	}
	return n
}

// modulePath returns the registry URL path of a module.
func modulePath(mod Module) string {
	return "/v1/modules/" + url.PathEscape(mod.Namespace) + pathSep + url.PathEscape(mod.Name) + pathSep + url.PathEscape(mod.Provider)
}

// LatestEligible returns the highest release version of source that was
// published at least minAge ago. With minAge <= 0 the newest release is
// returned without per-version lookups. Versions whose publish time is unknown
// are never eligible.
func (c *Client) LatestEligible(ctx context.Context, source string, minAge time.Duration) (string, error) {
	mod, err := ParseSource(source)
	if err != nil {
		return "", fmt.Errorf("latest version of %q: %w", source, err)
	}
	versions, err := c.listVersions(ctx, mod)
	if err != nil {
		return "", fmt.Errorf("list versions of %q: %w", source, err)
	}
	if minAge <= 0 && len(versions) > 0 {
		return versions[0], nil
	}
	cutoff := c.now().Add(-minAge)
	// Versions are sorted newest first, so the first old enough one is the answer.
	for i, version := range versions {
		if i >= maxVersionLookups {
			break
		}
		published, ok, lookupErr := c.publishedAt(ctx, mod, version)
		if lookupErr != nil {
			return "", fmt.Errorf("publish time of %q %s: %w", source, version, lookupErr)
		}
		if ok && !published.After(cutoff) {
			return version, nil
		}
	}
	return "", fmt.Errorf("%w: %s (minimum age %s)", ErrNoEligibleVersion, source, minAge)
}

// getJSON fetches path from the registry and decodes the JSON body into out.
func (c *Client) getJSON(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, http.NoBody)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req) //nolint:gosec // G704 - the URL is the fixed registry host plus escaped path parts
	if err != nil {
		return fmt.Errorf("request %s: %w", path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("%w: %w: %s %s", ErrUnexpectedStatus, ErrNotFound, path, resp.Status)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%w: %s %s", ErrUnexpectedStatus, path, resp.Status)
	}
	err = json.NewDecoder(io.LimitReader(resp.Body, maxBodyBytes)).Decode(out)
	if err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

// listVersions returns the release versions of mod, newest first.
func (c *Client) listVersions(ctx context.Context, mod Module) ([]string, error) {
	var body versionsResponse
	if err := c.getJSON(ctx, modulePath(mod)+pathSep+"versions", &body); err != nil {
		return nil, fmt.Errorf("list versions: %w", err)
	}
	var versions []string
	for _, m := range body.Modules {
		for _, v := range m.Versions {
			if releaseVersion.MatchString(v.Version) {
				versions = append(versions, v.Version)
			}
		}
	}
	slices.SortFunc(versions, func(a, b string) int { return CompareVersions(b, a) })
	return versions, nil
}

// publishedAt returns the publish time of one version. ok is false when the
// registry gives no usable timestamp or no detail page for the version.
func (c *Client) publishedAt(ctx context.Context, mod Module, version string) (published time.Time, ok bool, err error) {
	var body versionDetail
	err = c.getJSON(ctx, modulePath(mod)+pathSep+url.PathEscape(version), &body)
	if errors.Is(err, ErrNotFound) {
		// A listed version without a detail page (for example a yanked release) is not eligible.
		return time.Time{}, false, nil
	}
	if err != nil {
		return time.Time{}, false, fmt.Errorf("version detail: %w", err)
	}
	published, parseErr := time.Parse(time.RFC3339Nano, body.PublishedAt)
	if parseErr != nil {
		return time.Time{}, false, nil //nolint:nilerr // an unusable timestamp means "not eligible", not a failure
	}
	return published, true, nil
}
