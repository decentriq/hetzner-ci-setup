#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/decentriq}"
RUNNER_NAME="${RUNNER_NAME:-gcp-standalone-runner-1}"
RUNNER_LABELS="${RUNNER_LABELS:-}"

RUNNER_VERSION="${RUNNER_VERSION:-2.334.0}"
RUNNER_SHA256="${RUNNER_SHA256:-048024cd2c848eb6f14d5646d56c13a4def2ae7ee3ad12122bee960c56f3d271}"
NIX_VERSION="${NIX_VERSION:-2.25.5}"

RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_HOME="${RUNNER_HOME:-/home/${RUNNER_USER}}"
STATE_DIR="${STATE_DIR:-/var/lib/gcp-standalone-runner-setup}"
NESTED_VM_HOST_SETUP="${NESTED_VM_HOST_SETUP:-false}"

usage() {
  cat <<EOF
Usage: sudo $0 [options]

Installs Docker, daemon-mode Nix, and a pinned GitHub Actions runner.
The GitHub runner registration token is prompted interactively and is not stored.

Options:
  --url URL          GitHub repository URL. Default: ${REPO_URL}
  --name NAME        GitHub runner name. Default: ${RUNNER_NAME}
  --labels LABELS    Comma-separated labels. Default: ${RUNNER_LABELS}
  --help             Show this help.

Environment overrides:
  RUNNER_VERSION     ${RUNNER_VERSION}
  RUNNER_SHA256      ${RUNNER_SHA256}
  NIX_VERSION        ${NIX_VERSION}
  NESTED_VM_HOST_SETUP ${NESTED_VM_HOST_SETUP}
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

mark_done() {
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/$1"
}

done_marker() {
  [[ -f "$STATE_DIR/$1" ]]
}

nested_vm_host_setup_enabled() {
  case "$NESTED_VM_HOST_SETUP" in
    1 | true | yes | on)
      return 0
      ;;
    0 | false | no | off)
      return 1
      ;;
    *)
      die "NESTED_VM_HOST_SETUP must be one of true/false, got: $NESTED_VM_HOST_SETUP"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      REPO_URL="$2"
      shift 2
      ;;
    --name)
      RUNNER_NAME="$2"
      shift 2
      ;;
    --labels)
      RUNNER_LABELS="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "run as root, for example: sudo $0"
[[ -n "$REPO_URL" ]] || die "REPO_URL cannot be empty"
[[ -n "$RUNNER_NAME" ]] || die "RUNNER_NAME cannot be empty"
RUNNER_LABELS="${RUNNER_LABELS:-gcp,gcp-standalone,${RUNNER_NAME},standalone-tests,build,live}"
[[ -n "$RUNNER_LABELS" ]] || die "RUNNER_LABELS cannot be empty"

mkdir -p "$STATE_DIR"

if ! done_marker apt-update; then
  apt-get update
  mark_done apt-update
fi

if ! done_marker base-packages; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    jq \
    git \
    openssh-client \
    sudo \
    tar \
    gzip
  mark_done base-packages
fi

if nested_vm_host_setup_enabled; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y cpu-checker

  cat <<'EOF' >/etc/modules-load.d/gcp-integration-runner.conf
kvm_intel
vhost_vsock
vhost_net
vsock
EOF

  modprobe kvm_intel
  modprobe vhost_vsock
  modprobe vhost_net
  modprobe vsock

  lscpu | grep 'Virtualization' || die "CPU virtualization is not visible to the guest"

  for device in /dev/kvm /dev/vhost-vsock /dev/vhost-net; do
    [[ -e "$device" ]] || die "required nested-VM device is missing: $device"
  done

  kvm-ok
fi

if ! dpkg -s google-cloud-ops-agent >/dev/null 2>&1; then
  if ! dpkg -s google-cloud-ops-agent-repo >/dev/null 2>&1; then
    curl -fsSLO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh
    rm -f add-google-cloud-ops-agent-repo.sh
  fi

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-ops-agent
else
  echo "Google Cloud Ops Agent already installed"
fi

systemctl enable --now google-cloud-ops-agent

if id "$RUNNER_USER" >/dev/null 2>&1; then
  echo "User already exists: $RUNNER_USER"
else
  useradd -m -s /bin/bash "$RUNNER_USER"
fi

hostnamectl set-hostname "$RUNNER_NAME"

if [[ -f /etc/ssh/sshd_config ]]; then
  if grep -qE '^#?PasswordAuthentication' /etc/ssh/sshd_config; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
  else
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  fi
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
fi

NIX_BIN="${NIX_BIN:-/nix/var/nix/profiles/default/bin/nix}"

if command -v nix >/dev/null 2>&1 || [[ -x "$NIX_BIN" ]]; then
  echo "Nix already installed"
else
  sh <(curl -L "https://releases.nixos.org/nix/nix-${NIX_VERSION}/install") < /dev/null --daemon
fi

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
else
  echo "Docker already installed"
fi

cat <<'EOF' >/usr/local/bin/docker-compose
#!/usr/bin/env bash
exec docker compose "$@"
EOF
chmod 0755 /usr/local/bin/docker-compose

if nested_vm_host_setup_enabled; then
  docker-compose version
