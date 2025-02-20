#!/usr/bin/env bash
set -euo pipefail

cat /root/configs/simple-debian64-raid | sed 's|/root/images/Debian-stable-amd64-base.tar.gz|/root/images/Ubuntu-2404-noble-amd64-base.tar.gz|g' | sed 's/Debian-stable-amd64-base/runner/g' | sed 's|/dev/sda|/dev/nvme0n1|g' | sed 's|/dev/sdb|/dev/nvme1n1|g' > ubuntu
installimage -c ./ubuntu
reboot
