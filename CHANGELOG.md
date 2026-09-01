# Changelog

All notable changes to the `dhis2.sre` collection.

The collection follows [semantic versioning](https://semver.org). A breaking change to a role's
variables or to what it does to a host is a major version, so consumers pinning `v1.x` can take
patches without rereading their group_vars.

## 1.0.0

First release as an Ansible collection. Everything before this was a plain roles repository that
consumers put on their `roles_path`.

### Added

- `dhis2.sre.baseline`, a role that composes `bootstrap`, `firewall` and `harden` in that order.
- `playbooks/baseline.yml`, runnable as `ansible-playbook dhis2.sre.baseline`.
- Galaxy metadata and an Apache-2.0 licence, so the roles carry a licence and could be published.
- `tests/run.sh`, which builds and installs the collection and syntax-checks the playbooks against
  the installed copy.

### Changed

- The roles are addressed as `dhis2.sre.bootstrap`, `dhis2.sre.firewall` and `dhis2.sre.harden`
  once the collection is installed. Putting `roles/` on `roles_path` and using the bare names still
  works, which is how `dhis2-infrastructure` consumes them.
- `harden` defaults `docker_user` itself instead of borrowing the default `bootstrap` happened to
  leave in scope, so it can be run without `bootstrap`.
