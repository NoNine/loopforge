# Gerrit/Jenkins Setup Package Implementation Plan

## Purpose

This document defines the implementation plan for building the v1
Gerrit/Jenkins setup package described in `docs/prd.md`.

The source reference is `/home/ubuntu/ai-assisted/gerrit-jenkins`. That
reference contains useful manuals, helper scripts, Docker lab assets, and VM
verification assets, but it is framed around air-gapped installation. This
package must adapt those materials to the v1 boundary:

- v1 is not a strict air-gapped installer.
- v1 does not support offline Ubuntu dependency bundles.
- Public internet fallback on target hosts is simulation-only and must be
  labeled that way in docs, logs, and verification summaries.

The implementation should proceed in verifiable steps. Each step below must
leave the repository in a reviewable state and include a direct verification
command or checklist.

## Step 1: Establish The Repository Structure

Create the package layout before porting behavior. Keep manuals, templates,
helpers, simulations, examples, and logs separated so future changes have
clear ownership.

Planned structure:

```text
docs/
  prd.md
  implementation-plan.md
  account-model.md
  gerrit-user-manual.md
  jenkins-controller-manual.md
  jenkins-agent-manual.md
  gerrit-trigger-integration.md
  validation-and-evidence.md
examples/
  gerrit.env.example
  jenkins-controller.env.example
  jenkins-agent.env.example
scripts/
  common.sh
  gerrit-helper.sh
  jenkins-controller-helper.sh
  jenkins-agent-helper.sh
  collect-evidence.sh
templates/
  gerrit/
  jenkins-controller/
  jenkins-agent/
simulation/
  docker/
  vm/
logs/
```

Implementation notes:

- `docs/` contains the operator-facing manuals and design references.
- `examples/` contains reviewed env-file examples with placeholder values.
- `scripts/` contains helper commands that match manual phases.
- `templates/` contains service config, JCasC, job, and integration templates.
- `simulation/docker/` contains the first executable simulation model.
- `simulation/vm/` contains the later production-like verification model.
- `logs/` is used for local command logs and should not store committed
  verbose runtime output.

Verification:

```bash
find docs examples scripts templates simulation -maxdepth 3 -type d | sort
find docs examples scripts templates simulation -maxdepth 3 -type f | sort
rg -n "air-gapped|offline-bundle" docs examples scripts templates simulation
```

Acceptance criteria:

- The directory layout exists and matches the structure above unless a later
  implementation note explicitly justifies a small naming change.
- Any `air-gapped` or `offline-bundle` match is reference-only, non-goal, or
  prohibition text; no supported v1 command or path uses those terms.
- `logs/` exists or is documented as a generated runtime directory.

## Step 2: Define The Account Model

