# Wazuh Federated Rootless Podman Deployment

The goal of this project is to develop a rootless Podman Wazuh deployment (as of time of writing this, the Wazuh officially supports only Docker deployment out-of-box ). Here we will use the [quadlets](https://www.redhat.com/en/blog/quadlet-podman), and goal is to achieve the [Cross-Cluster Search](https://wazuh.com/blog/managing-multiple-wazuh-clusters-with-cross-cluster-search/) in simulated air-gapped environment (3 VMs - RHEL distro, Debian-based distro and the Arch-based distro). Deployment should be done through the Ansible.

Plan would be also to integrate the Renovate (reference: [Renovate](https://docs.renovatebot.com/)), and to achieve the air-gapped GitOps. This is just an idea and it is to be tested how far we get with this.

## !! Disclaimer & Safety Warning !!

> **IMPORTANT:** This tool is designed solely for authorized security testing and research.

## PoC Architecture Overview
- **all IPs are just mock IPs specific to my local setup and may need readjusting depending on your own environment/deployment**
- master node (host OS ; Ubuntu 24.04.4 LTS) - 127.0.0.1/127.0.1.1(accessible from the worker node)
- first worker node: (RHEL; Rocky Linux 10.2 (Red Quartz))
  - IP and ports: 192.168.122.74 - 22/TCP (SSH/Ansible))

## Wazuh Images - Offline Approach
- `./scripts/pull-images.sh` pulls the current Wazuh images into `wazuh-current-image-releases/` (gitignored, kept locally for the air-gapped transfer). It reads the pinned version from `WAZUH_VERSION`, `podman pull`s + `podman save`s each image to a `.tar`, and writes `images-lock.yml` with the image digests and tar sha256 checksums so the exact artifacts are auditable.
  ```
  ./scripts/pull-images.sh
  # -> wazuh-current-image-releases/*.tar  +  images-lock.yml
  ```
- `WAZUH_VERSION` is the single source of truth for the image tag. Renovate bumps it when a newer Wazuh version is released.

## Air-gapped GitOps with Renovate
- [`renovate.json`](renovate.json) tracks `wazuh/wazuh-*` image tags as a Docker datasource (grouped into one "Wazuh images" PR, digests pinned). The `WAZUH_VERSION` file is managed so the version bump lands there.
- To let Renovate open that PR automatically on a schedule, add the Renovate GitHub App to this repo (https://github.com/apps/renovate) and enable it — no workflow file needed.