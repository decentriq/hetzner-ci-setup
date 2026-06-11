#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME:-gcp-integration-runner-1}"
MACHINE_TYPE="${MACHINE_TYPE:-c3-highmem-44}"
ZONE="${ZONE:-europe-west1-b}"
REGION="${REGION:-${ZONE%-*}}"
MIN_CPU_PLATFORM="${MIN_CPU_PLATFORM:-Intel Sapphire Rapids}"

NETWORK="${NETWORK:-gcp-integration-runner}"
SUBNET="${SUBNET:-gcp-integration-runner-${REGION}}"
SUBNET_RANGE="${SUBNET_RANGE:-10.20.0.0/24}"
NETWORK_TAG="${NETWORK_TAG:-gcp-integration-runner}"
FIREWALL_RULE="${FIREWALL_RULE:-allow-ssh-gcp-integration-runner}"

BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-1000GB}"
BOOT_DISK_TYPE="${BOOT_DISK_TYPE:-pd-balanced}"
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-2404-lts-amd64}"
IMAGE_PROJECT="${IMAGE_PROJECT:-ubuntu-os-cloud}"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
SSH_SOURCE_CIDR="${SSH_SOURCE_CIDR:-}"

usage() {
  cat <<EOF
Usage: PROJECT_ID=<project> SSH_SOURCE_CIDR=<admin-ip-or-cidr> $0

Creates the GCP resources for a persistent integration-test GitHub runner with nested virtualization.

Required:
  PROJECT_ID         Existing GCP project with billing enabled. Defaults to gcloud's active project.
  SSH_SOURCE_CIDR    CIDR allowed to SSH to the runner, for example 203.0.113.10/32.

Optional environment overrides:
  INSTANCE_NAME      ${INSTANCE_NAME}
  MACHINE_TYPE       ${MACHINE_TYPE}
  ZONE               ${ZONE}
  REGION             ${REGION}
  MIN_CPU_PLATFORM   ${MIN_CPU_PLATFORM}
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

echo "Ensuring required APIs are enabled..."
gcloud services enable \
  compute.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project "$PROJECT_ID"

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
  existing_nested=$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(advancedMachineFeatures.enableNestedVirtualization)')
  existing_min_cpu_platform=$(gcloud compute instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" --zone "$ZONE" --format 'value(minCpuPlatform)')

  [[ "$existing_machine_type" == "$MACHINE_TYPE" ]] || die "existing machine type is $existing_machine_type, expected $MACHINE_TYPE"
  [[ "$existing_network" == "$NETWORK" ]] || die "existing network is $existing_network, expected $NETWORK"
  [[ "$existing_subnet" == "$SUBNET" ]] || die "existing subnet is $existing_subnet, expected $SUBNET"
  [[ "$existing_disk_size" == "$(disk_size_gb "$BOOT_DISK_SIZE")" ]] || die "existing disk size is ${existing_disk_size}GB, expected $BOOT_DISK_SIZE"
  [[ "$existing_disk_type" == "$BOOT_DISK_TYPE" ]] || die "existing disk type is $existing_disk_type, expected $BOOT_DISK_TYPE"
  [[ "$existing_nested" == "True" || "$existing_nested" == "true" ]] || die "existing instance does not have nested virtualization enabled"
  [[ "$existing_min_cpu_platform" == "$MIN_CPU_PLATFORM" ]] || die "existing min CPU platform is $existing_min_cpu_platform, expected $MIN_CPU_PLATFORM"

  echo "Existing instance matches requested shape. Nothing to create."
  exit 0
fi

echo "Creating instance: $INSTANCE_NAME"
gcloud compute instances create "$INSTANCE_NAME" \
  --project "$PROJECT_ID" \
  --zone "$ZONE" \
  --machine-type "$MACHINE_TYPE" \
  --min-cpu-platform "$MIN_CPU_PLATFORM" \
  --enable-nested-virtualization \
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

Integration runner VM is ready for bootstrap.

Next:
  gcloud compute scp --project "$PROJECT_ID" --zone "$ZONE" gcloud/setup-runner.sh gcloud/setup-integration-runner.sh "$INSTANCE_NAME":~/
  gcloud compute ssh --project "$PROJECT_ID" --zone "$ZONE" "$INSTANCE_NAME" -- 'sudo bash ~/setup-integration-runner.sh'
  gcloud compute scp --project "$PROJECT_ID" --zone "$ZONE" gcloud/start-runner.sh "$INSTANCE_NAME":~/start-runner.sh
  gcloud compute ssh --project "$PROJECT_ID" --zone "$ZONE" "$INSTANCE_NAME" -- 'sudo bash ~/start-runner.sh'
EOF