fi

usermod -aG docker "$RUNNER_USER"

mkdir -p /etc/nix
cat <<'EOF' >/etc/nix/nix.conf
allowed-users = *
auto-optimise-store = false
builders =
cores = 0
keep-outputs = true
max-jobs = auto
netrc-file = /etc/nix/netrc
require-sigs = true
sandbox = true
sandbox-fallback = false
substituters = https://decentriq.cachix.org https://decentriq-enclaves.cachix.org https://cache.nixos.org/
system-features = recursive-nix nixos-test big-parallel
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= decentriq.cachix.org-1:ATphZivd1g6LaqJ3ORH/iquIWOWBjAqe3MiVr0V4NxQ= decentriq-enclaves.cachix.org-1:OySCzvF7gQdG2twL37HjfKDrhmAEjRJUiywOAo/es6M=
trusted-substituters =
trusted-users = root runner @wheel
extra-sandbox-paths =
experimental-features = nix-command flakes recursive-nix
EOF
systemctl restart nix-daemon 2>/dev/null || true

mkdir -p "$RUNNER_HOME/.ssh"
cat <<'EOF' >"$RUNNER_HOME/.ssh/config"
StrictHostKeyChecking=accept-new
EOF
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/.ssh"
chmod 700 "$RUNNER_HOME/.ssh"

mkdir -p "$RUNNER_HOME/bin-extra"
cat <<'EOF' >"$RUNNER_HOME/bin-extra/ssh-agent-setup"
#!/usr/bin/env bash
set -eu

mkdir -p /home/runner/.ssh
echo "$DEPLOY_KEY" > /home/runner/.ssh/deploy_key
chmod 0600 /home/runner/.ssh/deploy_key

eval `ssh-agent`
echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >> "$GITHUB_ENV"
echo "SSH_AGENT_PID=$SSH_AGENT_PID" >> "$GITHUB_ENV"

ssh-add /home/runner/.ssh/deploy_key
EOF
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/bin-extra"
chmod a+x "$RUNNER_HOME/bin-extra/ssh-agent-setup"

runner_tarball="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
runner_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${runner_tarball}"

if [[ ! -x "$RUNNER_HOME/config.sh" ]]; then
  (
    cd "$RUNNER_HOME"
    sudo -u "$RUNNER_USER" curl -fL -o "$runner_tarball" "$runner_url"
    echo "${RUNNER_SHA256}  ${runner_tarball}" | sha256sum -c -
    sudo -u "$RUNNER_USER" tar xzf "$runner_tarball"
  )
else
  echo "GitHub runner is already unpacked"
fi

if [[ -f "$RUNNER_HOME/.runner" ]]; then
  echo "GitHub runner is already configured. Skipping registration."
else
  echo
  echo "Create a fresh registration token in GitHub, then paste it here."
  read -r -s -p "GitHub runner registration token: " RUNNER_TOKEN
  echo
  [[ -n "$RUNNER_TOKEN" ]] || die "runner token cannot be empty"

  (
    cd "$RUNNER_HOME"
    sudo -u "$RUNNER_USER" ./config.sh \
      --url "$REPO_URL" \
      --token "$RUNNER_TOKEN" \
      --name "$RUNNER_NAME" \
      --labels "$RUNNER_LABELS" \
      --unattended \
      --replace
  )
fi

echo "$RUNNER_HOME/bin:$RUNNER_HOME/.nix-profile/bin:$RUNNER_HOME/bin-extra:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin" > "$RUNNER_HOME/.path"
chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME/.path"

(
  cd "$RUNNER_HOME"
  if systemctl list-unit-files --type=service 'actions.runner.*.service' | grep -q '^actions.runner.'; then
    echo "GitHub runner service already installed"
  else
    ./svc.sh install "$RUNNER_USER"
  fi
)

cat <<'EOF' >/etc/systemd/system/docker-gc.service
[Unit]
Description=Run docker GC
Wants=docker-gc.timer

[Service]
ExecStart=docker system prune --all -f

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/docker-gc.timer
[Unit]
Description=Run docker GC timer
Requires=docker-gc.service

[Timer]
Unit=docker-gc.service
OnUnitInactiveSec=24h

[Install]
WantedBy=timers.target
EOF

cat <<'EOF' >/etc/systemd/system/nix-gc.service
[Unit]
Description=Run nix GC
Wants=nix-gc.timer

[Service]
ExecStart=bash -c 'store_size=$(( $(df --output=size /nix/store | tail -n 1) * 1024 )); store_avail=$(( $(df --output=avail /nix/store | tail -n 1) * 1024 )); to_free=$(( store_size / 20 - store_avail )); if [ "$to_free" -gt 0 ]; then /nix/var/nix/profiles/default/bin/nix-collect-garbage --max-freed "$to_free"; fi'

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' >/etc/systemd/system/nix-gc.timer
[Unit]
Description=Run nix GC timer
Requires=nix-gc.service

[Timer]
Unit=nix-gc.service
OnUnitInactiveSec=2h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable docker-gc.timer nix-gc.timer
systemctl start docker-gc.timer nix-gc.timer

echo
echo "Runner setup complete. Start it with: sudo bash start-runner.sh"
