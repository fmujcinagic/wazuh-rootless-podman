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

## Prerequisites

* Podman 4.4 or newer
* systemd 253 or newer
* At least 4 GB of RAM for the indexer
* `vm.max_map_count` of at least 262144

```
sudo sysctl -w vm.max_map_count=262144
```

## Install

```
./scripts/install.sh
```

The script generates the TLS certificates if they are missing, creates the
Podman secrets, copies the Quadlet units to
`~/.config/containers/systemd/`, enables lingering for the user and starts the
three services.

To change the default passwords, export them before running the script:

```
INDEXER_PASSWORD=... API_PASSWORD=... DASHBOARD_PASSWORD=... ./scripts/install.sh
```

The generated passwords also need a matching internal users database; for the
Ansible deployment this is handled by regenerating the user database
(`wazuh_regen_users`).

## Manage

```
systemctl --user status wazuh-indexer wazuh-manager wazuh-dashboard
systemctl --user restart wazuh-manager
journalctl --user -u wazuh-manager -f
```

To remove the services (the Podman volumes and secrets are kept):

```
./scripts/uninstall.sh
```

## Access

| Service | Port | URL |
| --- | --- | --- |
| wazuh.dashboard | 8443 | https://localhost:8443 |
| wazuh.indexer | 9200 | https://localhost:9200 |
| wazuh.manager | 1514, 1515, 55000, 5514/udp | agents, enrollment, API, syslog |

Default credentials:

* Dashboard and indexer: `admin` / `SecretPassword`
* Wazuh API: `wazuh-wui` / `MyS3cr37P450r.*-`

The passwords live in the Podman secret store, not in the repository or the
Quadlet files.

## Agent deployment

`agent/run-agent.sh` deploys the stock Wazuh agent container. It mounts the
integration collector logs read only and enrolls against the manager:

```
WAZUH_MANAGER_SERVER=<manager-ip> WAZUH_AGENT_NAME=<host> \
  WAZUH_AGENT_GROUP=podman ./agent/run-agent.sh
```

Agents connect to the manager on 1514 (events) and 1515 (enrollment). Point the agent at the host IP. In case the other ports are available or should be used, this is configurable in the ossec.conf of the Wazuh Agent.

The log directories are `~/.local/state/wazuh-podman` and
`~/.local/state/wazuh-network`, written by the collectors from the
integration hub repository.

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

* Quadlet resolves relative paths in `Volume=` against the directory that
  contains the unit file. `install.sh` symlinks the repository `config/`
  directory into `~/.config/containers/systemd/` so the certificates keep
  their ownership.
* The certificates generated by `wazuh-certs-generator` are owned by the
  subordinate UIDs that map to the indexer (1000) and manager (999) users, so
  the stack must run with the default rootless mapping rather than
  `--userns=keep-id`.
* The indexer needs `vm.max_map_count`. Verify it before starting.
