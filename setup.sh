#!/usr/bin/env bash
set -euo pipefail

# https://raw.githubusercontent.com/decentriq/hetzner-ci-setup/main/setup.sh

DIR=$(pwd)

mkdir -p build

if [[ ! -f build/update ]]
then
  apt update
  touch build/update
fi

if [[ ! -f build/ssh ]]
then
  cat << EOF >~/.ssh/authorized_keys
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC1FOV+RlXQOEbiD/lPwo3szPNjWMJcUuoDV/g3fRS/9lLc4ueBJENZl7p4iFs7ah3dEpgSTvG+A+PwbFdcYh18=
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC78ZdkvJjmkKE3pu4/yEuLbtbBcV/M0br3KVPcr3Son+RwgbCSBV+oazRcnkGuRNiYjcxNT0y+So29BfBLnSgynVS6S3VyAPlXnDmKwjx/g18CgEZ7FC5sdNl06s1XzTkeJNrjzxOueIkMG4bv6nqno1+iUkpRorSsEpdQN9pSdKaNF2u7CfqF2rqA1DSTQIhy61rqlxzq3iEOB8vS7D5OPbGHyscERhlzzxG4hvngiFJOeR8iSYoydmrmC7mBxB6887rwOAjOfh4vCO1LajNkH7eck9VdHfbiO6i9UdaiyA+faPvBapeWFv5ah9I19dx41X/Ag6dJgAxkdsAtaREp dstur@Davids-MacBook-Pro.local
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLcWCDZWDOBUskkFIjACZQD+IKSdwx1U4oUIE6Wdb7Se6djUg6MI1e2lJ8XCkWzRUOAZWYYpa6UmrM+GeMEV/DI=
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP4XftNJLEJnCN9YxVN4kSUda9yXacVU2nZWdPkajxDP isak@work-yubikey
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICnBcE8YBgKoC8j4b9grupB6Eo1QQM4t5tHy07VHoeY3 isak@yubikey
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBIQ8TXTQvAvDWSWPlQnPE/rOyG3wre3zGPw+Htv4H8K+Mu6N/j0Adol083KJjfal06AgMPfu1RD3GH5eKjKYm/4= matyas.fodor@yubikey
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDhHEqsLt5U5kFDHav2PHBAKmqEs+tAF0Ml8OwlpzRJcESvngTmHb8mKRBz60JlA/PX9wBVF5UPj0PCDTavHR+4l7EK1Az1Yi2DZz7+/TbyoRmPjXsbYKkCRN+0+PgUT95qoOmM/4VrmDuwDcHc48vJcdAUgQUmcF/o/O5wIQpnCR6AuIJ7QGRTYavB0fBwsVxNT3HU/vjwgOMhDEp1mzu/VZwtA4RBO2ERggs11dNf4O/2OR4vVrC7182TrRiN//BzvtLKjGHZF6NlGSJYiLCjZDj0sTjK1wyeQmTpHYM9KuJtr1y9WAPik6UKbVRhHpo80c/52LFWIlLxEuy5hrY5kPFEnyvhJ7zgHvWHEjaVDAq/oewad7hfimlp8dTPY3q4BP+vrJNJfpYonmypJTRiuw5LMDC2Dxrkq/DMLaR3+IQmKHu2GdukSF3sfDlQLxJIJkuk/SCklZ543yiPQeczO3fQN/AfK6w+n8ud03JqRtgC3S7tAEGF0H7+7Ky6lZU=
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOzccK9/DNjWEuyDK7y9XSCJwExOfTXF7tMfxs/3mbr/wifiCPPvVTJ6g38EkUwE7w+0+KUcqQ+C58SxHBQTWnE=
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAJPDa/afeM24q+mw08c56zt7KdkWOVoF5608bqVZDdv vasyl.trs@gmail.com
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGL3RfavVZYWU1UMfzwXiHGYpafD+aqLZZS3vz/A4KlRQPV/a0R0zSi1VgVSdhIaw+wCdbnb7RKnM88ylMHRtC8= volo@yubikey
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDV1WmZcD7uOXGBV7pGysc+JOpGsHK6c6jZ7FwiJJygj7X/iyaQJQxHPGC/GznkQuZBioO0AcOJZwS7zNMtQJDXAIy7nmFcPeeOmmZFFt9kn02JIXcsU54E30yMkQWUyrOOABh5/mm8eVznFr+KX9NSCs78CedDLAFdJhu9/lQInx78eaN2ntTfyvU2rHNKlt7FsO02NGtRldsk+AfrCJfujhXGhJtzAdPg/e/w2qRsIL9GH5BCbUPfLScrL/HydJhpSWoCHyhmeBighJuL1jENNo/hPrAb5yWUjB0CdoWIKFdsmZjQlwgmdONRkQ+31/7g+w5H+pmC1Bf1/NTRB3rV335Ir4D58aKrv+X9rqfGs5MBjkrAxanBMPgq6bYIdAMpBtjNCv56xFoaZNaDbjViHJdgARkAUcPgdywkI1Nn0iEofxYWlLDI6nOxpLVnTRXM9ofHYZ5b/8iYwyItHo18yyFAPwvlHClh44aMYVpSNuJy/PUqEjgFhpT3Cx8N7R0= ymelnychuk@MacBook-Air.Home
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDSX8jm9tNDVd3zOpLdGxT6/KRIDnYsyeCvLdp6QQ3S0FPmIk2i/i4zDDZ/kP6kqYAlpBxoFIDkfc73e5tR5qDco1h+Tyt7wtESdv0xiGAa+e2WwPWNv9+tBUvmyUuNJ/euWczO+0ghq+uj5xwZ/RYVEBJJ3vtpDe5WSatjifTjLnqF3/KvqNteTRmwnAmEPUb/B5JUw3rPd8dql9gqWfLL7wZtHyRDjmwzPw0vEO6g/8//Zen15kXxgF+rJ9ODMV1rm/liy9kqv/LkpKQBaLoY1Zv0DVo0E4HbdRzxLQRG8kTFtQK+Lb/0/AIbW4abVgUqG7/dBdx1nMt2VNZlr1QHhmvF2Vk9tISg6dmSW6n0vbCTZk6hJ69bpFWuslGAxI6tzJnZnXsp4PnX3EGqqlef6AG2ZBQEq+EWijS6apNbah1JJXMHe5E+FvvxA+0PXaYIYOWOOe/uxRPbGLtO3XInAcOy7b6RllGAhBRwUFbtRWIkdWQkLWtd/xJvatNP23k= neningermilan@MacBook-Pro
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHuzteX+kHMLA7ohArwOhooGovDaBmbZNjs9e1G9ZqHU9DagxHdBdhrBc4A06TyMpYBBsTF+puhHvhzDB5CZGgk=
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLI4Gmoiouf/4nO+K59ucWFrbrQE6/UryQjAzy1RH4shgaMCCAem0NDkQSwFM7h5cw4hJmx/gYhzpEEXxGs8m9k=
EOF
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
  sed -i 's/#PasswordAuthentication/PasswordAuthentication/g' /etc/ssh/sshd_config
  systemctl reload ssh
  touch build/ssh
