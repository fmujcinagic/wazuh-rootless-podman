#!/bin/bash
# Offline certificate generation, mirroring wazuh-certs-generator's entrypoint
# but without its internet download. The wazuh-certs-tool.sh helper is copied
# out of the indexer image beforehand (the indexer image has no openssl to run
# it with), then executed here inside the generator image which does.
#
# Expected mounts:
#   /work         = <install_root>/config   (holds certs.yml and the tool)
#   /certificates = <install_root>/config/wazuh_indexer_ssl_certs
# Runs as root inside the container; the chowns below land on the subordinate
# uids that the indexer (1000) and manager (999) containers use.

cp /work/certs.yml /work/config.yml
chmod 700 /work/wazuh-certs-tool.sh

cd /work
source /work/wazuh-certs-tool.sh -A

echo "Moving created certificates to the destination directory"
cp /work/wazuh-certificates/* /certificates/
echo "Setting permissions"
# Each container reads its key pair as a different (subordinate mapped) uid,
# so a strict per-uid chown is not portable. The files live under a 0700 home
# directory, therefore 0644 keeps them private to the host while leaving them
# readable for the indexer (1000) and manager (999) containers.
chmod 0644 /certificates/*
cp /certificates/root-ca.pem /certificates/root-ca-manager.pem
cp /certificates/root-ca.key /certificates/root-ca-manager.key

rm -rf /work/wazuh-certificates /work/config.yml /work/wazuh-certificates-tool.log

echo "certificates created"
