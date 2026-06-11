#!/usr/bin/env bash
set -euo pipefail

RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_HOME="${RUNNER_HOME:-/home/${RUNNER_USER}}"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run as root, for example: sudo $0"
[[ -x "$RUNNER_HOME/svc.sh" ]] || die "GitHub runner service script not found at $RUNNER_HOME/svc.sh"

echo "$RUNNER_HOME/bin:$RUNNER_HOME/.nix-profile/bin:$RUNNER_HOME/bin-extra:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" > "$RUNNER_HOME/.path"
chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/.path"

if [[ -f "$RUNNER_HOME/bin/actions.runner.service.template" ]] && ! grep -q '^Restart=always$' "$RUNNER_HOME/bin/actions.runner.service.template"; then
  sed -i '/\[Service\]/a Restart=always' "$RUNNER_HOME/bin/actions.runner.service.template"
fi

shopt -s nullglob
for unit in /etc/systemd/system/actions.runner.*.service; do
  if ! grep -q '^Restart=always$' "$unit"; then
    sed -i '/\[Service\]/a Restart=always' "$unit"
  fi
done

(
  cd "$RUNNER_HOME"
  if systemctl list-unit-files --type=service 'actions.runner.*.service' | grep -q '^actions.runner.'; then
    systemctl daemon-reload
  else
    ./svc.sh install "$RUNNER_USER"
  fi
  ./svc.sh start
)

systemctl --no-pager --full status 'actions.runner.*' || true
