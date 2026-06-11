# GCP GitHub Runners

This folder provisions and bootstraps persistent Google Cloud runners for Delta GitHub Actions workflows.

It intentionally does not create the GCP project or attach billing. Start with an existing, billed, runner-only project.

## Standalone Runner Shape

- VM: `c3d-highmem-4`
- Region: `europe-west1`
- Zones: `europe-west1-b`, `europe-west1-c`, `europe-west1-d`
- Disk: `500GB pd-balanced`
- OS: Ubuntu 24.04 LTS x86_64
- Runner labels: `gcp,gcp-standalone,<runner-name>,standalone-tests,build,live`
- Runner user: `runner`
- GitHub runner: pinned to `2.334.0`

The runner deliberately does not get `runner` or `integration-tests` labels, because those workflows need nested virtualization and should not land on this VM.

## Integration Runner Shape

- VM: `c3-highmem-44`
- Region: `europe-west1`
- Zone: `europe-west1-b`
- Disk: `1000GB pd-balanced`
- OS: Ubuntu 24.04 LTS x86_64
- Runner labels: `gcp-integration,gcp-integration-runner-1,integration-tests,runner,build,live`
- Runner user: `runner`
- GitHub runner: pinned to `2.334.0`

The integration runner uses Intel C3 with nested virtualization enabled. Do not give it the `exodus-hetzner` label.

## Create the Standalone VM

Pick the GCP project and SSH source range first. Use a single-admin IP where possible.

```bash
export PROJECT_ID="<existing-billed-runner-project>"
export SSH_SOURCE_CIDR="$(curl -fsSL https://ifconfig.me)/32"

./gcloud/create-vm.sh
```

The script creates the Compute Engine API enablement, VPC network, subnet, SSH firewall rule, and VM. It is safe to rerun when the existing resources match the requested shape.

Useful overrides:

```bash
export INSTANCE_NAME="gcp-standalone-runner-1"
export MACHINE_TYPE="c3d-highmem-4"
export ZONE="europe-west1-b"
export BOOT_DISK_SIZE="500GB"
export BOOT_DISK_TYPE="pd-balanced"
```

Standalone rollout:

```bash
PROJECT_ID="<existing-billed-runner-project>" SSH_SOURCE_CIDR="$(curl -fsSL https://ifconfig.me)/32" INSTANCE_NAME="gcp-standalone-runner-1" ZONE="europe-west1-b" ./gcloud/create-vm.sh
PROJECT_ID="<existing-billed-runner-project>" SSH_SOURCE_CIDR="$(curl -fsSL https://ifconfig.me)/32" INSTANCE_NAME="gcp-standalone-runner-2" ZONE="europe-west1-c" ./gcloud/create-vm.sh
PROJECT_ID="<existing-billed-runner-project>" SSH_SOURCE_CIDR="$(curl -fsSL https://ifconfig.me)/32" INSTANCE_NAME="gcp-standalone-runner-3" ZONE="europe-west1-d" ./gcloud/create-vm.sh
```

## Create the Integration VM

```bash
export PROJECT_ID="<existing-billed-runner-project>"
export SSH_SOURCE_CIDR="$(curl -fsSL https://ifconfig.me)/32"

./gcloud/create-integration-vm.sh
```

Useful overrides:

```bash
export INSTANCE_NAME="gcp-integration-runner-1"
export MACHINE_TYPE="c3-highmem-44"
export ZONE="europe-west1-b"
export MIN_CPU_PLATFORM="Intel Sapphire Rapids"
export BOOT_DISK_SIZE="1000GB"
export BOOT_DISK_TYPE="pd-balanced"
```

## Bootstrap the Standalone Runner

Copy and run the remote bootstrap script:

```bash
gcloud compute scp \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcloud/setup-runner.sh \
  gcp-standalone-runner-1:~/setup-runner.sh

gcloud compute ssh \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcp-standalone-runner-1 \
  -- 'sudo bash ~/setup-runner.sh \
    --url https://github.com/decentriq \
    --name gcp-standalone-runner-1 \
    --labels gcp,gcp-standalone,gcp-standalone-runner-1,standalone-tests,build,live'
```

When prompted, paste a fresh GitHub organization runner registration token from the Decentriq organization runner settings page. Do not pass the token as a command-line argument.

To test one exact VM before using the shared label, bootstrap with the same labels and run a temporary workflow branch against:

```yaml
runs-on: [self-hosted, gcp-standalone-runner-1]
```

After the runner is proven, the standalone workflow can use the shared pool label:

```yaml
runs-on: [self-hosted, live, build, standalone-tests]
```

## Bootstrap the Integration Runner

Copy and run the remote bootstrap scripts:

```bash
gcloud compute scp \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcloud/setup-runner.sh \
  gcloud/setup-integration-runner.sh \
  gcp-integration-runner-1:~/

gcloud compute ssh \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcp-integration-runner-1 \
  -- 'sudo bash ~/setup-integration-runner.sh \
    --url https://github.com/decentriq \
    --name gcp-integration-runner-1 \
    --labels gcp-integration,gcp-integration-runner-1,integration-tests,runner,build,live'
```

Before registering the runner, the bootstrap validates nested virtualization with:

```bash
lscpu | grep Virtualization
test -e /dev/kvm
test -e /dev/vhost-vsock
test -e /dev/vhost-net
kvm-ok
docker-compose version
```

To test one exact integration VM before using the shared label, run temporary workflow branches against:

```yaml
runs-on: [self-hosted, gcp-integration-runner-1]
```

After the runner is proven, integration workflows can use:

```yaml
runs-on: [self-hosted, live, runner, integration-tests]
```

## Start or repair the service

Standalone runner:

```bash
gcloud compute scp \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcloud/start-runner.sh \
  gcp-standalone-runner-1:~/start-runner.sh

gcloud compute ssh \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcp-standalone-runner-1 \
  -- 'sudo bash ~/start-runner.sh'
```

Integration runner:

```bash
gcloud compute scp \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcloud/start-runner.sh \
  gcp-integration-runner-1:~/start-runner.sh

gcloud compute ssh \
  --project "$PROJECT_ID" \
  --zone "${ZONE:-europe-west1-b}" \
  gcp-integration-runner-1 \
  -- 'sudo bash ~/start-runner.sh'
```

## Notes

- The VM has a public IP for the first iteration, but SSH ingress is restricted by `SSH_SOURCE_CIDR`.
- Docker is installed and the `runner` user is added to the `docker` group.
- Daemon-mode Nix is installed with the existing CI settings and Cachix substituters.
- Google Cloud Ops Agent is installed so Cloud Monitoring can collect guest memory metrics.
- Integration runners load and persist `kvm_intel`, `vhost_vsock`, `vhost_net`, and `vsock`.
- A `/usr/local/bin/docker-compose` wrapper is installed for scripts that still call Compose v1 syntax.
- The `ssh-agent-setup` helper is preserved because `.github/workflows/standalone-tests.yml` uses it.
- Docker and Nix garbage-collection timers are installed to keep the persistent VM from filling its disk.
