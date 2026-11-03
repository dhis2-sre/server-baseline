# tests

`run.sh` is the whole suite. It builds the collection, installs the tarball into a temporary
directory, syntax-checks `playbooks/baseline.yml` and `individual-roles.yml` against the installed
copy, and runs `docker-daemon.yml`:

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

`docker-daemon.yml` is the one test that applies anything. It runs the `harden` role's
`daemon.json` tasks against a scratch file on the machine running the suite, through the installed
collection, and checks that the hardening keys are enforced, that every other key already in the
file survives, that a second run changes nothing, and that a file that is not a JSON object stops
the role and is left alone. It needs no root, never touches `/etc/docker/daemon.json`, and ends its
play before the `Restart docker` handler it triggers can run.

Nothing else is applied. Verifying the roles against a real host means provisioning a clean Ubuntu
24.04 VM and running `playbooks/baseline.yml` at it; there is no VM in CI.
