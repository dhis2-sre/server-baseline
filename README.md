# server-baseline

`sre.server`, an Ansible collection that turns a stock Ubuntu 24.04 or 26.04 host into a hardened
Docker host.

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
| `sre.server.firewall` | Default deny ufw for services on the host, and a default deny `DOCKER-USER` chain for published container ports, both opening only the ports you list, plus a drop of TCP packets that carry IPv4 header options |
| `sre.server.harden` | SSH, kernel, AppArmor, fail2ban and Docker daemon hardening, including user namespace remapping |
| `sre.server.baseline` | All three of the above, in that order. No tasks of its own |

The order matters: `bootstrap` installs the Docker Engine, `firewall` locks down the host and the
`DOCKER-USER` chain that installing it creates, and `harden` reconfigures the daemon and the host
around both.

`firewall` filters two paths. Services on the host are reached through the `INPUT` chain, which ufw
manages. Published container ports bypass `INPUT`, because Docker rewrites their destination and
forwards them, so the role also writes a `DOCKER-USER` chain into ufw's `after.rules`, which ufw
restores on boot and on every reload. The drop of TCP packets that carry IPv4 header options sits in
the raw table, ahead of Docker's address translation, and is applied by `/etc/ufw/before.init`,
which the role owns. Do not add another firewall frontend or `iptables-persistent`, which Ubuntu's
ufw package cannot be installed alongside.

## Consuming it

Declare the collection in your project's `requirements.yml`, pinned to a tag:

```yaml
collections:
  - name: https://github.com/dhis2-sre/server-baseline.git
    type: git
    version: v1.0.0
```

Install it, and the `ansible.posix` and `community.general` dependencies it declares come with it:

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

That route does not resolve `ansible.posix` or `community.general`, so install `requirements.yml`
alongside it.

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
| `ssh_port` | `822` | harden, firewall | Port sshd listens on, and `firewall` opens it on its own. Keep it below 1024, so only root can bind it |
| `firewall_allowed_ports` | `[ 80, 443 ]` | firewall | TCP ports reachable from outside, both for services on the host and for published container ports. Leave SSH out: `firewall` opens `ssh_port`, and the port the play is connected on, by itself |
| `firewall_allowed_udp_ports` | `[ 51820 ]` | firewall | UDP ports, opened the same way. 51820 is WireGuard |
| `firewall_docker_bridges` | `[ docker0, br-+ ]` | firewall | Bridges containers sit on. Traffic leaving them is allowed, so containers reach the internet and each other. Add any network named with `com.docker.network.bridge.name`, or its containers can reach only listed ports |

The port lists match the port a client connects to on the host, so a container published as
`-p 443:8443` is opened by listing `443`. Removing a port from a list closes it on the next run. Rules
added by hand with `ufw allow` are not touched, because the role only removes rules it tagged itself,
but a hand added rule for a port you then list is tagged too, and closes when the port leaves the list.

Traffic routed through the host rather than to it, such as a WireGuard VPN forwarding its clients,
is denied by default. Allow it with `ufw route allow`, for example `ufw route allow in on wg0`.

### Before you remove port 80

With a default deny firewall, the port lists are the only thing deciding what is reachable, so make
closing 80 a deliberate choice:

- **HTTP-01 needs port 80.** Let's Encrypt validates the HTTP-01 challenge by connecting to port 80
  on the domain, and it cannot be moved to another port. This is Traefik's `httpChallenge` and
  certbot's `--webroot` and `--standalone` modes.
- **Renewals fail weeks later, not at once.** Closing 80 on a host that already has certificates
  breaks nothing immediately. The next renewal fails, and the site goes down when the current
  certificate expires, long after anyone connects it with the firewall change.