Start with the reference identity model:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/docs/gerrit-jenkins-identity-model.md
```

Create `docs/account-model.md` with the v1 account model. Use `identity`
only when discussing LDAP-backed identity integration; use `account` for
concrete roles.

Product accounts:

| Account | Source | Purpose |
| --- | --- | --- |
| Gerrit runtime account | Local OS | Runs Gerrit only. |
| Jenkins runtime account | Local OS | Runs the Jenkins controller only. |
| Jenkins agent runtime account | Local OS | Runs SSH build-agent sessions only. |
| Gerrit admin account | LDAP-backed human account or group | Administers Gerrit. |
| Jenkins admin account | LDAP-backed human account or group | Administers Jenkins. |
| Jenkins Gerrit integration account | Gerrit service account | Lets Jenkins authenticate to Gerrit, stream events, and vote `Verified`. |
| Test user account | LDAP-backed human-style test account | Verifies login and change workflow. |
| LDAP bind account | LDAP service account | Lets Gerrit and Jenkins search the directory read-only. |

Simulation environment account:

| Account | Source | Purpose |
| --- | --- | --- |
| `operator` account | Local OS account on simulation machines | Runs orchestration, SSH access, helper commands, and evidence collection. |

Implementation notes:

- Preserve the separation between runtime, human admin, integration, test, bind,
  and simulation environment accounts.
- State that human admin and test accounts are LDAP-backed, runtime accounts are
  local OS accounts by default, LDAP bind accounts are read-only LDAP service
  accounts, and the Jenkins Gerrit integration account is a Gerrit service
  account.
- State that the `operator` account is not a Gerrit/Jenkins runtime, admin,
  integration, bind, or test account.
- Keep examples account-name neutral where possible.
- Avoid describing runtime OS accounts as the same thing as application admin
  accounts.

Verification:

```bash
rg -n "runtime|admin|integration|test user|LDAP|bind" docs/account-model.md
rg -n "air-gapped|offline bundle|offline-bundle" docs/account-model.md
```

Acceptance criteria:

- Each product and simulation environment account has a defined source and
  purpose.
- The document explains why Gerrit admin, Jenkins admin, Jenkins Gerrit
  integration, test user, LDAP bind, runtime, and `operator` accounts are
  separate.
- Any offline-related match is reference-only, non-goal, or prohibition text.

## Step 3: Define The Simulation Model

Create `simulation/README.md` and the simulation substructure for two
machinery layers:

- Docker-based simulation first, with the bundle factory represented as a
  container.
- VM-based simulation second.

The simulation model must include five machines/environments:

| Machine/environment | Docker form | VM form | Responsibility |
| --- | --- | --- | --- |
| Bundle factory | Container | VM | Runs role helper `prepare-artifacts` commands and produces curated application artifacts, plugins, manifests, and checksums. |
| LDAP | Container | VM | Hosts LDAP bind, admin, and test accounts and groups. |
| Gerrit | Container | VM | Runs Gerrit with LDAP authentication, SSH access, integration permissions, and the `Verified` label. |
| Jenkins controller | Container | VM | Runs Jenkins, LDAP/JCasC configuration, Gerrit Trigger, and agent registration. |
| Jenkins agent | Container | VM | Runs SSH build jobs scheduled by Jenkins. |

The simulation model derives account usage from the account model defined in
Step 2. It must not introduce a separate account taxonomy. It must exercise
these Step 2 accounts:

- Gerrit admin account.
- Jenkins admin account.
- Jenkins Gerrit integration account.
- Test user account.
- LDAP bind account.
- Gerrit runtime account.
- Jenkins runtime account.
- Jenkins agent runtime account.
- `operator` account.

Implementation notes:

- Docker simulation is the first gate for every integration behavior.
- The Docker bundle factory container prepares curated application artifacts,
  plugins, manifests, and checksums before service containers start.
- The bundle factory is an environment, not a public API. Do not add a
  `bundle-factory-helper.sh`; artifact preparation remains exposed through the
  role helpers' `prepare-artifacts` commands.
- VM simulation should repeat Docker-verified flows in a systemd-oriented,
  production-like environment after Docker behavior is stable.
- Public internet fallback is allowed only in simulation and must be labeled
  `simulation-only` in docs, logs, and summaries.
- Do not port the reference repo's supported offline Ubuntu dependency bundle
  workflow into v1 simulation.

Verification:

```bash
rg -n "bundle factory|LDAP|Gerrit|Jenkins controller|Jenkins agent|operator" simulation docs
rg -n "Docker|VM|simulation-only|Verified|Gerrit Trigger" simulation docs
rg -n "local OS|LDAP-backed|prepare-artifacts|bundle-factory-helper" simulation docs
rg -n "supported offline|offline Ubuntu|offline-bundle" simulation docs
```

Acceptance criteria:

- Simulation docs describe all five machines/environments.
- Simulation docs map account usage back to Step 2 and do not define a separate
  account taxonomy.
- The `operator` account is documented as a simulation environment OS account,
  not a Gerrit/Jenkins product account.
- No bundle factory helper or bundle factory public API is introduced.
- Docker is documented as the first verification gate.
- VM verification is documented as a follow-up gate, not a prerequisite for
  early Docker milestones.
- Any target-host public internet fallback wording is explicitly
  simulation-only.
- Any offline-related match is reference-only, non-goal, or prohibition text.

## Step 4: Create The Gerrit Manual And Helper

Use these reference inputs:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/docs/gerrit-install-air-gapped.md
/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/gerrit-operator.sh
```

Create:

- `docs/gerrit-user-manual.md`
- `scripts/gerrit-helper.sh`
- `examples/gerrit.env.example`
- Gerrit templates under `templates/gerrit/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Gerrit artifact preparation.
4. Gerrit installation.
5. Gerrit configuration.
6. LDAP authentication assumptions.
7. Jenkins integration prerequisites.
8. Validation.
9. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure
configure-integration
validate
collect-evidence
run
```

