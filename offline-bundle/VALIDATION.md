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

Deferred until artifacts are downloaded on a supported Linux AMD64 host:

```bash
cd offline-bundle
./scripts/download-k3s-artifacts.sh
./scripts/download-ansible-debs.sh
./scripts/verify-artifacts.sh
```

`verify-artifacts.sh` requires real K3s artifacts and Ubuntu 24.04 AMD64 `.deb` packages. This repository currently includes placeholder tracking files only.
