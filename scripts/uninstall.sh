#!/usr/bin/env bash
set -euo pipefail

QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

systemctl --user stop \
    wazuh-dashboard.service wazuh-manager.service wazuh-indexer.service 2>/dev/null || true
rm -f "$QUADLET_DIR"/wazuh-*.container "$QUADLET_DIR"/wazuh.network "$QUADLET_DIR/config"
systemctl --user daemon-reload

echo "Wazuh services removed. Podman volumes and secrets were kept."
