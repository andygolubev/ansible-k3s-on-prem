# EC2 Testing Handoff Log

Last updated: 2026-06-27 (Asia/Jerusalem)

## Current status

- AWS CloudFormation stack `k3s-on-prem` is `CREATE_COMPLETE` in `eu-west-2`.
- EC2 instance `i-06eb140d78dae846d` is running.
- The self-contained `offline-bundle/` has been copied to the VM at
  `/home/ubuntu/offline-bundle` (about 28 GB).
- A complete remote SHA-256 verification passed before installation started.
- The human-facing target installer was started with
  `/home/ubuntu/offline-bundle/install.sh`.
- At the time of this handoff it was still in stage 2/5, verifying payload
  checksums for a second time as part of the installer. Running processes were:

  ```text
  3904 bash /home/ubuntu/offline-bundle/install.sh
  3916 bash /home/ubuntu/offline-bundle/scripts/verify-artifacts.sh
  ```

- The remote root filesystem had 164 GiB available (193 GiB total).

## Connect to the test VM

Run these commands from the repository root:

```bash
cd /Users/andy/repo/andygolubev/ansible-k3s-on-prem
chmod 400 .aws/k3s-on-prem.pem
ssh -i .aws/k3s-on-prem.pem \
  ubuntu@ec2-18-134-164-108.eu-west-2.compute.amazonaws.com
```

Equivalent public IP: `18.134.164.108`.

The security group permits SSH only from `147.235.195.89/32`. If the operator's
public IP changes, update the CloudFormation `SshCidr` parameter before trying
to connect.

If the local PEM is missing, retrieve it from SSM (do not commit it):

```bash
mkdir -p .aws
aws ssm get-parameter \
  --region eu-west-2 \
  --name /ec2/keypair/key-058c8a8511730e2b2 \
  --with-decryption \
  --query Parameter.Value \
  --output text > .aws/k3s-on-prem.pem
chmod 400 .aws/k3s-on-prem.pem
```

## Monitor or resume installation

Check whether installation is still running:

```bash
ssh -i .aws/k3s-on-prem.pem \
  ubuntu@ec2-18-134-164-108.eu-west-2.compute.amazonaws.com \
  'pgrep -af "install.sh|verify-artifacts|ansible-playbook" || true'
```

The original installer output is attached to the Codex unified terminal
session that started it, so a different agent may not inherit that stream.
Inspect progress through processes and cluster state:

```bash
sudo systemctl status k3s --no-pager || true
sudo k3s kubectl get nodes -o wide || true
sudo k3s kubectl get pods -A || true
```

If no installer process remains and installation did not finish, rerun the
same idempotent target command:

```bash
cd /home/ubuntu/offline-bundle
./install.sh
```

`install.sh` elevates itself with sudo and displays five verbose stages:

1. Host preflight.
2. Payload checksum verification.
3. Offline Ansible bootstrap.
4. Full Ansible installation.
5. Final node and pod status.

Do not run two copies of `install.sh` concurrently.

## What was implemented

- Added the actual isolated-host entry point at `offline-bundle/install.sh`.
- The installer is verbose and intended to be run by a human after copying the
  `offline-bundle/` directory from removable media.
- It does not provision infrastructure or copy files over a network.
- Made `offline-bundle/` self-contained:
  - versioned GitOps definitions are in `offline-bundle/gitops/app-of-apps/`;
  - versioned agent source/chart are in `offline-bundle/gitops/agent/`;
  - Ansible uses those paths without depending on repository siblings.
- Clarified that `offline-bundle/payload/` is gitignored and contains only
  generated/downloaded internet artifacts. Important versioned files stay
  directly under `offline-bundle/`.
- Added/updated README and architecture instructions for the removable-media
  workflow.
- Kept AWS provisioning and transfer separate as a test harness at
  `scripts/provision-and-install.sh`.
- Downloaded the previously missing k9s and observability payload artifacts.
- Verified the complete payload locally and remotely.
- Fixed NVMe setup so rerunning Ansible formats an uninitialized instance-store
  device only; it no longer reformats a device that already has a filesystem.

The structural work is already committed on `main`:

```text
055d1f4 Migrate to offline-bundle directory structure
de310bb Refactor offline install workflow and documentation
```

The NVMe idempotency fix is currently staged but not committed:

```text
M  offline-bundle/ansible/roles/gpu_offline/tasks/main.yml
```

## Work left

1. Let the target installer finish, or rerun it if its SSH session terminated.
2. Diagnose and fix any Ansible/runtime failure encountered on the fresh VM.
3. Validate the completed stack using `offline-bundle/VALIDATION.md`, especially:
   - host `nvidia-smi`;
   - K3s node Ready;
   - `nvidia.com/gpu` allocatable;
   - all pods healthy;
   - vLLM `/v1/models` and `/v1/chat/completions`.
4. Commit the staged NVMe idempotency fix after testing.
5. Terminate the billable test stack when testing is finished.

## AWS test operations

Inspect the stack and instance:

```bash
aws cloudformation describe-stacks \
  --region eu-west-2 \
  --stack-name k3s-on-prem

aws ec2 describe-instances \
  --region eu-west-2 \
  --instance-ids i-06eb140d78dae846d
```

Delete all test infrastructure when it is no longer needed:

```bash
aws cloudformation delete-stack \
  --region eu-west-2 \
  --stack-name k3s-on-prem

aws cloudformation wait stack-delete-complete \
  --region eu-west-2 \
  --stack-name k3s-on-prem
```

Deletion terminates the EC2 instance and deletes its root EBS volume. Preserve
any logs needed for diagnosis before deleting the stack.
