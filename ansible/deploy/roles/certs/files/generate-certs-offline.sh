#!/bin/bash
# Offline equivalent of wazuh-certs-generator:0.0.4.
# The generator image downloads wazuh-certs-tool.sh from packages.wazuh.com,
# which is a no-go in an air gap. The indexer image already ships the same
# tool, so copy it into the mounted work directory and run it there: the tool
# derives its output path from its own location, hence the copy.
#
# Mounted as: /work = <install_root>/config, /certificates = /work/wazuh_indexer_ssl_certs
# Run as root inside the container; the chowns below land on the subordinate
# uids the containers use, same as the upstream generator.

CERT_TOOL=/usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-certs-tool.sh

cp "$CERT_TOOL" /work/wazuh-certs-tool.sh
cp /work/certs.yml /work/config.yml
chmod 700 /work/wazuh-certs-tool.sh

cd /work
source /work/wazuh-certs-tool.sh -A

node_names=$(cert_parseYaml /work/config.yml | grep -E 'nodes[_]+server[_]+[0-9]+=' | sed -e 's/nodes__server__[0-9]=//' | sed 's/"//g')

cp /work/wazuh-certificates/* /certificates/ || exit 1
chmod -R 500 /certificates
chmod -R 400 /certificates/*
chown 1000:1000 /certificates/*
cp /certificates/root-ca.pem /certificates/root-ca-manager.pem
cp /certificates/root-ca.key /certificates/root-ca-manager.key
chown 999:999 /certificates/root-ca-manager.pem
chown 999:999 /certificates/root-ca-manager.key

for i in ${node_names}; do
    chown 999:999 "/certificates/${i}.pem"
    chown 999:999 "/certificates/${i}-key.pem"
done

rm -rf /work/wazuh-certificates /work/wazuh-certs-tool.sh /work/config.yml /work/wazuh-certificates-tool.log

if [ -f /certificates/root-ca.pem ]; then
    echo "certificates created"
else
    echo "ERROR: certificates were not created"
    exit 1
fi
