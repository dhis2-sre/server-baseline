# Changelog

All notable changes to the `sre.server` collection.

The collection follows [semantic versioning](https://semver.org). A breaking change to a role's
variables or to what it does to a host is a major version, so consumers pinning `v1.x` can take
patches without rereading their group_vars.

## Unreleased

This changes what `firewall` does to a host, so it ships as a major version.

### Changed

- `firewall` filters services running on the host, not only published container ports (#17). It
  manages ufw, denying incoming and routed traffic and opening only `firewall_allowed_ports` and
  `firewall_allowed_udp_ports`. **After upgrading, a host service on an unlisted port becomes
  unreachable, from containers on the same host as well.** The play refuses to run if the port it
  connects over is not listed.
- `firewall` purges `iptables-persistent` and `netfilter-persistent`, which Ubuntu's ufw package
  cannot be installed alongside. ufw restores the rules on boot instead, `DOCKER-USER` included.
- `DOCKER-USER` lets container traffic out by bridge interface (`firewall_docker_bridges`) instead
  of allowing the `172.16.0.0/12` source range, which also let in any client in that range. Listed
  ports RETURN to Docker's own rules instead of being accepted, so only published ports are reachable.
- Traffic routed through the host is denied by default and needs a `ufw route allow` rule. The old
  chain let routed traffic through to ports 22, 80 and 443 only because it matched those ports
  after address translation, so a WireGuard VPN forwarding its clients stops working on upgrade.
- Dropped container traffic is logged, rate limited, with the prefix `[DOCKER-USER BLOCK]`.
- The role no longer prints the rules at the end of a run. Use `ufw status` and
  `iptables --list DOCKER-USER`.
- The lockout check reads the port sshd accepted the connection on, so it also covers a port set in
  `~/.ssh/config`. Entries in the port lists that are not ports or ranges are rejected up front.

### Fixed

- `DOCKER-USER` matched `--dport`, which is the container's port by then, so `-p 443:8443` was
  blocked with 443 listed and `-p 8080:80` was open with 8080 unlisted. It now matches
  `--ctorigdstport`, the port the client connected to.
- Removing a port from the lists now closes it. Rules added by hand with `ufw allow` are left alone.
- `DOCKER-USER` is written for IPv6 as well as IPv4.
- A port added on a later run lands ahead of the default drop instead of after it (#4). The chain is
  rewritten in order from the lists on every run.


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
