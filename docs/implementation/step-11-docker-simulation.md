## Step 11: Build Docker Simulation

Use the Docker simulation behavior summarized in `docs/references/reference-digest.md`.

Create Docker simulation assets under `simulation/docker/` for:

- Bundle factory service that runs role helper `prepare-artifacts` commands and
  produces role artifact directories, manifests, and checksums.
- LDAP service with seeded bind/admin/test users.
- Gerrit service configured for LDAP and `Verified` voting.
- Jenkins controller configured with LDAP, JCasC, plugins, and Gerrit Trigger.
- Jenkins SSH agent service.
- Full verification wrapper.

Expected command surface:

```text
simulation/docker/simulate.sh [--env FILE] preflight
simulation/docker/simulate.sh [--env FILE] init-run
simulation/docker/simulate.sh [--env FILE] status
simulation/docker/simulate.sh [--env FILE] prepare-artifacts
simulation/docker/simulate.sh [--env FILE] stage-artifacts
simulation/docker/simulate.sh [--env FILE] up
simulation/docker/simulate.sh [--env FILE] configure-role
simulation/docker/simulate.sh [--env FILE] validate-role
simulation/docker/simulate.sh [--env FILE] configure-integration
simulation/docker/simulate.sh [--env FILE] validate-integration
simulation/docker/simulate.sh [--env FILE] prove-integration
simulation/docker/simulate.sh [--env FILE] audit-state
simulation/docker/simulate.sh [--env FILE] down
simulation/docker/simulate.sh [--env FILE] clean
```

Implementation notes:

- Docker simulation reuses the shared Docker harness and the functional role
  helpers from Steps 7, 8, and 9.
- Docker simulation must call role helpers only for role-local lifecycle:
  artifact preparation, install/configuration, role validation, and role-local
  evidence.
- Docker simulation must call `scripts/integration-setup.sh` for cross-role
  Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, Gerrit Trigger configuration,
  integration validation, trigger verification, and integration evidence.
- Docker simulation must use the Version Baseline for rendered inputs, prepared
  artifacts, staged artifacts, role helpers, and final evidence.
- Docker simulation bootstraps all lifecycle commands from the harness env file
  so `HARNESS_RUN_ID` and `HARNESS_PROJECT_NAME` do not depend on shell exports.
- Docker simulation is the first full end-to-end integration gate for Gerrit
  Trigger behavior, Jenkins agent scheduling, and `Verified` voting.
- `simulate.sh prepare-artifacts` runs role helper
  `prepare-artifacts` commands inside the bundle factory container. Do not add
  a `bundle-factory-helper.sh`.
- `simulate.sh stage-artifacts` stages prepared role artifacts from bundle
  factory output to the Gerrit, Jenkins controller, and Jenkins agent
  containers, then verifies manifests and checksums on the target side before
  service mutation.
- `simulate.sh validate-integration` is an independently repeatable passive
  readiness phase before `simulate.sh prove-integration`; `prove-integration`
  must require the successful validation marker and must not run
  `validate-integration` implicitly.
- `simulate.sh validate-integration` must invoke `scripts/integration-setup.sh
  validate-integration` for cross-role readiness once the real implementation
  exists, and must report blocked rather than success while the shared
  integration helper is scaffold-only.
- Docker verification must use the Step 10 evidence model for mode labels,
  checksums, and bounded log references.
- Docker verification must fail or report blocked rather than claim comparable
  verification when the run does not match the Version Baseline.
- Docker verification must fail if any consumed role or integration command reports dummy
  success, operation-plan-only success, `planned-checks-only`, modeled
  stream-events, modeled agent scheduling, modeled `Verified` voting, or a
  successful full verification summary without runtime proof from the real
  Gerrit, Jenkins controller, and Jenkins agent services.
- `simulate.sh audit-state` is the explicit read-only command for the
  expensive container and bind-mount sweep. Normal lifecycle phases use the
  cheap runtime-config checks only and do not rerun other phases implicitly.
- Docker logs must be written to bounded log files, not streamed verbosely into
  normal operator output.
- Any internet use during Docker artifact preparation or fallback must be
  labeled simulation-only.
- Generated local state must be ignored or clearly documented as generated.

Verification:

```bash
bash -n simulation/docker/simulate.sh
simulation/docker/simulate.sh --help
simulation/docker/simulate.sh preflight
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh status
simulation/docker/simulate.sh prepare-artifacts
simulation/docker/simulate.sh stage-artifacts
simulation/docker/simulate.sh up
simulation/docker/simulate.sh configure-role
simulation/docker/simulate.sh validate-role
simulation/docker/simulate.sh configure-integration
simulation/docker/simulate.sh validate-integration
simulation/docker/simulate.sh prove-integration
```

Acceptance criteria:

- Docker simulation starts all five machines, including the bundle factory
  container.
- Prepared artifacts, manifests, and checksums are produced by the bundle
  factory and verified after staging to service containers.
- Docker simulation uses the role helpers' functional install, configuration,
  validation, and role-local evidence commands, then uses
  `scripts/integration-setup.sh` for cross-role integration, agent scheduling,
  integration verification, and integration evidence instead of reimplementing or
  modeling that behavior inside `simulate.sh`.
- LDAP, local OS runtime account, Gerrit HTTP/SSH, Jenkins HTTP/LDAP/JCasC/plugin,
  Jenkins-to-Gerrit SSH, stream-events, and Jenkins agent readiness checks pass
  with separate evidence.
- `prove-integration` separately proves Gerrit event receipt, Jenkins job
  scheduling, agent execution, and Gerrit `Verified +1` vote posting.
- Verification writes a summary that labels the mode as Docker simulation.
- A successful `prove-integration` summary does not use modeled pass results for
  required runtime outcomes and must include proof from the real Gerrit,
  Jenkins controller, and Jenkins agent services.

