#!/usr/bin/env bash
set -euo pipefail

# https://raw.githubusercontent.com/decentriq/hetzner-ci-setup/main/setup.sh

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cd "$SCRIPT_DIR"

mkdir -p build

if [[ ! -f build/update ]]
then
  apt update
  touch build/update
fi

if [[ ! -f build/runner ]]
then
  mkdir -p actions-runner && cd actions-runner
  curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
  echo "ba46ba7ce3a4d7236b16fbe44419fb453bc08f866b24f04d549ec89f1722a29e  actions-runner-linux-x64-2.321.0.tar.gz" | shasum -a 256 -c
  tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz
fi