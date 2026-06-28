# ansible-k3s-on-prem

Offline K3s installation for an Ubuntu 26.04 AMD64 server.

## Prerequisite

Install and start Docker on the machine used to prepare the payload. At least
50 GB of free disk space is recommended.

## Download the payload

From the repository root, run:

```bash
cd offline-bundle
./scripts/download-all-artifacts.sh
```

## Install on the remote server

Copy the complete `offline-bundle` directory to the server. On the server, run:

```bash
cd offline-bundle
./install.sh
```
