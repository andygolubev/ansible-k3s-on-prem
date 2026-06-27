# EC2 Testing Handoff Log

Last updated: 2026-06-27 (Asia/Jerusalem)

## Current status

- AWS CloudFormation stack `k3s-on-prem` is `CREATE_COMPLETE` in `eu-west-2`.
- EC2 instance `i-06eb140d78dae846d` is running (`g5.2xlarge`, A10G GPU).
- The self-contained `offline-bundle/` is on the VM at
  `/home/ubuntu/offline-bundle` (about 28 GB); remote SHA-256 verified.
- **First `install.sh` run reached stage 4 (Ansible) and failed silently.** The
  K3s base came up (node Ready, core kube-system pods Running/Completed), but
  the playbook died before creating the GPU validation pod or any
  application/observability pods. Root cause found and fixed (see below).
- **Root cause of the first-run failure:** Ubuntu EC2 loads the `nouveau` kernel
  module at boot and it binds the A10G before the `nvidia` driver can claim it.
  The `gpu_offline` role had no nouveau handling, so `nvidia-smi` failed and the
  playbook stopped at the "Verify nvidia-smi works on host" task. Validated on
  the VM: `NVRM: GPU 0000:00:1e.0 is already bound to nouveau.` in dmesg.
- **Fix applied to `gpu_offline` role (now staged locally and copied to the VM):**
  - Reuse the driver if `nvidia-smi` already works (skip `.deb` install).
  - Blacklist `nouveau` in `/etc/modprobe.d/` and refresh initramfs.
  - Unbind NVIDIA GPUs from the `nouveau` PCI driver, `rmmod nouveau`, then
    `modprobe nvidia` (validated in place on this VM without a reboot —
    `nvidia-smi` then returns `NVIDIA A10G, 23028 MiB, 580.159.03`).
  - Only fall back to the local `.deb` driver install if the modules still
    cannot load.
- **The nouveau/GPU-driver fix is DONE and verified.** See "GPU fix (done,
  verified)" below.
- **The blocker is now a K3s CNI problem that is NOT fixed.** See
  "Open problem — K3s CNI not initializing (UNRESOLVED)" below. This must be
  solved before the playbook can get past the GPU-capacity check and before
  vLLM/observability can deploy. The next agent should start there.

### Handoff snapshot (preceding state, kept for reference)
- The original installer was observed in stage 2/5 verifying payload checksums:

  ```text
  3904 bash /home/ubuntu/offline-bundle/install.sh
  3916 bash /home/ubuntu/offline-bundle/scripts/verify-artifacts.sh
  ```

- The remote root filesystem had 164 GiB available (193 GiB total).

## GPU fix (done, verified)

The `gpu_offline` Ansible role now reuses an already-working NVIDIA driver instead
of always reinstalling it, and it kicks the `nvidia` modules past `nouveau` (the
open driver that grabs the A10G at boot). Validated live on this VM:

- Before fix: `nouveau` bound the GPU; `nvidia-smi` failed with
  `NVRM: GPU 0000:00:1e.0 is already bound to nouveau`.
- After fix (first run): runtime unbind of the GPU from `nouveau`, `rmmod
  nouveau`, `modprobe nvidia` got `nvidia-smi` working with **no reboot**:
  `NVIDIA A10G, 23028 MiB, 580.159.03`.
- After fix (reboot): `nouveau` is now correctly **blacklisted and not loaded at
  boot**; only `nvidia / nvidia_uvm / nvidia_drm / nvidia_modeset` load, and
  `nvidia-smi` works immediately on boot. So the offline-install driver path is
  fully solved and persistently idempotent.

Changes are staged in the working tree (not committed):

```text
M  offline-bundle/ansible/roles/gpu_offline/tasks/main.yml
```

(The NVMe idempotency fix is in the same file.) The role logic is now:

1. Probe `nvidia-smi`; if it works, set `nvidia_driver_functional` and skip the
   `.deb` install entirely (reuse the installed driver).
2. If not functional: write `/etc/modprobe.d/blacklist-nouveau.conf`
   (`blacklist nouveau` + `options nouveau modeset=0`), then
   `update-initramfs -u -k all` so it survives reboots.
