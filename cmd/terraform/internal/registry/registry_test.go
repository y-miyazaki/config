package registry

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

var testNow = time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC)

func TestParseSource(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		source  string
		want    Module
		wantErr error
	}{
		{name: "registry module", source: "terraform-aws-modules/vpc/aws", want: Module{"terraform-aws-modules", "vpc", "aws"}},
		{name: "submodule suffix", source: "terraform-aws-modules/iam/aws//modules/iam-user", want: Module{"terraform-aws-modules", "iam", "aws"}},
		{name: "explicit public host", source: "registry.terraform.io/acme/net/aws", want: Module{"acme", "net", "aws"}},
		{name: "git prefix", source: "git::https://example.com/x.git", wantErr: ErrNotRegistrySource},
		{name: "github shorthand", source: "github.com/acme/x", wantErr: ErrNotRegistrySource},
		{name: "ssh git", source: "git@github.com:acme/x.git", wantErr: ErrNotRegistrySource},
		{name: "https url", source: "https://example.com/x.zip", wantErr: ErrNotRegistrySource},
		{name: "relative path", source: "./modules/local", wantErr: ErrNotRegistrySource},
		{name: "parent path", source: "../shared", wantErr: ErrNotRegistrySource},
		{name: "absolute path", source: "/opt/modules/x", wantErr: ErrNotRegistrySource},
		{name: "private registry host", source: "app.terraform.io/org/net/aws", wantErr: ErrNotRegistrySource},
		{name: "too few parts", source: "acme/vpc", wantErr: ErrNotRegistrySource},
		{name: "empty part", source: "acme//aws", wantErr: ErrNotRegistrySource},
		{name: "unsafe characters", source: "acme/vp c/aws", wantErr: ErrNotRegistrySource},
		{name: "empty", source: "", wantErr: ErrNotRegistrySource},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := ParseSource(tt.source)
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("ParseSource(%q) error = %v, want %v", tt.source, err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseSource(%q) unexpected error: %v", tt.source, err)
			}
			if got != tt.want {
				t.Fatalf("ParseSource(%q) = %v, want %v", tt.source, got, tt.want)
			}
		})
	}
}

func TestCompareVersions(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		a, b string
		want int
	}{
		{name: "equal", a: "1.2.3", b: "1.2.3", want: 0},
		{name: "missing segment counts as zero", a: "1.2", b: "1.2.0", want: 0},
		{name: "numeric not lexical", a: "1.10.0", b: "1.9.0", want: 1},
		{name: "major wins", a: "2.0.0", b: "1.99.99", want: 1},
		{name: "older is less", a: "1.0.0", b: "1.0.1", want: -1},
		{name: "non numeric segment is zero", a: "1.x.0", b: "1.0.0", want: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := CompareVersions(tt.a, tt.b); got != tt.want {
				t.Fatalf("CompareVersions(%q, %q) = %d, want %d", tt.a, tt.b, got, tt.want)
			}
		})
	}
}

// fakeRegistry serves /versions and per-version metadata for acme/vpc/aws.
// published maps version -> RFC3339 timestamp ("" yields an unusable timestamp);
// versions are listed in the given order.
// serverErrorMarker as a published value makes the fake answer 500 for that version.
const serverErrorMarker = "!500"

func fakeRegistry(t *testing.T, order []string, published map[string]string, lookups *atomic.Int32) *Client {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/modules/acme/vpc/aws/versions", func(w http.ResponseWriter, _ *http.Request) {
		entries := make([]versionEntry, 0, len(order))
		for _, v := range order {
			entries = append(entries, versionEntry{Version: v})
		}
		writeJSON(w, versionsResponse{Modules: []moduleVersions{{Versions: entries}}})
	})
	mux.HandleFunc("/v1/modules/acme/vpc/aws/", func(w http.ResponseWriter, r *http.Request) {
		lookups.Add(1)
		version := strings.TrimPrefix(r.URL.Path, "/v1/modules/acme/vpc/aws/")
		ts, ok := published[version]
		if !ok {
			http.NotFound(w, r)
			return
		}
		if ts == serverErrorMarker {
			http.Error(w, "boom", http.StatusInternalServerError)
			return
		}
		writeJSON(w, versionDetail{PublishedAt: ts})
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return New(WithBaseURL(srv.URL), WithClock(func() time.Time { return testNow }))
}

// writeJSON encodes v as the JSON response body.
func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	// The encoder only fails when the client went away, which the test would notice anyway.
	_ = json.NewEncoder(w).Encode(v)
}

