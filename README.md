# server-baseline

Ansible roles that turn a stock Ubuntu 24.04 host into a hardened Docker host.

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
| `bootstrap_packages` | see defaults | bootstrap | Base packages. Includes `make` because one consumer drives its stacks with a Makefile on the host, and `python3-debian` because the repository module needs it |
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

And a step that pins a commit rather than a branch, so the hardening cannot change under you between
two runs of the same playbook. The repository is small, so re-cloning is simpler than reconciling an
existing checkout, and it leaves no stale state:

```make
SERVER_BASELINE_URL ?= https://github.com/dhis2-sre/server-baseline.git
SERVER_BASELINE_REF ?= <commit>

roles:
	rm -rf external/server-baseline
	git clone --quiet --no-checkout $(SERVER_BASELINE_URL) external/server-baseline
	git -C external/server-baseline checkout --quiet $(SERVER_BASELINE_REF)
	ansible-galaxy collection install --requirements-file external/server-baseline/requirements.yml
```

Both variables are overridable, and `git clone` takes a path as well as a URL, so trying a change
before pushing it needs no extra machinery:

```bash
make roles SERVER_BASELINE_URL=/path/to/server-baseline SERVER_BASELINE_REF=my-branch
```

`services/im-vm/ansible` in dhis2-infrastructure and `server-tools` in dhis2/docker-deployment are
working examples.

## Requirements

- `ansible-core`, plus the `ansible.posix` collection (see `requirements.yml`). `bootstrap` uses
  `authorized_key`, which core does not ship.
- Ubuntu 24.04 on the target.
- **Connect as a non-root account with sudo.** `harden` sets `PermitRootLogin no` and reloads sshd, so
  a playbook run as `root` succeeds and then locks itself out. Create the account before the first
  run, for example from cloud-init.

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
- **The SSH tasks validate with `sshd -t`**, which needs `/run/sshd` to exist. Every booted host has
  it, but a container or a chroot where sshd has never started does not, and the play fails there
  rather than writing a config it could not check.

## Known issues

- No Galaxy metadata (`meta/main.yml`), so `ansible-galaxy role install` is not an option. It also
  wants a license, which this repository has yet to declare.
- `var-naming[no-role-prefix]` is skipped in `.ansible-lint`. `docker_user`, `deploy_dir` and
  `allowed_ssh_users` are the interface consumers configure, so they keep their names; variables
  registered inside the roles do carry a role prefix.
