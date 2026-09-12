#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$HERE/config/wazuh_indexer_ssl_certs"

podman run --rm \
    -e CERT_TOOL_VERSION=4.14 \
    -v "$HERE/config/wazuh_indexer_ssl_certs:/certificates" \
    -v "$HERE/config/certs.yml:/config/certs.yml" \
    docker.io/wazuh/wazuh-certs-generator:0.0.4
