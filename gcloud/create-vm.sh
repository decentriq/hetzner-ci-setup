#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME:-gcp-standalone-runner-1}"
MACHINE_TYPE="${MACHINE_TYPE:-c3d-highmem-4}"
ZONE="${ZONE:-europe-west1-b}"
REGION="${REGION:-${ZONE%-*}}"

NETWORK="${NETWORK:-gcp-standalone-runner}"
SUBNET="${SUBNET:-gcp-standalone-runner-${REGION}}"
SUBNET_RANGE="${SUBNET_RANGE:-10.10.0.0/24}"
NETWORK_TAG="${NETWORK_TAG:-gcp-standalone-runner}"
FIREWALL_RULE="${FIREWALL_RULE:-allow-ssh-gcp-standalone-runner}"

BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-500GB}"
BOOT_DISK_TYPE="${BOOT_DISK_TYPE:-pd-balanced}"
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-2404-lts-amd64}"
IMAGE_PROJECT="${IMAGE_PROJECT:-ubuntu-os-cloud}"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
SSH_SOURCE_CIDR="${SSH_SOURCE_CIDR:-}"

usage() {
  cat <<EOF
Usage: PROJECT_ID=<project> SSH_SOURCE_CIDR=<admin-ip-or-cidr> $0

Creates the GCP resources for a persistent standalone-test GitHub runner.

Required:
  PROJECT_ID         Existing GCP project with billing enabled. Defaults to gcloud's active project.
  SSH_SOURCE_CIDR    CIDR allowed to SSH to the runner, for example 203.0.113.10/32.

Optional environment overrides:
  INSTANCE_NAME      ${INSTANCE_NAME}
  MACHINE_TYPE       ${MACHINE_TYPE}
  ZONE               ${ZONE}
  REGION             ${REGION}
  NETWORK            ${NETWORK}
  SUBNET             ${SUBNET}
  SUBNET_RANGE       ${SUBNET_RANGE}
  NETWORK_TAG        ${NETWORK_TAG}
  FIREWALL_RULE      ${FIREWALL_RULE}
  BOOT_DISK_SIZE     ${BOOT_DISK_SIZE}
  BOOT_DISK_TYPE     ${BOOT_DISK_TYPE}
  IMAGE_FAMILY       ${IMAGE_FAMILY}
  IMAGE_PROJECT      ${IMAGE_PROJECT}
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

basename_url() {
  local value="$1"
  echo "${value##*/}"
}

disk_size_gb() {
  local value="$1"
  value="${value%GB}"
  value="${value%gb}"
  echo "$value"
}

[[ "${1:-}" != "--help" ]] || {
  usage
  exit 0
}

command -v gcloud >/dev/null || die "gcloud is not installed"
[[ -n "$PROJECT_ID" ]] || die "PROJECT_ID is required, or set an active gcloud project"
[[ -n "$SSH_SOURCE_CIDR" ]] || die "SSH_SOURCE_CIDR is required, for example $(curl -fsSL https://ifconfig.me 2>/dev/null || echo 203.0.113.10)/32"

echo "Using project: $PROJECT_ID"
gcloud projects describe "$PROJECT_ID" >/dev/null

echo "Ensuring Compute Engine API is enabled..."
gcloud services enable compute.googleapis.com --project "$PROJECT_ID"

if gcloud compute networks describe "$NETWORK" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "Network already exists: $NETWORK"
else
  echo "Creating network: $NETWORK"
  gcloud compute networks create "$NETWORK" \
    --project "$PROJECT_ID" \
    --subnet-mode custom
fi

if gcloud compute networks subnets describe "$SUBNET" --project "$PROJECT_ID" --region "$REGION" >/dev/null 2>&1; then
  echo "Subnet already exists: $SUBNET"
else
  echo "Creating subnet: $SUBNET ($SUBNET_RANGE)"
  gcloud compute networks subnets create "$SUBNET" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --network "$NETWORK" \
    --range "$SUBNET_RANGE"
fi

if gcloud compute firewall-rules describe "$FIREWALL_RULE" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "Firewall rule already exists: $FIREWALL_RULE"
else
  echo "Creating SSH firewall rule: $FIREWALL_RULE"
  gcloud compute firewall-rules create "$FIREWALL_RULE" \
    --project "$PROJECT_ID" \
    --network "$NETWORK" \
    --direction INGRESS \
    --priority 1000 \
    --action ALLOW \
    --rules tcp:22 \
    --source-ranges "$SSH_SOURCE_CIDR" \
    --target-tags "$NETWORK_TAG"
fi

if gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" >/dev/null 2>&1; then
  echo "Instance already exists: $INSTANCE_NAME"

  existing_machine_type=$(basename_url "$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(machineType)')")
  existing_network=$(basename_url "$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(networkInterfaces[0].network)')")
  existing_subnet=$(basename_url "$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(networkInterfaces[0].subnetwork)')")
  existing_boot_disk=$(basename_url "$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(disks[0].source)')")
  existing_disk_size=$(gcloud compute disks describe "$existing_boot_disk" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(sizeGb)')
  existing_disk_type=$(basename_url "$(gcloud compute disks describe "$existing_boot_disk" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(type)')")

  [[ "$existing_machine_type" == "$MACHINE_TYPE" ]] || die "existing machine type is $existing_machine_type, expected $MACHINE_TYPE"
  [[ "$existing_network" == "$NETWORK" ]] || die "existing network is $existing_network, expected $NETWORK"
  [[ "$existing_subnet" == "$SUBNET" ]] || die "existing subnet is $existing_subnet, expected $SUBNET"
  [[ "$existing_disk_size" == "$(disk_size_gb "$BOOT_DISK_SIZE")" ]] || die "existing disk size is ${existing_disk_size}GB, expected $BOOT_DISK_SIZE"
  [[ "$existing_disk_type" == "$BOOT_DISK_TYPE" ]] || die "existing disk type is $existing_disk_type, expected $BOOT_DISK_TYPE"

  echo "Existing instance matches requested shape. Nothing to create."
  exit 0
fi

echo "Creating instance: $INSTANCE_NAME"
gcloud compute instances create "$INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --provisioning-model STANDARD \
  --maintenance-policy MIGRATE \
  --image-family "$IMAGE_FAMILY" \
  --image-project "$IMAGE_PROJECT" \
  --boot-disk-size "$BOOT_DISK_SIZE" \
  --boot-disk-type "$BOOT_DISK_TYPE" \
  --boot-disk-device-name "$INSTANCE_NAME" \
  --network "$NETWORK" \
  --subnet "$SUBNET" \
  --tags "$NETWORK_TAG" \
  --scopes logging-write,monitoring-write

cat <<EOF

Runner VM is ready for bootstrap.

Next:
  gcloud compute scp --project "$PROJECT_ID" --zone "$ZONE" gcloud/setup-runner.sh "$INSTANCE_NAME":~/setup-runner.sh
  gcloud compute ssh --project "$PROJECT_ID" --zone "$ZONE" "$INSTANCE_NAME" -- 'sudo bash ~/setup-runner.sh'
  gcloud compute scp --project "$PROJECT_ID" --zone "$ZONE" gcloud/start-runner.sh "$INSTANCE_NAME":~/start-runner.sh
  gcloud compute ssh --project "$PROJECT_ID" --zone "$ZONE" "$INSTANCE_NAME" -- 'sudo bash ~/start-runner.sh'
EOF
