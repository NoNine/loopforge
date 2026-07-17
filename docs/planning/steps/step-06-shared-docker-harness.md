## Step 6: Add Shared Docker Harness

Create the reusable Docker harness used by the Gerrit, Jenkins controller, and
Jenkins agent helper readiness gates. This harness provides real containers for
role-step validation, but it is not the full end-to-end Docker simulation.

Create:

- `simulation/docker/simulate.sh`
- Docker Compose assets under `simulation/docker/`
- Docker env examples under `simulation/docker/examples/`
- Harness state, staging, evidence, and bounded-log directories documented as
  generated local output

Harness environments:

| Environment | Responsibility |
| --- | --- |
| Bundle factory | Runs role helper `prepare-artifacts` commands and produces artifact bundles, manifests, and checksums. |
| LDAP | Provides bind, admin, integration, and test directory data for role gates. |
| Gerrit target | Runs Gerrit helper install, configure, and validation commands against staged artifacts. Gerrit cross-role integration is outside the role helper and is not run during role gates. |
| Jenkins controller target | Runs Jenkins helper install, plugin, JCasC, and validation commands against staged artifacts. Credential, integration, node, and job command surfaces belong to the shared integration helper and are not run during role gates. |
| Jenkins agent target | Runs Jenkins agent helper install, runtime SSH setup, and validation commands against staged artifacts. |

Harness implementation decisions:

- Use a boundary-first target model. The Gerrit, Jenkins controller, and
  Jenkins agent targets are host-like target containers, not prebuilt
  Gerrit/Jenkins service images with embedded application artifacts.
- Use `docs/baselines/version-baseline.md` for the bundle factory, Gerrit target,
  Jenkins controller target, and Jenkins agent target. Docker image tags may
  represent the reviewed Ubuntu baseline only when the harness records the
  resolved image digest or OS release evidence.
- Use a real LDAP service image for the LDAP environment so LDAP reachability
  and seeded directory assumptions can be checked by later role gates.
- Do not use `gerritcodereview/gerrit` or `jenkins/jenkins` as Step 6 target
  containers, because their embedded WARs would weaken the v1 artifact
  boundary. Gerrit and Jenkins application artifacts must still be prepared in
  the bundle factory, staged to targets, and verified before target mutation.
- If Docker Compose v2 is unavailable but `docker-compose` v1 is available, the
  Step 6 harness may use `docker-compose`. The command implementation should
  detect and report the Compose command it will use.
- Existing generated `generated/simulation/docker/<run-id>/` content is not
  source material. Treat the run-scoped `host/` and `target/` children as
  generated output and do not commit retained state or verbose logs.
- Harness evidence must record the Version Baseline values used by the run and
  must not report comparable readiness when container OS or artifact versions
  drift from that baseline.

Expected command surface:

```text
simulation/docker/simulate.sh preflight
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh start
simulation/docker/simulate.sh status
simulation/docker/simulate.sh prepare-artifacts --role gerrit
simulation/docker/simulate.sh prepare-artifacts --role jenkins-controller
simulation/docker/simulate.sh prepare-artifacts --role jenkins-agent
simulation/docker/simulate.sh stage-artifacts --role gerrit
simulation/docker/simulate.sh stage-artifacts --role jenkins-controller
simulation/docker/simulate.sh stage-artifacts --role jenkins-agent
simulation/docker/simulate.sh configure-role --role gerrit
simulation/docker/simulate.sh validate-role --role gerrit
simulation/docker/simulate.sh configure-role --role jenkins-controller
simulation/docker/simulate.sh validate-role --role jenkins-controller
simulation/docker/simulate.sh configure-role --role jenkins-agent
simulation/docker/simulate.sh validate-role --role jenkins-agent
simulation/docker/simulate.sh stop
```

Implementation notes:

- The harness must not add `bundle-factory-helper.sh` or any bundle factory
  public API. It runs the role helpers' `prepare-artifacts` commands in the
  bundle factory container.
- Add ignore rules for generated harness state and log directories before
  creating runtime output.
- Create only source assets under `simulation/docker/`; generated state,
  staged artifacts, evidence, and bounded logs must be written under generated
  paths.
- `prepare-artifacts --role ...` must run only in the bundle factory
  environment and must fail if invoked against a target container. Terminal
  output should stay short and role-scoped.
- `stage-artifacts --role ...` copies bundle factory output to the selected
  target container and verifies target-side manifests and checksums before
  any install or configuration command can run. Terminal output should stay
  short and role-scoped.
- `configure-role --role ...` runs role-local installation and configuration.
  `validate-role --role ...` runs the role helper readiness validation in the
  corresponding target container. It must fail on dummy success,
  `planned-checks-only`, operation-plan-only success, or modeled proof for
  required runtime checks. Terminal output should stay short and role-scoped.
- Because this step precedes the role helpers, harness verification checks the
  harness infrastructure, command surface, role validation, and missing-helper
  failure behavior. Steps 7, 8, and 9 run the role-specific gates after each
  helper exists.
- The harness may share Docker networks, volumes, images, and env rendering
  with the full Docker simulation, but full Gerrit Trigger end-to-end
  verification remains in the later Docker simulation step.
- Docker, Compose, package-manager, Gerrit, Jenkins, SSH, and verification
  logs must be redirected to timestamped bounded log files and referenced from
  evidence summaries.
- Any public internet fallback in the harness is simulation-only and must be
  labeled `simulation-only` in logs and evidence.
- Generated local state must be ignored or clearly documented as generated.

Verification:

```bash
bash -n simulation/docker/simulate.sh
simulation/docker/simulate.sh --help
simulation/docker/simulate.sh preflight
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh start
! simulation/docker/simulate.sh prepare-artifacts --role unknown
! simulation/docker/simulate.sh configure-role --role gerrit
! simulation/docker/simulate.sh validate-role --role gerrit
simulation/docker/simulate.sh stop
rg -n "dummy success|operation-plan-only|planned-checks-only|modeled" docs/planning/implementation-plan.md
rg -n "bundle-factory-helper|prepare-offline-deps|install-offline-deps" simulation/docker docs scripts templates examples
```

Acceptance criteria:

- The harness starts the five environments needed by role-helper gates.
- Before role helpers exist, role-specific harness commands fail nonzero with
  clear missing-helper or unknown-role messages instead of reporting success.
- Artifact bundles are produced only in the bundle factory environment.
- Staged artifacts are verified by manifest and checksum in target
  environments before mutation.
- Role-gate wrappers fail on dummy, placeholder, operation-plan-only, or
  modeled success for required runtime checks.
- Harness evidence includes mode labels, checksum references, role names,
  container names, and bounded log references.
- The harness is reusable by the Gerrit, Jenkins controller, Jenkins agent,
  and full Docker simulation steps.
- No supported offline Ubuntu dependency bundle workflow is introduced.
