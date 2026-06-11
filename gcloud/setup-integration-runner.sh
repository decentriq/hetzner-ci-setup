#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export RUNNER_NAME="${RUNNER_NAME:-gcp-integration-runner-1}"
export RUNNER_LABELS="${RUNNER_LABELS:-gcp-integration,gcp-integration-runner-1,integration-tests,runner,build,live}"
export STATE_DIR="${STATE_DIR:-/var/lib/gcp-integration-runner-setup}"
export NESTED_VM_HOST_SETUP="${NESTED_VM_HOST_SETUP:-true}"

exec "$SCRIPT_DIR/setup-runner.sh" "$@"
