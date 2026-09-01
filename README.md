# server-baseline

`sre.server`, an Ansible collection that turns a stock Ubuntu 24.04 host into a hardened Docker host.

It exists so that the projects deploying onto those hosts do not each carry their own copy of the
same provisioning. They depend on a pinned version of this collection, apply the baseline, and are
left with only the part that is actually theirs.

```text
                       sre.server
          bootstrap  ->  firewall  ->  harden
                            |
                         baseline
              /             |             \
        project A       project B       project C
      its own roles   its own roles   its own roles
```

Nothing in here knows what you deploy on top of it. Fork it, point `galaxy.yml` at your own
namespace, and the same applies.

## Roles

| Role | What it does |
|---|---|
| `sre.server.bootstrap` | Base packages, Docker Engine and the compose plugin from Docker's apt repository, the operator account, and `deploy_dir` |
| `sre.server.firewall` | Default deny `DOCKER-USER` chain, allowing only the ports you list plus inter-container traffic, persisted with `netfilter-persistent` |
| `sre.server.harden` | SSH, kernel, AppArmor, fail2ban and Docker daemon hardening, including user namespace remapping |
| `sre.server.baseline` | All three of the above, in that order. No tasks of its own |

The order matters: `bootstrap` installs the Docker Engine, `firewall` locks down the `DOCKER-USER`
chain that installing it creates, and `harden` reconfigures the daemon and the host around both.

`firewall` exists because Docker bypasses the host's `INPUT` chain for published container ports, so
host level rules never see that traffic. Do not put UFW or another frontend alongside it.

## Consuming it

Declare the collection in your project's `requirements.yml`, pinned to a tag:

```yaml
collections:
  - name: https://github.com/dhis2-sre/server-baseline.git
    type: git
    version: v1.0.0
```

Install it, and the `ansible.posix` dependency it declares comes with it:

```bash
ansible-galaxy collection install --requirements-file requirements.yml
```

Then put the baseline in front of whatever your project does to the host, in one play, so a
provision is one run rather than two:

```yaml
- name: Provision and deploy
  hosts: all
  become: true

  roles:
    - sre.server.baseline
    - deploy
```

For a host with nothing project specific on it, the collection ships the play above without the
second role, addressable by name:

```bash
ansible-playbook --inventory inventory.ini sre.server.baseline
```

### Taking only part of it

The roles are independent, so a project that wants the firewall but manages its own Docker
installation can say so:

```yaml
  roles:
    - sre.server.firewall
    - sre.server.harden
```

Both `bootstrap` and `harden` default `docker_user` to the inventory `ansible_user`, so they agree
whether they run together or separately.

### Without installing the collection

`galaxy.yml` and `roles/` both sit at the repository root, so a pinned checkout on `roles_path`
still works and the roles keep their bare names there. Only `sre.server.baseline` needs the
collection installed, because it names its dependencies by their fully qualified names.

```ini
[defaults]
roles_path = ./roles:./external/server-baseline/roles
```

That route does not resolve `ansible.posix`, so install `requirements.yml` alongside it.

## Variables

Every variable has a default. Override in `group_vars/all.yml`.

| Variable | Default | Role | Purpose |
|---|---|---|---|
| `docker_user` | inventory `ansible_user` | bootstrap, harden | Owns `deploy_dir` and is the user namespace remap target. Set it to a dedicated account to have one created |
| `docker_user_password` | none | bootstrap | Pre-hashed, required only when `docker_user` is a dedicated account. `!` locks the password, which is what a service account wants |
| `docker_user_ssh_key` | none | bootstrap | Optional public key for a dedicated operator account |
| `deploy_dir` | `/opt/deploy` | bootstrap | Directory owned by `docker_user`. Point it wherever your project expects its checkout |
| `bootstrap_packages` | see defaults | bootstrap | Base packages. Includes `make` because one consumer drives its compose stacks with a Makefile on the host, and `python3-debian` because the repository module needs it |
| `allowed_ssh_users` | `[ ubuntu ]` | harden | SSH `AllowUsers`. `docker_user` is appended automatically |
| `firewall_allowed_ports` | `[ 22, 80, 443 ]` | firewall | Host facing TCP ports |
| `firewall_allowed_udp_ports` | `[ 51820 ]` | firewall | Host facing UDP ports. 51820 is WireGuard |

Operators are deliberately **not** added to the root equivalent `docker` group. Give them a scoped
`sudo` rule for the command they need instead.

## Versioning

The collection is versioned independently of anything consuming it, following semantic versioning,
and every release is tagged `vX.Y.Z`. A change to what a role does to a host, or to the variables it
reads, is a major version, so a consumer pinned to `v1.x` can take a patch without rereading its
`group_vars`. See [CHANGELOG.md](CHANGELOG.md).

**Pin a tag, not a branch.** An unpinned `main` means the hardening applied to production can change
between two runs of the same playbook, without anything in the consuming repository changing.

To cut a release: bump `version` in `galaxy.yml`, write the `CHANGELOG.md` entry, merge, then tag
the merge commit `vX.Y.Z` and push the tag. CI refuses a tag that disagrees with `galaxy.yml`, then
builds the collection and attaches the tarball to a GitHub release.

## Requirements

- `ansible-core` 2.15 or newer on the control machine, plus the `ansible.posix` collection.
  Installing this collection pulls it in; a `roles_path` checkout has to install `requirements.yml`.
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

## Development

`tests/run.sh` builds the collection, installs it into a temporary directory, and syntax-checks the
playbooks against the installed copy. See [tests/README.md](tests/README.md) for what that does and
does not prove. Lint with the same hooks CI runs:

```bash
pre-commit run --all-files
```

## Known issues

- The collection is not published to the Ansible Galaxy hub. Consumers install it from the git tag,
  which is what the `requirements.yml` above does.
- `var-naming[no-role-prefix]` is skipped in `.ansible-lint`. `docker_user`, `deploy_dir` and
  `allowed_ssh_users` are the interface consumers configure, so they keep their names; variables
  registered inside the roles do carry a role prefix.
- Nothing applies the roles to a real host in CI. `tests/run.sh` stops at a syntax check, so
  verifying a change against a clean Ubuntu 24.04 VM is still manual.
