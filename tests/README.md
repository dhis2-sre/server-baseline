# tests

`run.sh` is the whole suite. It builds the collection, installs the tarball into a temporary
directory, and syntax-checks `playbooks/baseline.yml` and `individual-roles.yml` against the
installed copy:

```bash
tests/run.sh
```

It needs `ansible-core` and network access, since installing the collection also resolves the
`ansible.posix` dependency declared in `galaxy.yml`. CI runs it on every push and pull request.

It deliberately checks the things linting the working tree cannot:

- `galaxy.yml` is valid and the collection builds and installs.
- `sre.server.baseline` resolves, and so do the three roles it depends on. In the working tree every
  role also resolves by its bare directory name, so a wrong namespace goes unnoticed there.
- Each role still works on its own, not only as part of the baseline.

What it does not do is apply anything. Verifying the roles against a real host means provisioning a
clean Ubuntu 24.04 VM and running `playbooks/baseline.yml` at it; there is no VM in CI.
