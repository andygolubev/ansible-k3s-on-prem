# k3s-gpu-runtime Specification

## Purpose
TBD - created by archiving change add-gpu-vllm-k3s. Update Purpose after archive.
## Requirements
### Requirement: Offline NVIDIA host driver installation

The bundle SHALL include the NVIDIA GPU driver packages required for the target OS/kernel (Ubuntu 26.04 amd64) and SHALL install them on the host from local artifacts only, with no access to NVIDIA repositories, apt, or PyPI. After installation `nvidia-smi` SHALL report the A10G GPU on the host.

#### Scenario: Driver installs from local packages

- **WHEN** the GPU install step runs on the offline target
- **THEN** the NVIDIA driver is installed from `.deb` packages in the offline payload only
- **AND** no external apt or NVIDIA repository is contacted

#### Scenario: Host detects the GPU

- **WHEN** `nvidia-smi` is run on the host after driver installation
- **THEN** it lists one NVIDIA A10G GPU with its driver and CUDA version

### Requirement: NVIDIA container runtime for K3s containerd

The deployment SHALL install and configure the NVIDIA container toolkit/runtime so that K3s containerd can run GPU-enabled containers, using only artifacts from the offline bundle. The NVIDIA runtime SHALL be registered with containerd and selectable for GPU workloads.

#### Scenario: Container toolkit configured offline

- **WHEN** the GPU runtime configuration step runs on the offline target
- **THEN** the NVIDIA container toolkit is installed from local packages and the `nvidia` runtime is registered in the K3s containerd configuration
- **AND** containerd is restarted/reloaded so the runtime is active

### Requirement: NVIDIA device plugin and GPU scheduling

The deployment SHALL deploy the NVIDIA device plugin (manifest or chart, with its image loaded from the offline bundle) so the node advertises `nvidia.com/gpu` capacity, and Kubernetes SHALL be able to schedule pods that request `nvidia.com/gpu: 1`.

#### Scenario: Node advertises GPU capacity

- **WHEN** the device plugin is deployed and ready
- **THEN** `kubectl describe node` shows `nvidia.com/gpu` allocatable equal to 1

#### Scenario: Test pod accesses the GPU

- **WHEN** a validation pod requesting `nvidia.com/gpu: 1` is scheduled and runs `nvidia-smi`
- **THEN** the pod is scheduled onto the GPU node
- **AND** `nvidia-smi` inside the pod reports the A10G GPU

### Requirement: GPU artifacts present in offline bundle

All packages and images required for GPU enablement (driver `.deb` packages, container toolkit packages, device-plugin manifest and image, and any CUDA runtime images needed) SHALL be present in the offline bundle with SHA256 checksums and SHALL be verified before installation.

#### Scenario: Verification covers GPU artifacts

- **WHEN** the artifact verification script runs
- **THEN** it confirms the presence and checksums of the NVIDIA driver packages, container toolkit packages, device-plugin manifest/image, and required CUDA images

