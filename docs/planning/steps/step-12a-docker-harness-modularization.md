## Step 12 Follow-Up: Modularize Docker Harness Internals

Modularize the Docker harness for maintainability and as a clearer reference
for VM harness implementation. This follow-up is Docker-local cleanup; it is
not shared VM infrastructure and must not block Step 13.

Implementation notes:

- Keep `simulation/docker/simulate.sh` as the public Docker simulation CLI.
  Use it as a thin command dispatcher after modularization.
- Move Docker-specific implementation groups into `simulation/docker/lib/*.sh`.
  Candidate groups are config/run-state handling, Compose/container/mount
  helpers, loopback port and target SSH helpers, Docker artifact transfer and
  staging helpers, Docker evidence rendering, and command implementations when
  that reduces dispatcher size cleanly.
- Do not move Docker-specific code into `simulation/lib/`. Shared support
  remains limited to backend-neutral mechanics.
- Do not introduce a Docker/VM backend abstraction, shared dispatcher, or
  backend selection API.
- Preserve command names, terminal summaries, generated paths, evidence shape,
  run markers, cleanup behavior, and Docker simulation waivers.

Verification:

```bash
bash -n simulation/docker/simulate.sh simulation/docker/lib/*.sh simulation/lib/*.sh
tests/simulation-shared-library-test.sh
tests/docker-harness-terminal-summary-test.sh
tests/docker-harness-bootstrap-env-test.sh
tests/docker-harness-preflight-no-render-test.sh
tests/docker-harness-relative-env-paths-test.sh
tests/docker-harness-all-role-dispatch-test.sh
tests/docker-harness-artifact-export-test.sh
tests/docker-harness-integration-wiring-test.sh
tests/docker-harness-layout-test.sh
tests/account-docs-contract-test.sh
git diff --check
```

Acceptance criteria:

- Docker simulation command behavior and terminal summaries are unchanged.
- `simulation/docker/simulate.sh` is reduced to public CLI wiring and command
  dispatch where practical.
- Docker lifecycle, transport, mount, port, cleanup, evidence schema, and
  waiver behavior remain Docker-local.
- VM harness work can use the Docker modules as an implementation reference
  without depending on them.

