#!/usr/bin/env bash
set -euo pipefail

# https://raw.githubusercontent.com/decentriq/hetzner-ci-setup/main/start.sh

DIR=$(pwd)

if [[ ! -f build/runner_svc ]]
then
  (
  cd /home/runner
  ./svc.sh install root
  ./svc.sh start
  )
  touch build/runner_svc
fi
