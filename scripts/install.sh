#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

INDEXER_PASSWORD="${INDEXER_PASSWORD:-SecretPassword}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-kibanaserver}"
API_PASSWORD="${API_PASSWORD:-MyS3cr37P450r.*-}"

if [ ! -f "$HERE/config/wazuh_indexer_ssl_certs/root-ca.pem" ]; then
    "$HERE/scripts/generate-certs.sh"
fi

mkdir -p "$QUADLET_DIR"
rm -rf "$QUADLET_DIR/config"
ln -s "$HERE/config" "$QUADLET_DIR/config"
install -m 0644 "$HERE"/quadlet/*.container "$HERE"/quadlet/*.network "$QUADLET_DIR/"

create_secret() {
    local name="$1" value="$2"
    if podman secret inspect "$name" >/dev/null 2>&1; then
        podman secret rm "$name" >/dev/null
    fi
    printf '%s' "$value" | podman secret create "$name" -
}

create_secret INDEXER_PASSWORD "$INDEXER_PASSWORD"
create_secret DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD"
create_secret API_PASSWORD "$API_PASSWORD"

loginctl enable-linger "$USER" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user start wazuh-indexer.service wazuh-manager.service wazuh-dashboard.service

echo "Wazuh started, dashboard at https://localhost:8443"