fi

if [[ ! -f build/runner_user ]]
then
  useradd -m runner
  touch build/runner_user
fi

if [[ ! -f build/hostname ]]
then
  HOSTNAME=$(echo "$@" | awk -F' --name ' '{print $2;}' | cut -d' ' -f1)
  hostnamectl set-hostname "$HOSTNAME"
  touch build/hostname
fi

if [[ ! -f build/nix_install ]]
then
  sh <(curl -L https://nixos.org/nix/install) < /dev/null --daemon
  touch build/nix_install
fi

if ! grep 'extra-experimental-features = nix-command flakes' /etc/nix/nix.conf > /dev/null
then
  echo 'extra-experimental-features = nix-command flakes' >> /etc/nix/nix.conf
fi

if [[ ! -f build/docker_install ]]
then
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update

  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  touch build/docker_install
fi

if [[ ! -f build/runner_install ]]
then
  (
  cd /home/runner
  ARGS="$@"
  su runner /usr/bin/env bash -c 'curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz'
  su runner /usr/bin/env bash -c 'echo "ba46ba7ce3a4d7236b16fbe44419fb453bc08f866b24f04d549ec89f1722a29e  actions-runner-linux-x64-2.321.0.tar.gz" | shasum -a 256 -c'
  su runner /usr/bin/env bash -c 'tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz'
  su runner /usr/bin/env bash -c "./config.sh $ARGS"
  echo "$PATH" > .path
  )
  touch build/runner_install
fi

if [[ ! -f build/ssh-strict-host-key-checking ]]
then
  echo "StrictHostKeyChecking=accept-new" > ~/.ssh/config
  touch build/ssh-strict-host-key-checking
fi

if [[ ! -f build/ssh-agent-setup ]]
then
  (
  cd /home/runner
  mkdir -p bin
  cat << EOF >/home/runner/bin/ssh-agent-setup
set -eu

mkdir -p \$HOME/.ssh
echo "\$DEPLOY_KEY" > \$HOME/.ssh/deploy_key
chmod 0600 \$HOME/.ssh/deploy_key

eval \`ssh-agent\`
echo "SSH_AUTH_SOCK=\$SSH_AUTH_SOCK" >> \$GITHUB_ENV
echo "SSH_AGENT_PID=\$SSH_AGENT_PID" >> \$GITHUB_ENV

ssh-add \$HOME/.ssh/deploy_key
EOF

  chown runner bin/ssh-agent-setup
  chmod a+x bin/ssh-agent-setup
  echo "$PATH:$PWD/bin:/nix/var/nix/profiles/default/bin" > .path
  )
  touch build/ssh-agent-setup
fi

if [[ ! -f build/nix-conf ]]
then
  (
  cat <<EOF >/etc/nix/nix.conf
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
trusted-users = root @wheel
extra-sandbox-paths =
experimental-features = nix-command flakes recursive-nix
EOF
  )
  touch build/nix-conf
fi

if [[ ! -f build/docker-gc-setup ]]
then
  (
  cat <<EOF >/etc/systemd/system/docker-gc.timer
[Unit]
Description=Run docker GC timer
Requires=docker-gc.service
[Timer]
Unit=docker-gc.service
OnUnitInactiveSec=1w
[Install]
WantedBy=timers.target
EOF

  cat <<EOF >/etc/systemd/system/docker-gc.service
[Unit]
Description=Run docker GC
Wants=docker-gc.timer
[Service]
ExecStart=docker system prune --all -f
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable docker-gc.service docker-gc.timer
  systemctl start docker-gc.service docker-gc.timer
  )
  touch build/docker-gc-setup
fi