- **Alternatives without port 80:** TLS-ALPN-01 validates over 443 (Traefik's `tlsChallenge`), and
  DNS-01 needs no inbound port at all and is the only challenge that issues wildcard certificates, at
  the cost of DNS provider API credentials on the host.
- **No HTTP to HTTPS redirect.** A visitor who types `http://` gets a refused connection instead of a
  redirect. HSTS covers only returning visitors and preloaded domains.

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

- `ansible-core` 2.15 or newer on the control machine, plus the `ansible.posix` and
  `community.general` collections.
  Installing this collection pulls them in; a `roles_path` checkout has to install `requirements.yml`.
- Ubuntu 24.04 (noble) or 26.04 (resolute) on the target.
- **Connect as a non-root account with sudo.** `harden` sets `PermitRootLogin no` and reloads sshd, so
  a playbook run as `root` succeeds and then locks itself out. Create the account before the first
  run, for example from cloud-init.
- **On Ubuntu 26.04, become with `sudo.ws` if that account needs a sudo password.** 26.04 makes
  sudo-rs the default `sudo`, and sudo-rs wraps the prompt Ansible passes with `-p`, so Ansible never
  recognises it and every `become` task times out waiting for the privilege escalation prompt.
  Classic sudo is still installed as `/usr/bin/sudo.ws`. Set `ansible_become_exe: sudo.ws` for those
  hosts in your inventory or `group_vars`. This happens before any role runs, so the collection
  cannot work around it itself. Passwordless sudo is not affected.

## Things to know before you run this

- **User namespace remapping breaks containers that need the Docker socket.** The container's root
  maps to an unprivileged host uid, which cannot read `/var/run/docker.sock`. Traefik's Docker
  provider is the common casualty; use its file provider, or `userns_mode: host` for that one
  container if you accept handing it root equivalent access.
- **Bind mounted directories need to be world readable** for the same reason, or the remapped
  container uid cannot traverse them.
- **`/tmp` is mounted `noexec`.** Installers that unpack to `/tmp` and execute from there fail. Use
  `/usr/local/src` or similar.
- **Containers reach services on the host through ufw too.** A container connecting to the host,
  through `host.docker.internal`, the bridge gateway or the host's own address, is filtered like any
  other client, so only listed ports answer. Open a port to containers alone with a rule such as
  `ufw allow from 172.16.0.0/12 to any port 9100 proto tcp`. Docker allocates networks from
  `172.16.0.0/12` and, once that runs out, from `192.168.0.0/16`, so a host with many networks may
  need a second rule. The role leaves rules added by hand alone.
- **IPv6 is disabled** by the sysctl list. Override those two keys if you publish AAAA records.
- **`icc: false`** applies to the default bridge only. Containers on user defined networks, which is
  what compose creates, still reach each other.
- **The SSH tasks validate with `sshd -t`**, which needs `/run/sshd` to exist. Every booted host has
  it, but a container or a chroot where sshd has never started does not, and the play fails there
  rather than writing a config it could not check.
- **`PermitRootLogin`, `PasswordAuthentication` and `KbdInteractiveAuthentication` are set in
  `/etc/ssh/sshd_config.d/00-hardening.conf`**, which sorts ahead of the drop-ins Ubuntu and
  cloud-init ship, and `harden` fails if `sshd -T` shows any of them is not `no`. Password logins
  over SSH stop working even where a provider's cloud-init had kept them on, so connect with a key,
  including from your Ansible inventory. A `Match` block, in `sshd_config` or a drop-in, can still
  re-enable passwords for the connections it matches; the check reads the global settings only.
- **sshd moves to `ssh_port`, 822 by default, over two runs.** The first keeps the port it connected
  on open as well. Open `ssh_port` in any provider firewall and set `ansible_port` to it, and the
  second run closes the old port. Any other `Port` line in `sshd_config` or a drop-in fails the run.

## Development

`tests/run.sh` builds the collection, installs it into a temporary directory, syntax-checks the
playbooks against the installed copy, and runs the one behaviour test there is, for how `harden`
writes `daemon.json`. See [tests/README.md](tests/README.md) for what that does and does not prove. Lint with the same hooks CI runs:

```bash
pre-commit run --all-files
```

## Known issues

- The collection is not published to the Ansible Galaxy hub. Consumers install it from the git tag,
  which is what the `requirements.yml` above does.
- `var-naming[no-role-prefix]` is skipped in `.ansible-lint`. `docker_user`, `deploy_dir` and
  `allowed_ssh_users` are the interface consumers configure, so they keep their names; variables
  registered inside the roles do carry a role prefix.
- Nothing applies the roles to a real host in CI. Apart from the `daemon.json` test, `tests/run.sh`
  stops at a syntax check, so verifying a change against clean Ubuntu 24.04 and 26.04 VMs is still
  manual.
