#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/redact.sh
#
# Use cases:
# - redact_sensitive_text redacts Bearer tokens
# - redact_sensitive_text redacts a multi-word Authorization scheme value
# - redact_sensitive_text redacts PEM blocks and JWTs
# - redact_sensitive_text redacts GitHub and AWS access key patterns
# - redact_sensitive_text redacts key=value secrets regardless of separator

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/redact.sh"
}

@test "redact_sensitive_text redacts Bearer tokens" {
    run redact_sensitive_text 'Authorization: Bearer abc.def-123_token'
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"abc.def-123_token"* ]]
}

@test "redact_sensitive_text redacts a multi-word Authorization scheme value" {
    # Dummy base64 credential shape only — not a real secret.
    run redact_sensitive_text 'Authorization: Basic dXNlcjpwYXNzd29yZA==' # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"Authorization: [REDACTED]"* ]]
    [[ $output != *"dXNlcjpwYXNzd29yZA=="* ]] # pragma: allowlist secret
}

@test "redact_sensitive_text redacts PEM blocks and JWTs" {
    # Single-line PEM: the redaction pipeline processes text line-by-line.
    # Marker is split so the detect-private-key pre-commit hook does not
    # flag this fixture as a real key.
    local kind="PRIVATE"" KEY"
    run redact_sensitive_text "-----BEGIN ${kind}-----abc123-----END ${kind}-----"
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED-PEM]"* ]]
    [[ $output != *"abc123"* ]]

    run redact_sensitive_text 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk' # gitleaks:allow # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED-JWT]"* ]]
    [[ $output != *"eyJhbGciOiJIUzI1NiJ9"* ]]
}

@test "redact_sensitive_text redacts GitHub and AWS access key patterns" {
    # Dummy token shapes only — not real credentials.
    run redact_sensitive_text 'token ghp_FAKE_TOKEN_FOR_UNIT_TEST_ONLY_0000' # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"ghp_FAKE_TOKEN_FOR_UNIT_TEST_ONLY_0000"* ]] # pragma: allowlist secret

    run redact_sensitive_text 'AKIAABCDEFGHIJKLMNOP' # pragma: allowlist secret gitleaks:allow
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"AKIAABCDEFGHIJKLMNOP"* ]] # pragma: allowlist secret gitleaks:allow
}

@test "redact_sensitive_text redacts key=value secrets regardless of separator" {
    run redact_sensitive_text 'password=hunter2secretvalue' # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"password=[REDACTED]"* ]]
    [[ $output != *"hunter2secretvalue"* ]] # pragma: allowlist secret

    run redact_sensitive_text 'api_key: abcDEF1234567890' # pragma: allowlist secret gitleaks:allow
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"abcDEF1234567890"* ]] # pragma: allowlist secret gitleaks:allow
}
