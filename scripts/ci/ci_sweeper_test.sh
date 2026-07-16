#!/usr/bin/env bash
# Intentional shell script errors for ci-sweeper dogfood testing. Remove after validation.
set -euo pipefail

UNQUOTED_VAR="ci-sweeper-test"
echo $UNQUOTED_VAR

if true; then
  echo "missing fi causes bash -n failure"