Implementation notes:

- `prepare-artifacts` prepares version-pinned Gerrit artifacts, plugins,
  manifests, and checksums.
- The helper must not expose `prepare-offline-deps-bundle`,
  `install-offline-deps`, or other supported offline Ubuntu dependency bundle
  commands.
- The manual remains the authority; helper commands are repeatable
  accelerators for reviewed env files.
- Mutating helper commands should require explicit confirmation unless a
  reviewed `--yes` flag is provided.

Verification:

```bash
bash -n scripts/gerrit-helper.sh
scripts/gerrit-helper.sh --help
scripts/gerrit-helper.sh print-env-template
scripts/gerrit-helper.sh --env examples/gerrit.env.example --dry-run preflight
rg -n "prepare-artifacts|configure-integration|collect-evidence" docs/gerrit-user-manual.md scripts/gerrit-helper.sh
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/gerrit-user-manual.md scripts/gerrit-helper.sh
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- Gerrit artifact checksums and manifests are produced or planned by the
  helper.
- Gerrit validation covers startup, endpoint reachability, LDAP access, SSH
  access, plugin readiness, and integration account readiness.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.

## Step 5: Create The Jenkins Controller Manual And Helper

Use these reference inputs:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/docs/jenkins-install-air-gapped.md
/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/jenkins-operator.sh
```

Create:

- `docs/jenkins-controller-manual.md`
- `scripts/jenkins-controller-helper.sh`
- `examples/jenkins-controller.env.example`
- Jenkins controller templates under `templates/jenkins-controller/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Jenkins controller artifact and plugin preparation.
4. Jenkins installation.
5. Jenkins runtime configuration.
6. LDAP/JCasC configuration.
7. Gerrit Trigger base configuration.
8. Build-agent registration prerequisites.
9. Validation.
10. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-service
install-plugins
configure-jcasc
configure-integration
validate
collect-evidence
run
```

Implementation notes:

- Preserve the reference repo's useful Jenkins plugin and JCasC patterns.
- Treat plugin versions and checksums as curated artifacts.
- Keep Jenkins admin and Jenkins Gerrit integration identities separate.
- Do not run builds on the controller except for explicit simulation-only
  checks; production-like validation should use the Jenkins agent.

Verification:

```bash
bash -n scripts/jenkins-controller-helper.sh
scripts/jenkins-controller-helper.sh --help
scripts/jenkins-controller-helper.sh print-env-template
scripts/jenkins-controller-helper.sh --env examples/jenkins-controller.env.example --dry-run preflight
rg -n "JCasC|LDAP|Gerrit Trigger|prepare-artifacts|collect-evidence" docs/jenkins-controller-manual.md scripts/jenkins-controller-helper.sh
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/jenkins-controller-manual.md scripts/jenkins-controller-helper.sh
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- Jenkins controller validation covers startup, endpoint reachability, LDAP,
  plugins, JCasC, Gerrit SSH connectivity, and Gerrit Trigger readiness.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.

## Step 6: Create The Jenkins Agent Manual And Helper

Use these reference inputs:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/docs/jenkins-agent-install-air-gapped.md
/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/jenkins-operator.sh
```

Create:

- `docs/jenkins-agent-manual.md`
- `scripts/jenkins-agent-helper.sh`
- `examples/jenkins-agent.env.example`
- Jenkins agent templates under `templates/jenkins-agent/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated agent artifact preparation.
4. Agent host installation.
5. Agent runtime account and SSH setup.
6. Jenkins controller node registration.
7. Scheduling validation.
8. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-runtime
configure-controller-node
validate
collect-evidence
run
```

Implementation notes:

- Jenkins connects out to the agent over SSH.
- The agent must have a dedicated runtime user and remote filesystem path.
- The controller's built-in node should remain at zero executors in
  production-like docs.
- Agent validation must prove that Jenkins can schedule work on the configured
  label.

Verification:

