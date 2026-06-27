# ansible-k3s-on-prem

Proof of concept for K3s in an isolated environment.

## Install on an isolated server

Prepare `offline-bundle/payload/` on a networked machine, copy the
`offline-bundle/` directory to removable media, and connect that media to the
isolated Ubuntu 26.04 AMD64 server. From the copied bundle directory, run:

```bash
cd offline-bundle
./install.sh
```

The installer elevates with `sudo`, verifies OS, architecture, free space, and
all payload checksums, bootstraps Ansible from local packages, then installs
K3s, GPU support, Argo CD, k9s, observability, and vLLM. It prints numbered
stages, timestamps, verbose Ansible tasks, and final cluster status for the
human operator. It does not provision infrastructure or require internet.

## AWS test harness

`cloudformation-ec2-ssh-only.yaml` and the following command exist only to test
the removable-media installation flow on a temporary EC2 host:


```bash
./scripts/provision-and-install.sh \
  --stack-name k3s-on-prem \
  --region eu-west-2 \
  --ssh-cidr 203.0.113.10/32
```

The harness provisions the test host, copies the project as if it came from
removable media, then invokes the same root-level `install.sh` on that host.

See `offline-bundle/README-offline.md` for payload preparation, architecture,
validation, and rollback details.
