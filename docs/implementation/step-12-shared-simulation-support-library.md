## Step 12: Extract Shared Simulation Support Library

Extract backend-neutral simulation support before adding real VM behavior.
This step implements the accepted shared-library direction without creating a
generic Docker/VM backend abstraction.

Create shared support under `simulation/lib/` for common mechanics that are
already proven by Docker simulation and needed by VM simulation:

- command summaries, failures, timestamps, and quoting helpers;
- role names, role parsing, and role-to-helper mapping;
- env loading, repo-relative path resolution, and runtime input custody;
- generated run markers and lifecycle marker helpers;
- artifact bundle naming, manifest parsing, checksum validation, and staged
  artifact checks;
- evidence writing helpers and bounded log path helpers.

Implementation notes:

- Keep `simulation/docker/simulate.sh` and `simulation/vm/simulate.sh` as the
  public CLIs. Do not replace them with a backend-dispatching entrypoint.
- Move only backend-neutral code into `simulation/lib/`. Docker-specific
  Compose selection, container lifecycle, bind-mount validation, `docker cp`
  waivers, loopback ports, target SSH staging, and cleanup stay in the Docker
  harness.
- Update Docker simulation to source the shared helpers with no behavior
  change. Existing Docker tests must continue to pass.
- Do not introduce an abstract backend API in this step. Promote a backend
  boundary only later if repeated real VM code proves that interface.

Verification:

```bash
bash -n simulation/docker/simulate.sh simulation/lib/*.sh
simulation/docker/simulate.sh --help
simulation/docker/simulate.sh preflight
tests/account-docs-contract-test.sh
git diff --check
```

Acceptance criteria:

- Docker simulation command behavior and terminal summaries are unchanged.
- Shared helpers contain only backend-neutral support code.
- Docker lifecycle, transport, mount, port, and cleanup behavior remains
  Docker-local.
- The repository has a clear support-library base for the VM harness.