```bash
bash -n scripts/jenkins-agent-helper.sh
scripts/jenkins-agent-helper.sh --help
scripts/jenkins-agent-helper.sh print-env-template
scripts/jenkins-agent-helper.sh --env examples/jenkins-agent.env.example --dry-run preflight
rg -n "agent|SSH|label|executor|collect-evidence" docs/jenkins-agent-manual.md scripts/jenkins-agent-helper.sh
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/jenkins-agent-manual.md scripts/jenkins-agent-helper.sh
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- Agent validation covers SSH reachability, remote filesystem readiness,
  Jenkins node registration, and job scheduling.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.

## Step 7: Implement Gerrit Trigger Integration

Use the trigger behavior proven by the reference Docker lab as source
material:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/lab/README.md
/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/gerrit-operator.sh
/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/jenkins-operator.sh
```

Create `docs/gerrit-trigger-integration.md` and templates for:

- Gerrit `Verified` label definition.
- Gerrit access permissions for the Jenkins integration actor.
- Jenkins Gerrit Trigger server configuration.
- Disposable Jenkins verification job.
- Disposable Gerrit verification project/change.

Implementation notes:

- Jenkins must authenticate to Gerrit with the Jenkins Gerrit integration
  actor, not a human Jenkins admin.
- Gerrit must grant read, stream-events, and `Verified` voting permissions to
  the integration actor or group.
- Verification may create disposable projects, jobs, and changes, and must
  label those as verification artifacts.
- Failed `Verified` voting must be surfaced separately from event-stream or
  job-scheduling failures.

Verification:

```bash
rg -n "Verified|Gerrit Trigger|stream-events|patchset-created|integration" docs templates scripts simulation
```

Docker simulation acceptance:

- A disposable Gerrit change emits a `patchset-created` event.
- Jenkins receives the event and schedules the verification job.
- The job runs on the Jenkins agent.
- Jenkins posts `Verified +1` to the Gerrit change.
- Evidence records the change, build, vote, and verification mode.

## Step 8: Build Docker Simulation

