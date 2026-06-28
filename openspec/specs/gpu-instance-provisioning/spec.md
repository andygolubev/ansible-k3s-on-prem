# gpu-instance-provisioning Specification

## Purpose
TBD - created by archiving change add-gpu-vllm-k3s. Update Purpose after archive.
## Requirements
### Requirement: GPU instance specification

The infrastructure SHALL provision an AWS EC2 `g5.2xlarge` instance (1× NVIDIA A10G 24 GB GPU, 8 vCPU, 32 GiB RAM) as the single K3s node, with a 200 GB gp3 root EBS volume. The CloudFormation template SHALL default to `g5.2xlarge` and SHALL NOT silently fall back to a non-GPU instance type.

#### Scenario: Stack deploys with GPU instance type

- **WHEN** the CloudFormation template is deployed with default parameters
- **THEN** the launched instance is of type `g5.2xlarge`
- **AND** the root volume is a 200 GB `gp3` EBS volume

#### Scenario: Root volume sized for offline artifacts

- **WHEN** the instance boots and the offline bundle is transferred
- **THEN** the 200 GB gp3 root volume has sufficient capacity for the OS, K3s, container images, and persistent model copy

### Requirement: Ephemeral NVMe storage layout

The deployment SHALL document and configure a storage layout that places persistent/critical data (OS, K3s state and config, backups, persistent model copy) on the EBS root volume, and places large or regenerable caches (container image cache, model cache, temporary inference data) on the ~450 GB local NVMe instance store. The documentation SHALL include explicit warnings that the NVMe instance store is ephemeral and is lost on stop/start or termination, and persistent data MUST NOT rely solely on it.

#### Scenario: NVMe mounted for caches

- **WHEN** the operator follows the storage setup steps on a fresh instance
- **THEN** the local NVMe instance-store device is formatted and mounted at the documented mountpoint
- **AND** cache paths (container images and/or model cache) are placed on the NVMe mount

#### Scenario: Persistent data survives NVMe loss

- **WHEN** the instance is stopped and started (discarding instance-store contents)
- **THEN** persistent data and the canonical model copy on the EBS root volume remain intact
- **AND** any caches lost from NVMe can be repopulated from the EBS copy or offline bundle without internet access

#### Scenario: Ephemeral data-loss warning is documented

- **WHEN** an operator reads the storage layout documentation
- **THEN** it states that NVMe instance-store data is ephemeral and lists which paths are safe to lose

