# Changelog

All notable changes to the `sre.server` collection.

The collection follows [semantic versioning](https://semver.org). A breaking change to a role's
variables or to what it does to a host is a major version, so consumers pinning `v1.x` can take
patches without rereading their group_vars.

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
