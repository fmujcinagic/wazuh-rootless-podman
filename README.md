# Wazuh Rootless Podman Deployment

Since the official Wazuh documentation as of day of writing doesn't support native rootless Podman deployment this is the deployment of the single-node Wazuh (indexer, manager, dashboard) running entirely as a rootless Podman user, managed by systemd with Quadlet. This works out of the box. No root daemon, no privileged ports, no Docker.

## Why rootless Podman

Wazuh is usually deployed with Docker. On production hosts, and on RHEL and
its derivatives in particular, that is a problem:

* The Docker daemon runs as root and its socket is root equivalent. Adding a
  user to the `docker` group grants full root access, which is not acceptable
  under least privilege or a hardened baseline.
* Workarounds that run the rootful Docker daemon as a normal user, such as
  `dockerrootplease` (https://github.com/chrisfosterelli/dockerrootplease),
  only relocate the root daemon. They depend on a root-owned socket, can break
  with SELinux enforcing, cgroup or storage driver changes, and are not
  supported by the distribution.
* Docker is not part of the standard RHEL repositories, while Podman is.
  Running the stack with Podman stays inside the supported package set and the
  existing SELinux policy.

Podman runs containers under the calling user with a user namespace and no
daemon. Quadlet lets systemd start and supervise the containers as user
services, so the stack survives reboots and can be upgraded by a regular user
without granting root or installing Docker. Rootless containers cannot bind
ports below 1024, which is why the dashboard is published on 8443 and syslog
on 5514.

## Requirements

* Podman 4.4 or newer, systemd 253 or newer, cgroup v2 on the target
* Ansible (2.17+) with the `containers.podman` and `ansible.posix`
  collections on the machine that runs the CLI
* At least 4 GB of RAM and `vm.max_map_count` of 262144 for the indexer
  (the playbook sets it on the master automatically)
* A Rocky/RHEL-family target VM; the CLI can install `podman` and `python3`
  on a fresh machine itself

## Deploy

Everything goes through the interactive helper in the repository root:

```
./wazuh.cfg
```

1. Pick the deployment type: standalone server, worker manager + local
   agent, or agent only.
2. Answer the prompts for the mode (see "Node modes" below).
3. Answer the target VM prompts (host, ssh user, sudo password, optional
   podman storage directory). The CLI offers to install podman and python3
   over ssh on a fresh VM, renders `ansible/deploy/inventory/hosts.yml` and
   runs the playbook.

The stack is deployed as a dedicated rootless `wazuh` user on the target,
with TLS certificates generated inside the certificates-generator image, all
secrets in the Podman secret store and linger enabled so the stack survives
reboots. Repeat runs converge to zero changes; passwords are only re-hashed
when the fingerprint in `vault/<host>.yml` changes.

To build the offline bundle beforehand or rebuild it for a new Wazuh version,
run the bundle playbook on an internet-connected machine and copy the result
to the target:

```
cd ansible/bundle && ansible-playbook build-bundle.yml
```

## Access

| Service | Port | URL |
| --- | --- | --- |
| wazuh.dashboard | 8443 | https://localhost:8443 |
| wazuh.indexer | 9200 | https://localhost:9200 |
| wazuh.manager | 1514, 1515, 55000, 5514/udp | agents, enrollment, API, syslog |

Passwords are generated on the first master run and stored in
`ansible/deploy/vault/<host>.yml`; the verification summary at the end of a
run prints the admin login. The passwords live in the Podman secret store,
not in the repository or the Quadlet files.

## Manage

```
systemctl --user status wazuh-indexer wazuh-manager wazuh-dashboard
systemctl --user restart wazuh-manager
journalctl --user -u wazuh-manager -f
```

## Node modes

The Ansible playbook in `ansible/deploy` knows three node modes, picked by
the `wazuh_node_role` variable or through the interactive helper `wazuh.cfg`
in the repository root:

1. **Standalone server** (`wazuh_node_role=master`) - indexer, manager and
   dashboard on one VM, acting as the cluster master. If a cluster key is
   given, the manager leaves the cluster port open so workers can join.
2. **Worker manager + local agent** (`wazuh_node_role=worker`) - joins an
   existing master. The CLI asks for the master host, the cluster name and
   the cluster key, plus the master's indexer admin and API passwords (the
   worker ships its events into the master's indexer). It optionally pulls
   `root-ca-manager.pem`, `wazuh.manager.pem` and `wazuh.manager-key.pem`
   from the master into `/var/tmp/wazuh-worker-certs` on the target; the
   playbook moves them into `config/wazuh_indexer_ssl_certs/` before the
   manager starts.
3. **Agent only** (`wazuh_node_role=agent`) - a Wazuh agent enrolled against
   a remote manager. The CLI asks for the manager host, the events port,
   the enrollment port, the agent name and the agent group. The agent
   container runs with the host network, because rootless port publishing
   does not accept container to host IP connections on every setup.

All three modes reuse the same offline bundle and the same
`ansible/deploy/deploy.yml` playbook; the playbook switches the Quadlet
layout, the manager cluster block and the verification based on the role.
Enrollment happens on port 1515 during agent registration, after which
the agent pushes events to the manager on port 1514. To rotate the indexer
passwords later, change them in the vault file and re-run the deployment
with `wazuh_regen_users=true`; the user database is rebuilt and every
consumer container is restarted.

## Loading integrations

The stack is a plain Wazuh manager, so custom decoders, rules and dashboards
can be added. The repository stays generic; add a Quadlet drop-in for the
manager instead of editing the unit. You can try this with the examples for the Podman provisioning and network bandwidth monitoring that can be found
on my Github profile:

```bash
mkdir -p ~/.config/containers/systemd/wazuh-manager.container.d
# create the e.g. file: ~/.config/containers/systemd/wazuh-manager.container.d/10-integrations.conf
# with the following content:
# ----
[Container]
Volume=/path/to/decoders:/var/ossec/ruleset/decoders/0005a-custom.xml:ro
Volume=/path/to/rules:/var/ossec/etc/rules/custom_rules.xml:ro
# ----

systemctl --user daemon-reload
systemctl --user restart wazuh-manager
```

Decoders that must run before the built-in JSON decoder are named with a low
prefix (for example `0005a-`) so they sort before `0006-json_decoders.xml`.
This is the Quadlet naming convention. On Podman 4.x, where Quadlet drop-ins
are not available, add the `Volume=` lines to
`quadlet/wazuh-manager.container` before running `scripts/install.sh`.

The Quadlet units were generated from the original compose file with
`podlet compose` and then adapted for rootless use.

## Credits

The configuration files under `config/` are derived from the official Wazuh
Docker repository (https://github.com/wazuh/wazuh-docker), Copyright (C) 2017,
Wazuh Inc., licensed under GPLv2. The Quadlet units, scripts and this
documentation are original. Wazuh is a trademark of Wazuh, Inc.

## Notes

* The certificates generated by `wazuh-certs-generator` are owned by the
  subordinate UIDs that map to the indexer (1000) and manager (999) users, so
  the stack must run with the default rootless mapping rather than
  `--userns=keep-id`.
* The agent container runs on the host network; see the agent mode above.
* A worker joins by cluster key and needs the master's certificates; both
  come from the master deployment and are requested by the CLI.
