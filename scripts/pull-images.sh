#!/usr/bin/env bash
#
# This script pulls the current Wazuh images from the registry and saves them to a local directory.
# Make sure to run from the root of the repository, and that podman is installed and configured to pull from the registry.
#
set -euo pipefail

VERSION_FILE="WAZUH_VERSION"
OUT_DIR="wazuh-current-image-releases"
LOCK_FILE="images-lock.yml"
REGISTRY="${WZ_REGISTRY:-docker.io}"

[[ -f "$VERSION_FILE" ]] || { echo "missing $VERSION_FILE"; exit 1; }
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
mkdir -p "$OUT_DIR"

IMAGES=(
  "wazuh/wazuh-indexer"
  "wazuh/wazuh-dashboard"
  "wazuh/wazuh-manager"
  "wazuh/wazuh-agent"
)

echo "Current Wazuh version is: $VERSION"

entries=()
tars=()

for img in "${IMAGES[@]}"; do
  full="$REGISTRY/$img:$VERSION"
  tar="$OUT_DIR/${img#wazuh/}-$VERSION.tar"
  if [[ -f "$tar" ]]; then
    echo "exists, skipping pull/save: $tar"
  else
    podman pull "$full"
    podman save --format docker-archive -o "$tar" "$full"
    [[ -f "$tar" ]] || { echo "failed to save $full -> $tar"; exit 1; }
    echo "saved $full -> $tar"
  fi
  digest="$(podman image inspect --format '{{.Digest}}' "$full")"
  checksum="$(sha256sum "$tar" | awk '{print $1}')"

  entries+=(
    "  - image: $img"
    "    tag: $VERSION"
    "    digest: $digest"
    "    tar: $tar"
    "    sha256: $checksum"
  )
  tars+=("$tar")
done

{
  printf 'images_lock:\n'
  printf '  version: %s\n' "$VERSION"
  printf '  registry: %s\n' "$REGISTRY"
  printf '  images:\n'
  printf '%s\n' "${entries[@]}"
} > "$LOCK_FILE"

echo "Finished writing $LOCK_FILE and saved images to $OUT_DIR"
