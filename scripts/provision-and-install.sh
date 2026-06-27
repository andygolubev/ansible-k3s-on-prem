#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

REGION="${AWS_REGION:-eu-west-2}"
STACK_NAME="${STACK_NAME:-k3s-on-prem}"
INSTANCE_TYPE="${INSTANCE_TYPE:-g5.2xlarge}"
ROOT_VOLUME_SIZE="${ROOT_VOLUME_SIZE:-200}"
SSH_CIDR="${SSH_CIDR:-}"
KEY_FILE="${KEY_FILE:-${PROJECT_ROOT}/.aws/${STACK_NAME}.pem}"
REMOTE_BUNDLE_DIR="${REMOTE_BUNDLE_DIR:-/home/ubuntu/offline-bundle}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

TEST HARNESS: provision EC2, upload the bundle, and run the target installer.

This is not the isolated-server installation entry point. On a real target,
copy the repository from removable media and run ./install.sh.

Options:
  --region REGION          AWS region (default: ${REGION})
  --stack-name NAME        CloudFormation stack name (default: ${STACK_NAME})
  --instance-type TYPE     EC2 instance type (default: ${INSTANCE_TYPE})
  --root-volume-size GIB   Root gp3 volume size (default: ${ROOT_VOLUME_SIZE})
  --ssh-cidr CIDR          Allowed SSH source; auto-detects public_ip/32
  --key-file PATH          Local generated-key destination
  --remote-bundle-dir PATH Remote test-copy destination (default: ${REMOTE_BUNDLE_DIR})
  -h, --help               Show this help

Environment variables with the uppercase option names are also supported.
EOF
}

while (($#)); do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    --stack-name) STACK_NAME="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --root-volume-size) ROOT_VOLUME_SIZE="$2"; shift 2 ;;
    --ssh-cidr) SSH_CIDR="$2"; shift 2 ;;
    --key-file) KEY_FILE="$2"; shift 2 ;;
    --remote-bundle-dir) REMOTE_BUNDLE_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for command in aws curl ssh tar; do
  command -v "${command}" >/dev/null || {
    echo "Required command not found: ${command}" >&2
    exit 1
  }
done

if [[ -z "${SSH_CIDR}" ]]; then
  public_ip="$(curl --fail --silent --show-error https://checkip.amazonaws.com | tr -d '[:space:]')"
  [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Could not detect a public IPv4 address; pass --ssh-cidr explicitly." >&2
    exit 1
  }
  SSH_CIDR="${public_ip}/32"
fi

echo "Verifying the prepared offline payload..."
"${PROJECT_ROOT}/offline-bundle/scripts/internal/verify-artifacts.sh"

required_full_stack_artifacts=(
  "offline-bundle/payload/tools/k9s/VERSION"
  "offline-bundle/payload/tools/k9s/k9s"
  "offline-bundle/payload/observability/VERSIONS.env"
  "offline-bundle/payload/observability/images/images.tsv"
  "offline-bundle/payload/observability/manifests/install-local.yaml"
)
for artifact in "${required_full_stack_artifacts[@]}"; do
  [[ -f "${PROJECT_ROOT}/${artifact}" ]] || {
    echo "Full-stack artifact is missing: ${artifact}" >&2
    echo "Prepare operator-tools and observability artifacts before deploying." >&2
    exit 1
  }
done

echo "Deploying CloudFormation stack ${STACK_NAME} in ${REGION}..."
aws cloudformation deploy \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${PROJECT_ROOT}/cloudformation-ec2-ssh-only.yaml" \
  --parameter-overrides \
    "SshCidr=${SSH_CIDR}" \
    "InstanceType=${INSTANCE_TYPE}" \
    "RootVolumeSize=${ROOT_VOLUME_SIZE}" \
  --no-fail-on-empty-changeset

stack_output() {
  aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" \
    --output text
}

instance_id="$(stack_output InstanceId)"
public_dns="$(stack_output PublicDnsName)"
key_parameter="$(stack_output PrivateKeySsmParameterPath)"

mkdir -p "$(dirname "${KEY_FILE}")"
key_tmp="$(mktemp "$(dirname "${KEY_FILE}")/.${STACK_NAME}.pem.XXXXXX")"
trap 'rm -f "${key_tmp:-}"' EXIT
aws ssm get-parameter \
  --region "${REGION}" \
  --name "${key_parameter}" \
  --with-decryption \
  --query Parameter.Value \
  --output text >"${key_tmp}"
chmod 400 "${key_tmp}"
mv -f "${key_tmp}" "${KEY_FILE}"
key_tmp=""

echo "Waiting for ${instance_id} and SSH (${public_dns})..."
aws ec2 wait instance-status-ok --region "${REGION}" --instance-ids "${instance_id}"

ssh_options=(
  -i "${KEY_FILE}"
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=20
)

for attempt in {1..30}; do
  if ssh "${ssh_options[@]}" "ubuntu@${public_dns}" true 2>/dev/null; then
    break
  fi
  if ((attempt == 30)); then
    echo "SSH did not become ready on ${public_dns}." >&2
    exit 1
  fi
  sleep 10
done

echo "Uploading offline-bundle as removable-media test data (about $(du -sh "${PROJECT_ROOT}/offline-bundle" | awk '{print $1}'))..."
ssh "${ssh_options[@]}" "ubuntu@${public_dns}" "rm -rf '${REMOTE_BUNDLE_DIR}' && mkdir -p '${REMOTE_BUNDLE_DIR}'"
COPYFILE_DISABLE=1 tar \
  --no-xattrs \
  -C "${PROJECT_ROOT}/offline-bundle" \
  -cf - . | ssh "${ssh_options[@]}" "ubuntu@${public_dns}" "tar -C '${REMOTE_BUNDLE_DIR}' -xf -"

echo "Running the same target-side installer used with removable media..."
ssh "${ssh_options[@]}" "ubuntu@${public_dns}" "bash -se" <<REMOTE
set -Eeuo pipefail
sudo cloud-init status --wait
cd '${REMOTE_BUNDLE_DIR}'
sudo ./install.sh
REMOTE

echo
echo "Installation complete."
echo "Instance: ${instance_id}"
echo "SSH: ssh -i '${KEY_FILE}' ubuntu@${public_dns}"
