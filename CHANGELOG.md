# Changelog

All notable changes to the `sre.server` collection.

The collection follows [semantic versioning](https://semver.org). A breaking change to a role's
variables or to what it does to a host is a major version, so consumers pinning `v1.x` can take
patches without rereading their group_vars.

## 2.1.0

### Added

- `docker_user_groups` sets the supplementary groups `bootstrap` adds a dedicated `docker_user` to.
  It defaults to `[ sudo ]`, as before. A consumer that keeps the account out of `sudo` set it to
  `[]` instead of removing it again in its own play, which made both tasks report a change on every
  run.

## 2.0.0

These change what `firewall` and `harden` do to a host, so they ship as a major version.

### Added

- Ubuntu 26.04 (resolute) as a supported target alongside 24.04. The roles needed no changes, but a
  connecting account that needs a sudo password has to become with `sudo.ws` there, as the README
  describes (#14).

### Changed

- **Breaking:** `harden` moves sshd to the new `ssh_port`, 822 by default (#23). The port the play
  connected on stays open too, in sshd and in `firewall`, so set `ansible_port` to `ssh_port`, open
  it in any provider firewall and run again to close the old one. fail2ban's `sshd` jail bans on the
  same ports.
- `firewall` filters services running on the host, not only published container ports (#17). It
  manages ufw, denying incoming and routed traffic and opening only `firewall_allowed_ports` and
  `firewall_allowed_udp_ports`. **After upgrading, a host service on an unlisted port becomes
  unreachable, from containers on the same host as well.** It opens `ssh_port` and the port the play
  is connected on by itself, so `firewall_allowed_ports` defaults to `[ 80, 443 ]` and a list that
  still has 22 in it keeps 22 open after sshd has left it.
- `firewall` purges `iptables-persistent` and `netfilter-persistent`, which Ubuntu's ufw package
  cannot be installed alongside. ufw restores the rules on boot instead, `DOCKER-USER` included, and
  the drop of TCP packets that carry IPv4 header options moves to `/etc/ufw/before.init`, which ufw
  runs on boot and on every reload. The role owns that file and replaces it.
- `DOCKER-USER` lets container traffic out by bridge interface (`firewall_docker_bridges`) instead
  of allowing the `172.16.0.0/12` source range, which also let in any client in that range. Listed
  ports RETURN to Docker's own rules instead of being accepted, so only published ports are reachable.
- Traffic routed through the host is denied by default and needs a `ufw route allow` rule. The old
  chain let routed traffic through to ports 22, 80 and 443 only because it matched those ports
  after address translation, so a WireGuard VPN forwarding its clients stops working on upgrade.
- Dropped container traffic is logged, rate limited, with the prefix `[DOCKER-USER BLOCK]`.
- `harden` stops and masks `apport.service` where it exists. Ubuntu's crash reporter set
  `fs.suid_dumpable` back to 2 on every boot, over the 0 `harden` sets. The packages stay installed.
- ufw no longer applies `/etc/ufw/sysctl.conf` (`IPT_SYSCTL=` in `/etc/default/ufw`), which on every
  start and reload set `log_martians` back to 0 over `harden`'s kernel parameters.
- The role no longer prints the rules at the end of a run. Use `ufw status` and
  `iptables --list DOCKER-USER`.
- Entries in the port lists that are not ports or ranges are rejected up front.

### Fixed

- `DOCKER-USER` matched `--dport`, which is the container's port by then, so `-p 443:8443` was
  blocked with 443 listed and `-p 8080:80` was open with 8080 unlisted. It now matches
  `--ctorigdstport`, the port the client connected to.
- Removing a port from the lists now closes it. Rules added by hand with `ufw allow` are left alone.
- `DOCKER-USER` is written for IPv6 as well as IPv4.
- `harden` writes its kernel parameters to `/etc/sysctl.d/99-sre-server-hardening.conf` instead of
  `/etc/sysctl.conf`, which Ubuntu 26.04 no longer reads at boot, so there they were lost on every
  reboot. It removes them from `/etc/sysctl.conf`, which 24.04 still applies after the drop-in.

## 1.1.0

### Changed

- **Breaking:** `harden` sets `PermitRootLogin`, `PasswordAuthentication` and the new
  `KbdInteractiveAuthentication` to `no` in `/etc/ssh/sshd_config.d/00-hardening.conf` instead of in
  `sshd_config`, where any drop-in setting the same keyword, such as cloud-init's
  `50-cloud-init.conf` with `PasswordAuthentication yes`, silently overrode them. Hosts where that
  kept password logins working lose them. sshd is now reloaded on every run, and the role fails if
  `sshd -T` shows the settings are not in effect (#15).

### Fixed

- `firewall` inserts its allow rules at the top of `DOCKER-USER` instead of appending them, so a port
  added to `firewall_allowed_ports` or `firewall_allowed_udp_ports` on a later run lands ahead of the
  default drop rather than after it, where it never matched (#4).
- `bootstrap` refreshes the apt cache only when it is more than an hour old, instead of on every run,
  so a repeat run no longer reports its "Update apt cache" task as changed (#7).
- `harden` replaces an existing `/etc/subuid` or `/etc/subgid` entry for `docker_user` instead of
  adding a second one beside it. `useradd` writes an entry for each new user, and wherever its range
  was not `100000:65536` the role left the user with two ranges (#5).
- `harden` merges its Docker daemon settings (`userns-remap`, `icc`, `log-driver`, `log-opts`) into
  `/etc/docker/daemon.json` instead of replacing the file, so settings it does not manage, such as
  `data-root` or `registry-mirrors`, survive a run (#6). The hardening keys still win. Existing
  `log-opts` are kept when the driver was already `json-file`, and dropped otherwise, because
  dockerd will not start with options `json-file` does not know. A file that is not a JSON object
  now stops the role instead of being overwritten.
- `harden` no longer restarts fail2ban on every run. It ensures the service is enabled and running,
  and restarts it through a handler only when installing it changed something (#8).

### Changed

- The first run after upgrading rewrites `daemon.json` with sorted keys, so Docker restarts once on
  each host even where the settings are unchanged.

### Added

- `firewall` drops IPv4 TCP packets that carry IP header options, in the raw `PREROUTING` chain
  ahead of Docker's DNAT so it covers published container ports and the host's own listeners. No
  legitimate client sends them, and they trigger CVE-2026-98432, a remote use-after-free in the
  IPv4 TCP handshake with no fixed Ubuntu 24.04 kernel yet.
- `harden_docker_daemon_config`, the path the Docker daemon settings are merged into. It defaults
  to `/etc/docker/daemon.json` and exists for the tests.
- `tests/docker-daemon.yml`, run by `tests/run.sh`, which applies those tasks to a scratch file and
  checks the result. It is the suite's first test that applies anything.

## 1.0.1

### Fixed

- `harden` runs its AppArmor status probe with `check_mode: false`. The probe is a `command`, which
  ansible skips under `--check`, leaving the assert after it to read a registered result that has no
  `stdout` and fail.

## 1.0.0

First release as an Ansible collection. Everything before this was a plain roles repository that
consumers put on their `roles_path`.

### Added

- `sre.server.baseline`, a role that composes `bootstrap`, `firewall` and `harden` in that order.
- `playbooks/baseline.yml`, runnable as `ansible-playbook sre.server.baseline`.
- Galaxy metadata and an Apache-2.0 licence, so the roles carry a licence and could be published.
- `tests/run.sh`, which builds and installs the collection and syntax-checks the playbooks against
  the installed copy.

### Changed

- The roles are addressed as `sre.server.bootstrap`, `sre.server.firewall` and `sre.server.harden`
  once the collection is installed. Putting `roles/` on `roles_path` and using the bare names still
  works, so a consumer that already does that keeps working untouched.
- `harden` defaults `docker_user` itself instead of borrowing the default `bootstrap` happened to
  leave in scope, so it can be run without `bootstrap`.
- `deploy_dir` defaults to `/opt/deploy`. Nothing in the collection is specific to any one project
  any more, so a consumer that wants a different directory sets it explicitly.