3. Find NVIDIA GPU PCI addresses bound to `nouveau` (under
   `/sys/bus/pci/drivers/nouveau/*:*:*.*`) and `echo <addr> > .../unbind`.
4. `modprobe -r nouveau`, then `modprobe nvidia nvidia-uvm nvidia-modeset
   nvidia-drm` (`nvidia-drm` may fail "busy" — harmless; compute doesn't need it).
5. Only if `nvidia-smi` STILL fails after module load, fall back to
   `dpkg -i {{ gpu_driver_deb_dir }}/*.deb`.

## Open problem — K3s CNI not initializing (UNRESOLVED)

> **Confirmed root cause:** the partial NVIDIA `config.toml.tmpl` replaced
> K3s's generated containerd configuration. `k3s crictl info` showed containerd
> looking for CNI configuration in `/etc/cni/net.d` and binaries in
> `/opt/cni/bin`, while K3s installs them under `/var/lib/rancher/k3s/`. The
> nftables warning was unrelated: iptables NAT/mangle operations succeed. The
> repair removes this template, relies on K3s runtime auto-discovery, validates
> the effective CNI paths, and explicitly selects `RuntimeClass: nvidia` for
> GPU workloads.

**This is the current blocker. Solve this before re-running the playbook.**

### Symptom

The K3s node stays `NotReady`, and the kubelet reports forever:

```
container runtime network not ready: NetworkReady=false reason=NetworkPluginNotReady
message: Network plugin returns error: cni plugin not initialized
```

Because the node carries the `node.kubernetes.io/not-ready:NoSchedule` taint,
the `nvidia-device-plugin` DaemonSet (which only tolerates `nvidia.com/gpu`,
NOT the not-ready taint) never schedules → `nvidia.com/gpu` allocatable stays
empty → the `gpu_offline` task "Verify node advertises nvidia.com/gpu capacity"
fails after 30 retries, aborting the playbook. The base system pods that need
pod networking (coredns, metrics-server, traefik) are stuck `0/1 Running`
forever; only hostNetwork pods (svclb-traefik, local-path-provisioner) are
healthy.

### Root cause (strong lead, not 100% confirmed)

It is a flannel/CNI initialization race that K3s v1.36.1+k3s1 hits on this
**Ubuntu 26.04 + kernel 7.0.0-1006-aws** image. The fresh-boot sequence in the
k3s log (PID changes each boot) is:

```
17:45:05 "Starting flannel with backend vxlan"
17:45:05 "Flannel found PodCIDR assigned for node ip-10-0-1-10"   (podCIDR 10.42.0.0/24 IS set)
17:45:06 VXLAN config VNI=1; flannel.1 mac set
17:45:06 "Starting flannel in iptables mode..."
17:45:06 warning: "Failed to load kernel module nft-expr-counter with modprobe"   <-- SUSPECT
17:45:06 warning: "no subnet found for key: FLANNEL_NETWORK in file /run/flannel/subnet.env" (etc.)
17:45:06 "Wrote flannel subnet file to /run/flannel/subnet.env"
17:45:06 "Running flannel backend." / "watching for new subnet leases"
17:45:07 E "Error syncing pod ... NetworkReady=false ... cni plugin not initialized"
```

So flannel **does** start, finds the PodCIDR, writes `/run/flannel/subnet.env`,
and brings `flannel.1` up with `10.42.0.0/32`. But `cni0` (the linux bridge
flannel creates for pods) **never appears**, and the kubelet's CNI status probe
never flips to ready. The kubelet's own sandbox-creation errors confirm the CNI
plugin call fails at runtime:

```
failed to setup network for sandbox ...: plugin type="flannel" failed (add):
failed to load flannel 'subnet.env' file: open /run/flannel/subnet.env: no such file or directory
```

(this specific message was from the original boot; on later boots subnet.env
exists but `cni0` still never comes up, so the race/early-failure leaves the
kubelet's CNI status permanently stuck even though the data plane partly worked
on the first boot — `cni0 10.42.0.1/24` came up on the first boot but NOT after
restarts/reboot).

### Strongest hypotheses to investigate (in priority order)

1. **nftables / iptables-nft backend broken on kernel 7.0.** K3s logs
   `"Failed to load kernel module nft-expr-counter with modprobe"`. Flannel
   runs `"Starting flannel in iptables mode"` immediately after; if the
   nftables kernel modules it needs aren't available on this Ubuntu 26.04
   kernel, the flannel iptables setup fails and the CNI bridge (`cni0`) is
   never created. Check:
   - `modprobe nft_expr_counter` and `modprobe nft_counter` on the host — do
     they load? Are `/lib/modules/$(uname -r)/kernel/net/netfilter/nft*` and
     `nf_tables*` present?
   - `update-alternatives --display iptables` — is it `iptables-nft`?
   - `iptables -t nat -L` and `iptables -t mangle -L` — do they error?
   - Whether `/lib/modules/7.0.0-1006-aws` is missing the netfilter/nft
     modules (EC2 minimal kernel vs the packages the playbook installed).
2. **flannel/CNI plugin status probe doesn't recover after an early failure.**
   The kubelet caches "not initialized" from a transient early race and never
   re-checks positively even once subnet.env + cni0 exist. A clean K3s restart
   did NOT fix it (tried twice); a full VM reboot did NOT fix it either. This
   points at root-cause #1 (a hard failure, not a race), since a race would
   usually self-heal on reboot.
3. **containerd config template interaction.** The `gpu_offline` role drops a
   minimal `config.toml.tmpl` that only ADDS an `nvidia` runtime (does NOT set
   it as default), so containerd's default runtime stays `runc`. This is very
   likely NOT the cause (CNI is flannel/kubelet, independent of containerd
   runtimes), but the template is present and K3s logs
   `"Using containerd config template at .../config.toml.tmpl"`. Removing it
   temporarily is a cheap way to rule it out. The template lives at
   `offline-bundle/ansible/roles/gpu_offline/templates/containerd-nvidia-runtime.toml.j2`
   and is written to the VM at
   `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`.

### What is KNOWN-GOOD (do not re-investigate these)

- CNI binaries present and executable:
  `/var/lib/rancher/k3s/data/<hash>/bin/{flannel,bridge,loopback,portmap,bandwidth,host-local,firewall}`
  are symlinks to a multicall `cni` binary; `loopback` and `flannel` run fine
  when invoked directly (CNI_COMMAND=VERSION returns supported versions).
- CNI conflist present:
  `/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist`
  (name=cbr0, cniVersion 1.0.0, plugins flannel+portmap+bandwidth).
- `/run/flannel/subnet.env` exists after boot:
  `FLANNEL_NETWORK=10.42.0.0/16`, `FLANNEL_SUBNET=10.42.0.1/24`,
  `FLANNEL_MTU=8951`, `FLANNEL_IPMASQ=true`.
- Node spec has `podCIDR 10.42.0.0/24`.
- `flannel.1` interface comes up with `10.42.0.0/32`; on the first boot only,
  `cni0` came up with `10.42.0.1/24` (data plane worked); after restart/reboot
  `cni0` does NOT come back.
- `net.ipv4.ip_forward=1`, `net.bridge.bridge-nf-call-iptables=1`.
- K3s install args are minimal (`server --write-kubeconfig-mode 644`) — flannel
  is default-on, nothing disabled. Defined in
  `offline-bundle/ansible/group_vars/all.yml` (`k3s_install_args`).
- Secure Boot is **disabled** (not a module-signing issue).

### What has already been tried (didn't work)

- `sudo systemctl restart k3s` (twice) — node stays NotReady.
- `sudo rm -f /var/lib/cni/networks/*` + restart — no change.
- Full VM reboot — node STILL NotReady on the fresh boot (this rules out "just
  a transient race needing a reboot"; see hypothesis #1/#2).

### Suggested next steps for the fixing agent

1. Reproduce and confirm hypothesis #1 first — it's the most probable and most
   testable. On the VM:
   ```bash
   sudo modprobe nft_expr_counter; echo "rc=$?"
   sudo modprobe nft_counter;      echo "rc=$?"
   ls /lib/modules/$(uname -r)/kernel/net/netfilter/ | grep -E 'nft|nf_tables'
   ls /lib/modules/$(uname -r)/kernel/net/ipv4/netfilter/ | grep -iE 'iptable|nf_nat'
   sudo update-alternatives --display iptables
   sudo iptables -t nat -L -n   # does it error?
   # Is the extra-modules package even installed?
   dpkg -l | grep -E 'linux-modules-extra|linux-modules-7.0.0-1006-aws'
   ```
   EC2 AWS kernels often keep nftables/extra netfilter modules in the
   `linux-modules-extra-*-aws` package. If that package isn't installed (and
   you're offline), the netfilter modules flannel needs are likely missing —
   which would explain the `nft-expr-counter` load failure and the missing
   `cni0` bridge.
2. If extra-modules are missing, the bundle's K3s/GPU `.deb` download scripts
   need to also fetch `linux-modules-extra-$(uname -r)` (or whatever Ubuntu
   names it on 26.04) into the offline payload, and the `k3s_offline` role needs
   to install it before starting K3s. That is the durable, repeatable fix.
3. As a quick verification (NOT the durable fix), you can grab the matching
   `linux-modules-extra` .deb on an internet host and `dpkg -i` it on the VM,
   then `systemctl restart k3s` and see if the node goes Ready and `cni0`
   appears. If yes, hypothesis #1 is confirmed.
4. To rule out hypothesis #3 in parallel, temporarily move the containerd
   template aside and restart K3s:
   ```bash
   sudo mv /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl{,.bak}
   sudo systemctl restart k3s
   ```
   If the node then goes Ready, the NVIDIA containerd template merge is the
   culprit and the template needs to preserve K3s's default runtime block.
5. Once the node reliably goes Ready on boot, fix the `gpu_offline` role so the
   playbook doesn't fail on the cold-start CNI race even when it's transient:
   add a "wait for node Ready / CNI ready" task (retry loop on the node Ready
   condition, e.g. 60 × 5s) BEFORE the device-plugin apply and the
   `nvidia.com/gpu` capacity check. Today the capacity check retries 30 ×
   (gpu_validation_delay) but the underlying node never becomes Ready, so more
   retries alone won't help — the node must actually go Ready first.

### Relevant files

- `offline-bundle/ansible/roles/gpu_offline/tasks/main.yml` — the task that
  fails is "Verify node advertises nvidia.com/gpu capacity" (~line 420 after
  the staged edits). Also where the nouveau/driver-reuse fix lives.
- `offline-bundle/ansible/roles/k3s_offline/tasks/main.yml` — K3s install;
  good place to add `linux-modules-extra` install if hypothesis #1 holds.
- `offline-bundle/ansible/group_vars/all.yml` — `k3s_install_args`,
  `gpu_validation_retries`/`gpu_validation_delay`.
- `offline-bundle/VALIDATION.md` — full acceptance checklist to run once the
  node is Ready and the playbook completes.

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

The NVMe idempotency fix and the nouveau/driver-reuse fix are both in
`offline-bundle/ansible/roles/gpu_offline/tasks/main.yml`, currently staged but
not committed:

```text
M  offline-bundle/ansible/roles/gpu_offline/tasks/main.yml
```

## Work left

1. **Solve the K3s CNI / node-NotReady problem** (see "Open problem — K3s CNI
   not initializing"). Start with the nftables / `linux-modules-extra`
   hypothesis. This is THE blocker — nothing else can proceed until the node
   goes Ready.
2. Once the node goes Ready reliably, finish the playbook (vLLM, observability)
   and run the `offline-bundle/VALIDATION.md` acceptance checks.
3. Add a "wait for node Ready" task to the `gpu_offline` role before the
   device-plugin/capacity-check steps so a transient cold-start CNI race can't
   abort the playbook.
4. Commit the staged `gpu_offline/main.yml` (NVMe + nouveau/driver-reuse fixes)
   after testing.
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