Use these reference inputs:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/lab
```

Create Docker simulation assets under `simulation/docker/` for:

- LDAP service with seeded bind/admin/test users.
- Gerrit service configured for LDAP and `Verified` voting.
- Jenkins controller configured with LDAP, JCasC, plugins, and Gerrit Trigger.
- Jenkins SSH agent service.
- Full verification wrapper.

Expected command surface:

```text
simulation/docker/preflight.sh
simulation/docker/render-config.sh
simulation/docker/up.sh
simulation/docker/verify.sh
simulation/docker/full-verify.sh
simulation/docker/down.sh
```

Implementation notes:

- Docker is the first gate for integration behavior.
- Docker logs must be written to bounded log files, not streamed verbosely into
  normal operator output.
- Any internet use during Docker artifact preparation or fallback must be
  labeled simulation-only.
- Generated local state must be ignored or clearly documented as generated.

Verification:

```bash
bash -n simulation/docker/*.sh
simulation/docker/preflight.sh
simulation/docker/render-config.sh
simulation/docker/up.sh
simulation/docker/verify.sh
simulation/docker/full-verify.sh
```

Acceptance criteria:

- Docker simulation starts all five machines, including the bundle factory
  container.
- LDAP, Gerrit, Jenkins controller, and Jenkins agent checks pass.
- Full verification proves Gerrit Trigger and `Verified +1`.
- Verification writes a summary that labels the mode as Docker simulation.

## Step 9: Build VM Simulation

Use these reference inputs:

```text
/home/ubuntu/ai-assisted/gerrit-jenkins/docs/offline-bundle-verification.md
/home/ubuntu/ai-assisted/gerrit-jenkins/vm/scripts/vm-verify.sh
```

Create VM simulation assets under `simulation/vm/` after Docker verification is
stable.

Expected command surface:

```text
simulation/vm/vm-verify.sh create
simulation/vm/vm-verify.sh bootstrap
simulation/vm/vm-verify.sh configure
simulation/vm/vm-verify.sh execute
simulation/vm/vm-verify.sh audit
simulation/vm/vm-verify.sh full
```

Implementation notes:

- VM simulation should use separate LDAP, Gerrit, Jenkins controller, and
  Jenkins agent VMs.
- The VM model is production-like validation, not strict air-gap verification.
- Remove or rename reference workflow concepts that imply supported offline
  Ubuntu dependency bundles.
- VM commands that mutate remote or host state require explicit operator
  approval and must describe expected side effects.

Verification:

```bash
bash -n simulation/vm/vm-verify.sh
simulation/vm/vm-verify.sh --help
simulation/vm/vm-verify.sh full --preflight-only --env simulation/vm/example.env
```

Acceptance criteria:

- VM preflight can validate host tooling, env values, SSH reachability, and
  target addresses before mutation.
- Full VM verification repeats the Docker-proven LDAP, Gerrit, Jenkins,
  Jenkins agent, Gerrit Trigger, and `Verified` vote flow.
- Evidence labels the mode as VM simulation or production-like validation,
  depending on the run.

## Step 10: Add Validation And Evidence Collection

Create `docs/validation-and-evidence.md` and `scripts/collect-evidence.sh`.

Evidence must capture:

- Verification mode.
- Timestamp and package version.
- Hostnames and service endpoints.
- Sanitized config input manifest.
- Artifact manifest and checksums.
- Helper command versions or git commit.
- Service startup and endpoint checks.
- LDAP access checks.
- Jenkins agent scheduling result.
- Gerrit Trigger event, build, and `Verified` vote result.
- Bounded log references.

Implementation notes:

- Do not store secrets in evidence.
- Do not stream verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, or
  verification logs into normal command output.
- Summaries must distinguish simulation-only runs from production-like runs.
- Evidence should be useful for audit review without requiring repo history.

Verification:

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "simulation-only|production-like|checksums|Verified|LDAP|agent" docs/validation-and-evidence.md scripts/collect-evidence.sh
```

Acceptance criteria:

- Evidence collection can be run after role-specific validation and after
  full integration validation.
- Evidence summaries include mode labels and checksum references.
- Secret-looking env values are omitted or redacted.

## Step 11: Add Cross-Repository Boundary Checks

Add a lightweight verification check that prevents old reference language from
re-entering v1 docs and helper command surfaces.

Recommended checks:

```bash
rg -n "strict air-gapped|supported offline|offline Ubuntu dependency|prepare-offline-deps|install-offline-deps" docs scripts templates simulation examples
rg -n "simulation-only" docs scripts templates simulation examples
```

Implementation notes:

- Matches from the first command are acceptable only when they are
  reference-only, non-goal, or prohibition text.
- Historical source references may mention the old repo, but they must be
  clearly identified as reference-only or non-goal context.
- The second command should find explicit labels wherever public internet
  fallback appears in simulation.

Acceptance criteria:

- PRD non-goals are enforced by docs and helper interfaces.
- Simulation-only fallback is visibly labeled in docs, logs, and summaries.
- No helper exposes supported offline Ubuntu dependency bundle workflows.

## Step 12: Final End-To-End Acceptance

Run final acceptance in this order:

1. Static docs and shell checks.
2. Helper `--help`, `print-env-template`, and `--dry-run preflight` checks.
3. Docker simulation preflight.
4. Docker full verification.
5. VM preflight.
6. VM full verification when VM infrastructure is available.

Minimum command set:

```bash
bash -n scripts/*.sh simulation/docker/*.sh simulation/vm/*.sh
scripts/gerrit-helper.sh --help
scripts/jenkins-controller-helper.sh --help
scripts/jenkins-agent-helper.sh --help
scripts/collect-evidence.sh --help
simulation/docker/full-verify.sh
simulation/vm/vm-verify.sh full --preflight-only --env simulation/vm/example.env
```

Final acceptance criteria:

- A new operator can follow the docs without repo history.
- Gerrit, Jenkins controller, and Jenkins agent have manual and helper flows.
- LDAP-backed identity assumptions are documented and simulated.
- Jenkins can schedule a job on the agent.
- Gerrit Trigger posts `Verified +1` back to Gerrit.
- Validation artifacts are produced and retained for review.
- The package does not claim strict air-gapped support in v1.
- The package does not support offline Ubuntu dependency bundles in v1.

## Commit Strategy

Keep commits small and logical:

1. Add repository structure and implementation plan.
2. Add account model.
3. Add simulation model docs.
4. Add Gerrit manual/helper/templates.
5. Add Jenkins controller manual/helper/templates.
6. Add Jenkins agent manual/helper/templates.
7. Add Gerrit Trigger integration.
8. Add Docker simulation.
9. Add VM simulation.
10. Add validation and evidence collection.
11. Add boundary checks and final acceptance docs.

Use standard Git-style commit messages with concise imperative subjects, for
example:

```text
Add Gerrit setup helper
Add Docker simulation verification
Document validation evidence
```
