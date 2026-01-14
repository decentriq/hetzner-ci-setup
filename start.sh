#!/usr/bin/env bash
set -euo pipefail

# https://raw.githubusercontent.com/decentriq/hetzner-ci-setup/main/start.sh

DIR=$(pwd)

if [[ ! -f build/runner_svc ]]
then
  (
  cd /home/runner
  grep Restart=always ./bin/actions.runner.service.template &> /dev/null || sed -i '/\[Service\]/a Restart=always' ./bin/actions.runner.service.template
  ./svc.sh uninstall ; ./svc.sh install root
  ./svc.sh start
  )
  touch build/runner_svc
fi
