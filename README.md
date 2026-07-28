# server-baseline

Ansible roles that turn a stock Ubuntu 24.04 host into a hardened Docker host. Shared by the projects
that run DHIS2 workloads on plain servers, so the hardening has one implementation rather than one per
repository:

- [dhis2/docker-deployment](https://github.com/dhis2/docker-deployment) - the DHIS2 instance servers.
- [dhis2-sre/dhis2-infrastructure](https://github.com/dhis2-sre/dhis2-infrastructure) -
  `services/im-vm`, the Instance Manager control plane.

Extracted from `server-tools/roles` in dhis2/docker-deployment with its history, so `git log` and
`git blame` still explain why each rule is there. The `harden` role was originally adapted from
dhis2-sre/microk8s-playbook.

## Roles

Run them in this order, then whatever is specific to your project:

| Role | What it does |
|---|---|
| `bootstrap` | Base packages, Docker Engine and the compose plugin from Docker's apt repository, the operator account, and `deploy_dir` |
| `firewall` | Default deny `DOCKER-USER` chain, allowing only the ports you list plus inter-container traffic, persisted with `netfilter-persistent` |
| `harden` | SSH, kernel, AppArmor, fail2ban and Docker daemon hardening, including user namespace remapping |

`firewall` exists because Docker bypasses the host's `INPUT` chain for published container ports, so
host level rules never see that traffic. Do not put UFW or another frontend alongside it.

```yaml
- name: Provision a Docker host
  hosts: all
  become: true

  roles:
    - bootstrap
    - firewall
    - harden
```

## Variables

Every variable has a default. Override in `group_vars/all.yml`.

| Variable | Default | Role | Purpose |
|---|---|---|---|
| `docker_user` | inventory `ansible_user` | bootstrap | Owns `deploy_dir` and is the user namespace remap target. Set it to a dedicated account to have one created |
| `docker_user_password` | none | bootstrap | Pre-hashed, required only when `docker_user` is a dedicated account. `!` locks the password, which is what a service account wants |
| `docker_user_ssh_key` | none | bootstrap | Optional public key for a dedicated operator account |
| `deploy_dir` | `/opt/dhis2` | bootstrap | Directory owned by `docker_user` |
| `bootstrap_packages` | see defaults | bootstrap | Base packages. Includes `make` because docker-deployment drives its stacks with a Makefile on the host |
| `allowed_ssh_users` | `[ ubuntu ]` | harden | SSH `AllowUsers`. `docker_user` is appended automatically |
| `firewall_allowed_ports` | `[ 22, 80, 443 ]` | firewall | Host facing TCP ports |
| `firewall_allowed_udp_ports` | `[ 51820 ]` | firewall | Host facing UDP ports. 51820 is WireGuard |

Operators are deliberately **not** added to the root equivalent `docker` group. Give them a scoped
`sudo` rule for the command they need instead.

## Consuming it

These are plain roles, not a collection, so the simplest integration is a pinned checkout on the
`roles_path`. `ansible.cfg`:

```ini
[defaults]
roles_path = ./roles:./external/server-baseline/roles
```

And a fetch step that pins a commit rather than a branch, so the hardening cannot change under you
between two runs of the same playbook:

```make
SERVER_BASELINE_REF ?= <commit>
SERVER_BASELINE_URL ?= https://github.com/dhis2-sre/server-baseline.git

roles: external/server-baseline/.git
	git -C external/server-baseline fetch --depth 1 origin $(SERVER_BASELINE_REF)
	git -C external/server-baseline checkout -q FETCH_HEAD
	ansible-galaxy collection install --requirements-file external/server-baseline/requirements.yml

external/server-baseline/.git:
	git clone --no-checkout $(SERVER_BASELINE_URL) external/server-baseline
```

`services/im-vm/ansible` in dhis2-infrastructure is a working example.

## Requirements

- `ansible-core`, plus the `ansible.posix` collection (see `requirements.yml`). `bootstrap` uses
  `authorized_key`, which core does not ship.
- Ubuntu 24.04 on the target.
- **Connect as a non-root account with sudo.** `harden` sets `PermitRootLogin no`, so a playbook run
  as `root` succeeds once and then locks itself out. Create the account before the first run, for
  example from cloud-init.

## Things to know before you run this

- **User namespace remapping breaks containers that need the Docker socket.** The container's root
  maps to an unprivileged host uid, which cannot read `/var/run/docker.sock`. Traefik's Docker
  provider is the common casualty; use its file provider, or `userns_mode: host` for that one
  container if you accept handing it root equivalent access.
- **Bind mounted directories need to be world readable** for the same reason, or the remapped
  container uid cannot traverse them.
- **`/tmp` is mounted `noexec`.** Installers that unpack to `/tmp` and execute from there fail. Use
  `/usr/local/src` or similar.
- **IPv6 is disabled** by the sysctl list. Override those two keys if you publish AAAA records.
- **`icc: false`** applies to the default bridge only. Containers on user defined networks, which is
  what compose creates, still reach each other.

## Known issues

- `bootstrap` uses `apt_key` and `apt_repository`, both deprecated and due for removal in
  `ansible-core` 2.25. They need migrating to `deb822_repository`.
- The roles are not clean under `ansible-lint` yet: no fully qualified module names, and `command`
  tasks without `changed_when`. Left as extracted so the move is reviewable on its own.
- No Galaxy metadata (`meta/main.yml`), so `ansible-galaxy role install` is not an option yet.
