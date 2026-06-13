# Validation Notes

Validated locally:

```bash
bash -n offline-bundle/scripts/download-k3s-artifacts.sh \
  offline-bundle/scripts/download-ansible-debs.sh \
  offline-bundle/scripts/install-ansible-offline.sh \
  offline-bundle/scripts/verify-artifacts.sh

cd offline-bundle/ansible
ANSIBLE_HOME=../../.ansible-home \
ANSIBLE_LOCAL_TEMP=../../.ansible-tmp \
ansible-playbook --syntax-check -i inventory.ini playbooks/site.yml
```

Payload verification requires a prepared `offline-bundle/payload/` directory. Prepare it on an internet-connected host with Docker:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD/offline-bundle:/offline-bundle" \
  -w /offline-bundle \
  ubuntu:26.04 \
  bash -lc '
    apt-get update &&
    apt-get install -y curl ca-certificates &&
    ./scripts/download-k3s-artifacts.sh &&
    ./scripts/download-ansible-debs.sh &&
    ./scripts/verify-artifacts.sh
  '
```

Or prepare it on a networked Ubuntu 26.04 AMD64 host:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
./scripts/verify-artifacts.sh
```

`verify-artifacts.sh` requires real K3s artifacts, Ubuntu 26.04 AMD64 `.deb` packages, and `payload/checksums.txt`.

Validated on an isolated Ubuntu 26.04 AMD64 EC2 target:

```bash
cd "$HOME/offline-bundle"
./scripts/verify-artifacts.sh
sudo ./scripts/install-ansible-offline.sh

cd "$HOME/offline-bundle/ansible"
ansible-playbook -i inventory.ini playbooks/site.yml

sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo systemctl status k3s
```

Expected result: Ansible installs from local `.deb` packages, the K3s playbook completes without internet access, the single node is Ready, and core `kube-system` pods are Running or Completed.