func ago(d time.Duration) string { return testNow.Add(-d).Format(time.RFC3339Nano) }

func TestLatestEligible(t *testing.T) {
	t.Parallel()

	const day = 24 * time.Hour
	order := []string{"1.0.0", "2.1.0", "1.1.0", "2.0.0", "3.0.0-beta1"}
	published := map[string]string{
		"1.0.0": ago(90 * day),
		"1.1.0": ago(30 * day),
		"2.0.0": ago(1 * day),
		"2.1.0": ago(1 * time.Hour),
	}

	tests := []struct {
		name        string
		minAge      time.Duration
		published   map[string]string
		want        string
		wantErr     error
		wantLookups int32
	}{
		{name: "seven days skips fresh releases", minAge: 7 * day, published: published, want: "1.1.0", wantLookups: 3},
		{name: "zero age takes newest without lookups", minAge: 0, published: published, want: "2.1.0", wantLookups: 0},
		{name: "one hour boundary is inclusive", minAge: time.Hour, published: published, want: "2.1.0", wantLookups: 1},
		{name: "nothing old enough", minAge: 365 * day, published: published, wantErr: ErrNoEligibleVersion, wantLookups: 4},
		{
			name:   "unknown publish time is never eligible",
			minAge: 7 * day,
			published: map[string]string{
				"1.0.0": ago(90 * day),
				"1.1.0": "",
				"2.0.0": ago(1 * day),
				"2.1.0": "not-a-date",
			},
			want:        "1.0.0",
			wantLookups: 4,
		},
		{name: "versions without a detail page are never eligible", minAge: 7 * day, published: map[string]string{}, wantErr: ErrNoEligibleVersion, wantLookups: 4},
		{
			name:        "a missing detail page is skipped and an older version wins",
			minAge:      7 * day,
			published:   map[string]string{"2.0.0": ago(90 * day)},
			want:        "2.0.0",
			wantLookups: 2,
		},
		{
			name:        "server error on a version lookup is an error",
			minAge:      7 * day,
			published:   map[string]string{"2.1.0": serverErrorMarker},
			wantErr:     ErrUnexpectedStatus,
			wantLookups: 1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var lookups atomic.Int32
			client := fakeRegistry(t, order, tt.published, &lookups)
			got, err := client.LatestEligible(context.Background(), "acme/vpc/aws", tt.minAge)
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("LatestEligible() error = %v, want %v", err, tt.wantErr)
				}
			} else if err != nil {
				t.Fatalf("LatestEligible() unexpected error: %v", err)
			}
			if got != tt.want {
				t.Errorf("LatestEligible() = %q, want %q", got, tt.want)
			}
			if lookups.Load() != tt.wantLookups {
				t.Errorf("per-version lookups = %d, want %d", lookups.Load(), tt.wantLookups)
			}
		})
	}
}

func TestLatestEligibleErrors(t *testing.T) {
	t.Parallel()

	var lookups atomic.Int32
	client := fakeRegistry(t, nil, nil, &lookups)

	if _, err := client.LatestEligible(context.Background(), "./local", time.Hour); !errors.Is(err, ErrNotRegistrySource) {
		t.Errorf("non-registry source error = %v, want ErrNotRegistrySource", err)
	}
	if _, err := client.LatestEligible(context.Background(), "acme/unknown/aws", time.Hour); !errors.Is(err, ErrUnexpectedStatus) {
		t.Errorf("unknown module error = %v, want ErrUnexpectedStatus", err)
	}
	if _, err := client.LatestEligible(context.Background(), "acme/vpc/aws", time.Hour); !errors.Is(err, ErrNoEligibleVersion) {
		t.Errorf("empty version list error = %v, want ErrNoEligibleVersion", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.LatestEligible(ctx, "acme/vpc/aws", time.Hour); !errors.Is(err, context.Canceled) {
		t.Errorf("canceled context error = %v, want context.Canceled", err)
	}
}
