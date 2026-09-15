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

node_names=$(cert_parseYaml /work/config.yml | grep -E 'nodes[_]+server[_]+[0-9]+=' | sed -e 's/nodes__server__[0-9]=//' | sed 's/"//g')

echo "Moving created certificates to the destination directory"
cp /work/wazuh-certificates/* /certificates/
echo "Changing certificate permissions"
chmod -R 500 /certificates
chmod -R 400 /certificates/*
echo "Setting UID indexer and dashboard"
chown 1000:1000 /certificates/*
echo "Setting UID for wazuh manager"
cp /certificates/root-ca.pem /certificates/root-ca-manager.pem
cp /certificates/root-ca.key /certificates/root-ca-manager.key
chown 999:999 /certificates/root-ca-manager.pem
chown 999:999 /certificates/root-ca-manager.key

for i in ${node_names}; do
    chown 999:999 "/certificates/${i}.pem"
    chown 999:999 "/certificates/${i}-key.pem"
done

rm -rf /work/wazuh-certificates /work/config.yml /work/wazuh-certificates-tool.log

echo "certificates created"
