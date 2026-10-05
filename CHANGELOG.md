# Changelog

All notable changes to the `sre.server` collection.

The collection follows [semantic versioning](https://semver.org). A breaking change to a role's
variables or to what it does to a host is a major version, so consumers pinning `v1.x` can take
patches without rereading their group_vars.

## Unreleased

### Fixed

- `harden` merges its Docker daemon settings (`userns-remap`, `icc`, `log-driver`, `log-opts`) into
  `/etc/docker/daemon.json` instead of replacing the file, so settings it does not manage, such as
  `data-root` or `registry-mirrors`, survive a run (#6). The hardening keys still win. Existing
  `log-opts` are kept when the driver was already `json-file`, and dropped otherwise, because
  dockerd will not start with options `json-file` does not know. A file that is not a JSON object
  now stops the role instead of being overwritten.

### Changed

- The first run after upgrading rewrites `daemon.json` with sorted keys, so Docker restarts once on
  each host even where the settings are unchanged.

### Added

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
