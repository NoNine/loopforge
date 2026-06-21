# Gerrit/Jenkins Setup Package Implementation Plan

## Purpose

This document defines the implementation plan for building the v1
Gerrit/Jenkins setup package described in `docs/prd.md`.

The behavior digest is `docs/reference-digest.md`. That digest summarizes the
known-working draft repository behavior without allowing implementation agents
to copy code, docs, templates, scripts, config files, command bodies, or
verbatim implementation from `/home/ubuntu/ai-assisted/gerrit-jenkins`.

Implementation agents must use `docs/reference-digest.md`, `docs/prd.md`, the
role native-operations references, and this plan as their reference set. Do not
open or copy from the draft repository unless a human explicitly approves a
new reference review.

The draft behavior was originally framed around air-gapped installation. This
package must adapt the behavior to the v1 boundary:

- v1 is not a strict air-gapped installer.
- v1 does not support offline Ubuntu dependency bundles.
- Public internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only and must be labeled that way in docs, logs, and verification
  summaries.

The implementation should proceed in verifiable steps. Each step below must
leave the repository in a reviewable state and include a direct verification
command or checklist.

## Functional Command Contract

Every advertised helper or verifier command must be functional for its
lifecycle phase before the step that introduces it can be accepted.

- Normal command execution must perform the real lifecycle action implied by
  the command name or exit nonzero with a clear unsupported or blocked reason.
- `--dry-run` may describe intended mutation, but non-dry-run output must not
  report only "would do" behavior.
- Readiness gates fail on dummy success, operation-plan-only success,
  `planned-checks-only`, model-only proof for required runtime checks, or
  unsupported behavior that exits 0.
- `print-env-template`, `preflight`, `prepare-artifacts`, and
  `collect-evidence` must be functional for their own lifecycle phases even
  though they do not directly configure a running service.
- Commands that install, configure, validate, or exercise Gerrit, Jenkins, the
  Jenkins agent, LDAP integration, Gerrit Trigger, SSH connectivity, or
  `Verified` voting must pass real runtime checks in the target environment.
  Role readiness requires the relevant service process or daemon to be started
  from staged artifacts and checked through its runtime protocol, API, or
  filesystem state. Local responders, marker files, synthetic transcripts, and
  model-only records are not acceptable readiness proof.

Role-step readiness gates must run against the shared Docker harness introduced
before the role helpers. Artifact bundles are always produced in the bundle
factory environment, then staged to target environments and verified by
manifest and checksum on the target before any target mutation.

## Version Baseline

All role helpers, Docker harnesses, Docker simulation, VM verifier scaffolds,
and future real VM verification must use the same default version combination
unless a later reviewed change updates this baseline everywhere.

- Ubuntu target baseline: Ubuntu 24.04.4 LTS, release `24.04`, codename
  `noble`.
- Java runtime: OpenJDK 21 for Gerrit, Jenkins controller, and Jenkins agent.
- Gerrit: `3.13.6` for the default conservative production rollout.
- Gerrit `3.14.0` is treated as a current/latest line noted by the reference
  material, but it is not the v1 default because `.0` releases require careful
  production testing.
- Jenkins controller: `2.555.3 LTS`.
- Jenkins Plugin Installation Manager Tool: `2.15.0`.
- Jenkins agent: no standalone Jenkins core version; it uses OpenJDK 21,
  SSH server/client tooling, and the Jenkins SSH Build Agents plugin from the
  controller plugin bundle.

Evidence records and verifier summaries must record this version combination.
Docker and VM verification must fail or report blocked rather than claiming
comparable verification when the environment does not match the baseline.

## Evidence Contract

Checkpoint-level evidence requirements define what must be proven at each
workflow boundary. The common evidence record schema defines how that proof is
recorded so role helpers, Docker/VM verifiers, and final audits can be compared
consistently.

Common evidence records must include:

- Verification mode.
- Timestamp.
- Role or environment name.
- Checkpoint name.
- Command name.
- Pass, fail, blocked, unsupported, or not-applicable status.
- Reviewed input fingerprint or sanitized config input manifest.
- Artifact manifest references.
- Checksum references and verification result.
- Observed checks for the checkpoint.
- Bounded log references.
- Redaction status.

Producer rules:

- Role-local `collect-evidence` commands emit role-scoped checkpoint records
  using this schema.
- `scripts/integration-setup.sh collect-evidence` emits integration-scoped
  records for cross-role SSH, trigger, scheduling, and vote checkpoints.
- Docker and VM verifiers aggregate role-local records and add simulation,
  production-like, and end-to-end records.
- Global evidence collection audits and combines role-local and verifier
  records into the final evidence package.
- Records may mark fields as not applicable when they are outside the producer's
  scope, but required behavior must not be reported as success when it is
  failed, unproven, dummy, modeled, operation-plan-only, or
  `planned-checks-only`.
- Evidence must not include secrets, private keys, tokens, passwords, LDAP bind
  secrets, or full secret-bearing env values.
- Verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, and verification
  logs must be referenced as bounded log files, not streamed.

## Step 1: Establish The Repository Structure

Create the package layout before porting behavior. Keep manuals, templates,
helpers, simulations, examples, and logs separated so future changes have
clear ownership.

Planned structure:

```text
README.md
docs/
  prd.md
  implementation-plan.md
  reference-digest.md
  account-model.md
  gerrit-setup-manual.md
  jenkins-controller-setup-manual.md
  jenkins-agent-setup-manual.md
  gerrit-trigger-integration.md
  validation-and-evidence.md
examples/
  gerrit.env.example
  jenkins-controller.env.example
  jenkins-agent.env.example
scripts/
  common.sh
  gerrit-setup.sh
  jenkins-controller-setup.sh
  jenkins-agent-setup.sh
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

- `README.md` is the top-level operator entrypoint and should orient new
  operators and reviewers to the setup flow, v1 boundaries, manuals,
  simulations, and validation evidence.
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
test -f README.md
find . -maxdepth 1 -type f | sort
find docs examples scripts templates simulation -maxdepth 3 -type d | sort
find docs examples scripts templates simulation -maxdepth 3 -type f | sort
rg -n "air-gapped|offline-bundle" docs examples scripts templates simulation
```

Acceptance criteria:

- The directory layout exists and matches the structure above unless a later
  implementation note explicitly justifies a small naming change.
- `README.md` exists as the top-level orientation document and points readers
  to the setup flow and v1 boundaries.
- Any `air-gapped` or `offline-bundle` match is reference-only, non-goal, or
  prohibition text; no supported v1 command or path uses those terms.
- `logs/` exists or is documented as a generated runtime directory.

## Step 2: Define The Account Model

Start with the account model in `docs/reference-digest.md`.

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
| `ci-operator` account | Local OS account on simulation machines | Runs orchestration, SSH access, helper commands, and evidence collection. |

Implementation notes:

- Preserve the separation between runtime, human admin, integration, test, bind,
  and simulation environment accounts.
- State that human admin and test accounts are LDAP-backed, runtime accounts are
  local OS accounts by default, LDAP bind accounts are read-only LDAP service
  accounts, and the Jenkins Gerrit integration account is a Gerrit service
  account.
- State that the `ci-operator` account is not a Gerrit/Jenkins runtime, admin,
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
  integration, test user, LDAP bind, runtime, and `ci-operator` accounts are
  separate.
- Any offline-related match is reference-only, non-goal, or prohibition text.

## Step 3: Define The Simulation Model

Create `simulation/README.md` and simulation model docs for two machinery
layers:

- Docker-based simulation first, with the bundle factory represented as a
  container.
- VM-based simulation second.

Step 3 owns documentation and directory-model definition only. It does not add
executable verifier scripts; those are introduced by the Docker harness,
Docker simulation, and VM simulation steps.

Step 3-owned files:

```text
simulation/README.md
simulation/docker/README.md
simulation/vm/README.md
```

The simulation docs must describe generated-output locations for state, staged
artifacts, evidence, and bounded logs. Generated runtime output must be ignored
or clearly documented as generated.

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
- `ci-operator` account.

Implementation notes:

- A shared Docker harness is introduced before the role helper steps so Gerrit,
  Jenkins controller, and Jenkins agent readiness gates can run in real
  containers.
- The full Docker simulation remains the first end-to-end integration gate for
  Gerrit Trigger behavior, Jenkins agent scheduling, and `Verified` voting.
- The Docker bundle factory container prepares curated application artifacts,
  plugins, manifests, and checksums before service containers start.
- The bundle factory is an environment, not a public API. Do not add a
  `bundle-factory-helper.sh`; artifact preparation remains exposed through the
  role helpers' `prepare-artifacts` commands.
- VM simulation should repeat Docker-verified flows in a systemd-oriented,
  production-like environment after Docker behavior is stable.
- Follow the source-boundary terminology in `docs/prd.md`: Ubuntu/OS
  dependencies and application artifacts are separate supply lanes. Target
  hosts may use approved internal Ubuntu/OS package repositories for OS
  dependencies, while application artifacts are prepared only in the bundle
  factory or staging environment, staged to target hosts, and verified by
  manifest and checksum before mutation.
- Public internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only and must be labeled `simulation-only` in docs, logs, and
  summaries. Target hosts must not download Gerrit/Jenkins application artifacts
  from the public internet as fallback.
- Docker and VM simulation inputs must preserve the Version Baseline. A
  simulation or verifier must fail or report blocked rather than claim
  comparable readiness when the Ubuntu, Java, Gerrit, Jenkins controller,
  plugin-manager, or Jenkins agent/plugin-bundle versions differ.
- Do not port the reference repo's supported offline Ubuntu dependency bundle
  workflow into v1 simulation.

Shared simulation workflow:

| Checkpoint | Docker execution | VM execution | Required verifier evidence |
| --- | --- | --- | --- |
| Preflight | Check local Docker/Compose tooling, env values, ports, disk, and generated-state paths. | Check host tooling, env values, SSH reachability, target addresses, disk, and approval-sensitive options. | Preflight summary with mode label and no target mutation. |
| Input rendering | Render Docker simulation config from reviewed env values. | Bootstrap reviewed env values and machine connection inputs. | Rendered-input manifest with secret values redacted. |
| Artifact preparation | Run role helper `prepare-artifacts` commands in the bundle factory container. | Run role helper `prepare-artifacts` commands on the bundle factory VM. | Role artifact directories, manifests, checksums, and any `simulation-only` internet-use labels. |
| Artifact staging | Stage prepared artifacts from bundle factory output to Gerrit, Jenkins controller, and Jenkins agent containers. | Transfer prepared artifacts from the bundle factory VM to Gerrit, Jenkins controller, and Jenkins agent VMs. | Target-side staged paths and manifest/checksum verification before service mutation. |
| Service configuration | Start or configure LDAP, Gerrit, Jenkins controller, and Jenkins agent containers from staged artifacts. | Configure LDAP, Gerrit, Jenkins controller, and Jenkins agent VMs with systemd-oriented service behavior. | Runtime-account, service-startup, endpoint, LDAP, plugin, and config evidence. |
| Readiness checks | Run independently repeatable Docker checks before end-to-end verification. | Run independently repeatable VM checks before end-to-end verification. | Separate pass/fail results for LDAP, local OS runtime accounts, Gerrit HTTP/SSH, Jenkins HTTP/LDAP/JCasC/plugins, Jenkins-to-Gerrit SSH, stream-events, and agent readiness. |
| End-to-end execution | Run disposable change, Jenkins trigger, agent job, and `Verified +1` verification. | Repeat the Docker-proven disposable change, Jenkins trigger, agent job, and `Verified +1` verification. | Separate event-stream, job-scheduling, agent-execution, and vote-posting evidence. |
| Evidence audit | Collect Docker simulation summaries and bounded log references. | Collect VM simulation or production-like summaries and bounded log references. | Mode-labeled evidence, checksums, fingerprints, and redacted bounded log references. |

Checkpoint ownership map:

| Checkpoint | Docker owner | VM owner |
| --- | --- | --- |
| Preflight | `simulation/docker/docker-harness.sh preflight`. | `simulation/vm/vm-verify.sh check --preflight-only` or `simulation/vm/vm-verify.sh full --preflight-only`. |
| Input rendering | `simulation/docker/docker-harness.sh render-config`. | `simulation/vm/vm-verify.sh bootstrap`. |
| Artifact preparation | `simulation/docker/docker-harness.sh prepare-artifacts [--role ...]`. | `simulation/vm/vm-verify.sh prepare-artifacts`. |
| Artifact staging | `simulation/docker/docker-harness.sh stage-artifacts [--role ...]`. | `simulation/vm/vm-verify.sh stage-artifacts`. |
| Service configuration | `simulation/docker/docker-harness.sh up`. | `simulation/vm/vm-verify.sh configure`. |
| Readiness checks | `simulation/docker/docker-harness.sh check` for full Docker readiness; `simulation/docker/docker-harness.sh run-role-gate --role ...` for a single role. | `simulation/vm/vm-verify.sh check`. |
| End-to-end execution | `simulation/docker/docker-harness.sh full-verify`. | `simulation/vm/vm-verify.sh execute` or `simulation/vm/vm-verify.sh full`. |
| Evidence audit | Role-local `collect-evidence`, Docker harness evidence, and later global aggregation. | `simulation/vm/vm-verify.sh audit` and later global aggregation. |

Ownership rules:

- Step 3 documents the shared simulation model, checkpoint semantics, and
  command ownership only.
- Step 6 implements Docker harness ownership for role-step readiness gates.
- Step 11 implements full Docker simulation ownership for end-to-end
  integration verification.
- Step 12 implements the non-mutating VM verifier scaffold for command
  contract, env parsing, approval guardrails, bounded logging, and evidence
  schema integration.
- Step 15 is the future real VM implementation and verification gate. It is
  documented for later work and skipped in the current default plan.
- Simulation wrappers orchestrate role helpers but must not replace role
  behavior with modeled success.
- The Docker harness owns role-step readiness gates and Docker end-to-end
  integration.

Command convention model:

- Every command surface uses one owning script plus a subcommand.
- Role helpers use `scripts/<role>-setup.sh <command>`.
- Cross-role integration uses `scripts/integration-setup.sh <command>`.
- Docker simulation uses `simulation/docker/docker-harness.sh <command>`.
- VM simulation uses `simulation/vm/vm-verify.sh <command>`.
- Do not add standalone role phase scripts such as `scripts/preflight.sh`,
  Docker phase scripts such as `simulation/docker/check.sh`, or VM phase
  scripts such as `simulation/vm/check.sh`.
- Cross-role commands must not be exposed by role helpers. They belong to
  `scripts/integration-setup.sh`.

Verification:

```bash
test -f simulation/README.md
test -f simulation/docker/README.md
test -f simulation/vm/README.md
rg -n "bundle factory|LDAP|Gerrit|Jenkins controller|Jenkins agent|operator" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "Docker|VM|simulation-only|Verified|Gerrit Trigger" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "Checkpoint ownership|docker-harness.sh|vm-verify.sh" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "Ubuntu/OS dependencies|Application artifacts|approved internal Ubuntu/OS package repositories" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "local OS|LDAP-backed|prepare-artifacts|bundle-factory-helper" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "supported offline|offline Ubuntu|offline-bundle" simulation/README.md simulation/docker/README.md simulation/vm/README.md
```

Acceptance criteria:

- Simulation docs describe all five machines/environments.
- Simulation docs map account usage back to Step 2 and do not define a separate
  account taxonomy.
- The `ci-operator` account is documented as a simulation environment OS account,
  not a Gerrit/Jenkins product account.
- Simulation docs define generated-output locations for state, staged
  artifacts, evidence, and bounded logs.
- No bundle factory helper or bundle factory public API is introduced.
- Docker is documented as the first full integration verification gate.
- Docker harness and VM verifier responsibilities are distinguishable by
  checkpoint.
- Real VM verification is documented as a future follow-up gate, not a
  prerequisite for early Docker milestones or current default acceptance.
- Ubuntu/OS dependency handling and application artifact handling are documented
  as separate lanes.
- Any target-host public internet fallback wording is limited to Ubuntu/OS
  dependency installation and is explicitly simulation-only.
- Any offline-related match is reference-only, non-goal, or prohibition text.

## Step 4: Define The Operator Workflow Contract

Document the default operator workflow as a phase contract, not as a full
runnable command transcript. The contract must define phase order, execution
environment, helper command ownership, inputs and outputs, side effects, and
the checkpoint that lets operators stop, review evidence, and resume at a known
boundary. The cross-role command sequence belongs in
`docs/integration-setup-manual.md`.

Workflow contract:

| Phase | Machine/environment | Helper commands | Inputs/outputs | Side effects | Required checkpoint |
| --- | --- | --- | --- | --- | --- |
| Inputs | Operator workstation | `print-env-template`, `preflight` | Copies env examples into reviewed role env files, removes all `CHANGE_ME` values, keeps secrets out of committed examples, reviews cross-role values, and confirms browser-visible URLs for simulation. | None beyond local env-file creation. | Reviewed env files exist for Gerrit, Jenkins controller, and Jenkins agent, and preflight failures are resolved before mutation. |
| Artifacts | Bundle factory | `prepare-artifacts` | Consumes reviewed role env files and produces role artifact directories, manifests, and checksums. | Downloads or copies curated application artifacts and plugins; any public internet use is labeled `simulation-only` when it occurs in simulation. | Role artifact manifests and checksums are produced and retained as evidence inputs. |
| Artifact staging | Bundle factory and target hosts | Operator-managed file transfer; role-local checksum verification in `install` or `preflight` | Stages prepared role artifacts from the bundle factory to the Gerrit host, Jenkins controller, and Jenkins agent host. | Operator copies files onto target hosts but does not install services until checksums pass. | Staged artifact paths exist on each target host, and target-side manifest/checksum verification passes before installation. |
| Gerrit readiness | Gerrit host | `install`, `configure`, `validate` | Consumes Gerrit env values and staged Gerrit artifacts; produces Gerrit service config and readiness evidence. | Installs packages from approved sources, creates or updates local runtime files, and starts or restarts Gerrit. | Step 7 role gate only: Gerrit starts, uses LDAP, exposes HTTP/SSH, records bounded logs, and stops before Jenkins integration mutation. |
| Jenkins controller readiness | Jenkins controller | `install`, `configure-service`, `install-plugins`, `configure-jcasc`, `validate` | Consumes Jenkins controller env values and staged Jenkins artifacts; produces service, plugin, and JCasC evidence. | Installs packages from approved sources, creates or updates Jenkins runtime files, installs plugins, and starts or restarts Jenkins. | Controller-only checkpoint: Jenkins starts, uses LDAP/JCasC, has required plugins, records bounded logs, and stops before Gerrit Trigger, credential transfer, node registration, scheduling, or vote proof. |
| Jenkins agent readiness | Jenkins agent | `install`, `configure-runtime`, `validate` | Consumes Jenkins agent env values and staged Jenkins agent artifacts; produces SSH daemon, runtime account, filesystem, bounded log, and evidence records. | Installs packages from approved sources and creates or updates agent-host runtime files and SSH service state. | Step 9 role gate only: the agent host proves OS/tooling, SSH daemon, runtime account, filesystem, staged artifact, bounded log, and evidence readiness, and stops before credential transfer, controller node registration, or scheduling proof. |
| Shared integration | Jenkins controller, Gerrit host, and Jenkins agent | `scripts/integration-setup.sh` | Consumes reviewed role env files plus reviewed integration env values. Produces Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, Gerrit Trigger, node, validation, vote, and integration evidence. | Creates or updates controller-held key material, Gerrit public-key registration, reviewed Gerrit config changes, Jenkins credentials, Jenkins node config, disposable verification artifacts, and review votes. | Run after all three role manuals complete. Follow `docs/integration-setup-manual.md` for the cross-role command sequence and stop/review points. |
| Evidence | All role environments | `collect-evidence` | Consumes role validation outputs, manifests, checksums, sanitized config manifests, and bounded log references. | Writes local evidence summaries only; it must not expose secrets or private keys. | Mode-labeled evidence, manifests, checksums, fingerprints, and bounded log references are retained for each checkpoint. |

Operator sequencing rules:

- Run `prepare-artifacts` from the bundle factory environment for each role.
- Stage prepared artifacts by operator-managed file transfer from the bundle
  factory to each target host before running target-host installation, then
  verify manifests and checksums on the target host before mutation.
- Application artifact bundles for Gerrit, Jenkins controller, and Jenkins
  agent are key-free. They must not contain SSH private keys, public keys,
  `authorized_keys`, or generated key/public-key handoff files. Keypair
  generation and public-key handoff between Gerrit, Jenkins controller, and
  agent are integration-step work.
- Target-host OS dependencies come from approved internal Ubuntu/OS package
  repositories. Public internet fallback for target-host OS dependency
  installation is simulation-only and must be labeled in docs, logs, manifests,
  and verification summaries.
- Complete Gerrit, Jenkins controller, and Jenkins agent role-only bringup
  before running the shared cross-role integration helper.
- Use `docs/integration-setup-manual.md` for the approved cross-role helper
  command workflow. Role manuals must hand off to that document instead of
  duplicating the full integration command sequence.
- Product-like integration defaults to a global `Verified` CI label in reviewed
  `All-Projects` configuration. Jenkins read and `label-Verified -1..+1`
  grants stay scoped to the reviewed project and ref pattern, while
  `stream-events` remains a global capability grant.
- Jenkins Gerrit Trigger uses SSH for authentication and `stream-events`. The
  Gerrit REST review API is the default `Verified` vote posting path. Legacy
  SSH review commands or flags require explicit operator justification and
  compatibility evidence.
- The Jenkins agent helper must not register controller nodes.
- Treat role-local `validate` as role-only readiness validation. Treat shared
  `validate-integration` and `verify-trigger` as later cross-role acceptance
  for Gerrit SSH, event streaming, Jenkins agent scheduling, REST vote posting,
  and Gerrit review state.

Generated key transfer contract:

- Jenkins controller owns the Jenkins-to-Gerrit private key and the
  Jenkins-to-agent private key.
- Gerrit and Jenkins agent integration steps consume only public keys, never
  Jenkins-held private keys.
- Role manuals must name the env fields or files used for each public key
  transfer and must state expected file ownership and permissions.
- Evidence may record key fingerprints, public-key paths, and credential IDs,
  but must redact private-key material, passwords, tokens, and LDAP bind
  secrets.
- Key rotation is an explicit repeat of key generation, public key transfer,
  role-side reconfiguration, validation, and evidence collection.

Operator safety rules:

- Run `--dry-run` where supported before mutating target hosts, Jenkins, or
  Gerrit.
- Require interactive confirmation for mutating helper commands unless a
  reviewed `--yes` flag is provided.
- Each phase that mutates a host or application must describe expected side
  effects before execution.
- Each phase must emit bounded logs or evidence references so a failed run can
  be reviewed without replaying verbose runtime output.

Verification:

```bash
rg -n "Operator Workflow Contract|Phase \\| Machine/environment \\| Helper commands \\| Inputs/outputs \\| Side effects \\| Required checkpoint" docs/implementation-plan.md
rg -n "Artifact staging|Generated key transfer contract|Operator safety rules" docs/implementation-plan.md
rg -n "private key|public key|fingerprint|redact|CHANGE_ME|staged artifact" docs/implementation-plan.md
rg -n "^scripts/.+--env .+--yes" docs/implementation-plan.md
rg -n "integration-setup.sh|configure-gerrit-ssh|configure-agent-ssh|configure-trigger|validate-integration|verify-trigger" docs/implementation-plan.md
rg -n "^[[:space:]]*(run|configure-controller-node)$" docs/implementation-plan.md
```

Acceptance criteria:

- The documented operator workflow has no catch-all `run` command.
- The workflow identifies which side owns Jenkins-to-Gerrit and
  Jenkins-to-agent key generation.
- The workflow defines artifact staging from the bundle factory to target hosts
  and requires target-side checksum verification before installation.
- The workflow defines public key transfers, private-key custody, and evidence
  redaction requirements.
- The workflow identifies mutating phases and requires confirmation or reviewed
  `--yes` before mutation.
- The workflow separates agent host runtime setup from controller-side node
  registration and scheduling validation.
- The implementation plan does not embed a full runnable operator command
  transcript; runnable transcripts belong in future operator manuals.

## Step 5: Define Gerrit Trigger Integration

Use the trigger behavior summarized in `docs/reference-digest.md` as source
material.

Create `docs/gerrit-trigger-integration.md` and templates for:

- Gerrit `Verified` label definition.
- Gerrit access permissions for the Jenkins integration actor.
- Jenkins Gerrit Trigger server configuration.
- Disposable Jenkins verification job.
- Disposable Gerrit verification project/change.

Implementation notes:

- Jenkins must authenticate to Gerrit with the Jenkins Gerrit integration
  actor, not a human Jenkins admin.
- Product-like setup defines the global `Verified` label through reviewed
  `All-Projects` configuration.
- Gerrit must grant read and `label-Verified -1..+1` permissions to the
  integration actor or group only at the reviewed project/ref scope.
- Gerrit must grant `stream-events` as a global capability.
- Jenkins Gerrit Trigger uses SSH for authentication and event streaming.
- The Gerrit REST review API is the default `Verified` vote posting path.
- Legacy SSH review commands or flags are exception-only and require explicit
  operator justification plus compatibility evidence.
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
- Jenkins posts `Verified +1` to the Gerrit change through the Gerrit REST
  review API.
- Evidence records the change, build, vote, and verification mode.

## Step 6: Add Shared Docker Harness

Create the reusable Docker harness used by the Gerrit, Jenkins controller, and
Jenkins agent helper readiness gates. This harness provides real containers for
role-step validation, but it is not the full end-to-end Docker simulation.

Create:

- `simulation/docker/docker-harness.sh`
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
- Use the Version Baseline for the bundle factory, Gerrit target, Jenkins
  controller target, and Jenkins agent target. A Docker image tag such as
  `ubuntu:24.04` may represent the Ubuntu 24.04.4 LTS `noble` baseline only
  when the harness records the resolved image digest or OS release evidence.
- Use a real LDAP service image for the LDAP environment so LDAP reachability
  and seeded directory assumptions can be checked by later role gates.
- Do not use `gerritcodereview/gerrit` or `jenkins/jenkins` as Step 6 target
  containers, because their embedded WARs would weaken the v1 artifact
  boundary. Gerrit and Jenkins application artifacts must still be prepared in
  the bundle factory, staged to targets, and verified before target mutation.
- If Docker Compose v2 is unavailable but `docker-compose` v1 is available, the
  Step 6 harness may use `docker-compose`. The command implementation should
  detect and report the Compose command it will use.
- Existing generated `simulation/state/docker/<run-id>/`,
  `simulation/staging/docker/<run-id>/`, `simulation/evidence/docker/<run-id>/`,
  and `logs/docker/<run-id>/` content is not source material. Treat those paths
  as generated output and do not commit retained state or verbose logs.
- Harness evidence must record the Version Baseline values used by the run and
  must not report comparable readiness when container OS or artifact versions
  drift from that baseline.

Expected command surface:

```text
simulation/docker/docker-harness.sh preflight
simulation/docker/docker-harness.sh render-config
simulation/docker/docker-harness.sh up
simulation/docker/docker-harness.sh status
simulation/docker/docker-harness.sh prepare-artifacts --role gerrit
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-controller
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-agent
simulation/docker/docker-harness.sh stage-artifacts --role gerrit
simulation/docker/docker-harness.sh stage-artifacts --role jenkins-controller
simulation/docker/docker-harness.sh stage-artifacts --role jenkins-agent
simulation/docker/docker-harness.sh run-role-gate --role gerrit
simulation/docker/docker-harness.sh run-role-gate --role jenkins-controller
simulation/docker/docker-harness.sh run-role-gate --role jenkins-agent
simulation/docker/docker-harness.sh down
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
- `run-role-gate --role ...` runs the role helper readiness gate in the
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
bash -n simulation/docker/docker-harness.sh
simulation/docker/docker-harness.sh --help
simulation/docker/docker-harness.sh preflight
simulation/docker/docker-harness.sh render-config
simulation/docker/docker-harness.sh up
! simulation/docker/docker-harness.sh prepare-artifacts --role unknown
! simulation/docker/docker-harness.sh run-role-gate --role gerrit
simulation/docker/docker-harness.sh down
rg -n "dummy success|operation-plan-only|planned-checks-only|modeled" docs/implementation-plan.md
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

## Step 7: Create The Gerrit Manual And Helper

Use the Gerrit helper and integration behavior summarized in
`docs/reference-digest.md`.

Create:

- `docs/gerrit-setup-manual.md`
- `docs/gerrit-native-operations-reference.md`
- `scripts/gerrit-setup.sh`
- `examples/gerrit.env.example`
- Gerrit templates under `templates/gerrit/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Gerrit artifact preparation.
4. Gerrit installation.
5. Gerrit configuration.
6. LDAP authentication assumptions.
7. Deferred Jenkins integration prerequisites.
8. Validation.
9. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure
validate
collect-evidence
```

Implementation notes:

- `prepare-artifacts` prepares version-pinned Gerrit artifacts, plugins,
  manifests, and checksums, and the readiness gate must run it in the shared
  Docker harness bundle factory environment.
- Gerrit artifact bundles must be key-free. `prepare-artifacts` must not write
  Jenkins-to-Gerrit public keys, private keys, `authorized_keys`, or generated
  key handoff files, and staged artifact verification must reject them before
  target mutation. `Verified` label and Jenkins integration access templates
  are cross-role integration artifacts and must not be staged by the Gerrit
  role helper.
- Gerrit manifests must record `artifact_source=curated-bundle-factory`,
  `os_dependency_source=approved-internal-os-repos`,
  `public_internet_fallback=simulation-only`, and `bundle_contains_keys=no`.
- Gerrit defaults to the Version Baseline: Gerrit `3.13.6` and OpenJDK 21 on
  Ubuntu 24.04.4 LTS `noble`. Gerrit `3.14.0` is not the default and may be
  used only after a reviewed baseline update.
- Gerrit target commands consume only staged artifacts from the bundle factory
  output and must verify target-side manifests and checksums before install or
  configuration.
- `install`, `configure`, and `validate` must be functional against the Gerrit
  target container in the shared Docker harness. Gerrit cross-role integration
  must not be exposed as a role-helper command.
- `validate` must pass real Gerrit runtime checks in the target container,
  including daemon startup and protocol checks, not local responder output,
  operation-plan-only output, or `planned-checks-only` output.
- `collect-evidence` must emit role-local Gerrit checkpoint evidence using the
  Evidence Contract defined above.
- The helper must not expose `prepare-offline-deps-bundle`,
  `install-offline-deps`, or other supported offline Ubuntu dependency bundle
  commands.
- The manual remains the authority; helper commands are repeatable
  accelerators for reviewed env files.
- `docs/gerrit-native-operations-reference.md` is the strong reference for
  direct OS and Gerrit operations. Keep it consistent with the Gerrit manual
  and helper behavior, but never add repository helper commands to it.
- Mutating helper commands should require explicit confirmation unless a
  reviewed `--yes` flag is provided.

Verification:

```bash
bash -n scripts/gerrit-setup.sh
scripts/gerrit-setup.sh --help
scripts/gerrit-setup.sh print-env-template
scripts/gerrit-setup.sh --env examples/gerrit.env.example --dry-run preflight
simulation/docker/docker-harness.sh prepare-artifacts --role gerrit
simulation/docker/docker-harness.sh stage-artifacts --role gerrit
simulation/docker/docker-harness.sh run-role-gate --role gerrit
find simulation/evidence/docker -type f -name '*gerrit*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find simulation/evidence/docker -type f -name '*gerrit*')
rg -n "bundle_contains_keys=no|os_dependency_source=approved-internal-os-repos|public_internet_fallback=simulation-only" simulation/state/docker/<run-id>/bundle-factory/artifacts/gerrit/manifest.txt simulation/staging/docker/<run-id>/gerrit/manifest.txt
! find simulation/state/docker/<run-id>/bundle-factory/artifacts/gerrit simulation/staging/docker/<run-id>/gerrit -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "prepare-artifacts|collect-evidence" docs/gerrit-setup-manual.md scripts/gerrit-setup.sh
! scripts/gerrit-setup.sh --help | rg -n "configure-integration|verify-trigger|configure-agent"
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/gerrit-setup-manual.md scripts/gerrit-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes" docs/gerrit-native-operations-reference.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, and secret-redaction
  expectations.
- Gerrit artifact checksums and manifests are produced by the helper in the
  bundle factory environment and verified after staging to the Gerrit target.
- Gerrit artifact bundles contain no SSH key material, public-key handoff
  files, or `authorized_keys`; keypair generation and Gerrit public-key
  installation remain later integration-step work.
- Gerrit validation covers startup, endpoint reachability, LDAP access, SSH
  access, and plugin readiness. Jenkins integration account readiness,
  `Verified` grants, stream-events grants, and Gerrit-owned
  `All-Projects.git`/`All-Users.git` integration state are deferred to the
  later integration step.
- Gerrit service commands pass the shared Docker harness role gate without
  dummy, placeholder, operation-plan-only, or modeled success.
- Gerrit role-local evidence follows the Evidence Contract and includes
  bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Gerrit native operations remain helper-free and consistent with the role
  manual's OS, Gerrit, validation, backup, and recovery operations.

## Step 8: Create The Jenkins Controller Manual And Helper

Use the Jenkins controller helper and integration behavior summarized in
`docs/reference-digest.md`.

Create:

- `docs/jenkins-controller-setup-manual.md`
- `docs/jenkins-controller-native-operations-reference.md`
- `scripts/jenkins-controller-setup.sh`
- `examples/jenkins-controller.env.example`
- Jenkins controller templates under `templates/jenkins-controller/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Jenkins controller artifact and plugin preparation.
4. Jenkins installation.
5. Jenkins runtime configuration.
6. LDAP/JCasC configuration.
7. Deferred Gerrit Trigger base configuration.
8. Deferred Jenkins-to-Gerrit SSH key generation.
9. Deferred build-agent SSH key generation.
10. Deferred build-agent registration and scheduling validation.
11. Deferred end-to-end Gerrit Trigger verification.
12. Validation.
13. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-service
install-plugins
configure-jcasc
validate
collect-evidence
```

Implementation notes:

- Preserve the reference repo's useful Jenkins plugin and JCasC patterns.
- `docs/jenkins-controller-native-operations-reference.md` is the strong
  reference for direct OS and Jenkins controller operations. Keep it
  consistent with the controller manual and helper behavior, but never add
  repository helper commands to it.
- Treat plugin versions and checksums as curated artifacts.
- Jenkins controller defaults to the Version Baseline: Jenkins `2.555.3 LTS`,
  OpenJDK 21, and Jenkins Plugin Installation Manager Tool `2.15.0` on Ubuntu
  24.04.4 LTS `noble`.
- `prepare-artifacts` must run in the shared Docker harness bundle factory
  environment, and Jenkins controller target commands must consume only staged
  bundle factory output.
- Jenkins controller artifact bundles must be key-free. `prepare-artifacts`
  must not write Jenkins-to-Gerrit or Jenkins-to-agent private keys, public
  keys, `authorized_keys`, or generated key handoff files, and staged artifact
  verification must reject them before target mutation. Jenkins credentials,
  Gerrit Trigger server, agent-node, disposable verification job, and
  trigger-verification env templates are cross-role integration artifacts and
  must not be staged by the controller role helper.
- Jenkins controller manifests must record
  `artifact_source=curated-bundle-factory`,
  `os_dependency_source=approved-internal-os-repos`,
  `public_internet_fallback=simulation-only`, and `bundle_contains_keys=no`.
- Target-side manifests and checksums must be verified in the Jenkins
  controller target before install, plugin installation, or JCasC
  configuration mutates Jenkins state. Credential setup, node setup, and
  verification jobs belong to the shared integration helper after role-local
  readiness.
- Keep Jenkins admin and Jenkins Gerrit integration identities separate.
- In Step 8, the Jenkins controller helper proves controller-only bringup:
  real Jenkins startup, endpoint reachability, staged plugin installation,
  JCasC/LDAP configuration, runtime configuration, artifact freshness, bounded
  logs, and role-local evidence.
- Jenkins-to-Gerrit private key generation, Jenkins-to-agent private key
  generation, Jenkins build-agent registration, scheduling validation, Gerrit
  Trigger configuration, and end-to-end Gerrit Trigger verification are shared
  integration-helper outputs and must not be accepted as Step 8 outputs.
- Gerrit Trigger configuration and shared `verify-trigger` behavior must
  follow the Step 5 trigger integration contract when that later integration
  step is run.
- `install`, `configure-service`, `install-plugins`, `configure-jcasc`, and
  `validate` must be functional against the Jenkins controller target in the
  shared Docker harness. Cross-role integration commands must not be exposed by
  the Jenkins controller helper and must not create keypairs, Gerrit Trigger
  config, Jenkins nodes, scheduling records, or trigger/vote evidence during
  Step 8.
- Controller validation must pass real Jenkins runtime checks for the lifecycle
  phase it claims. It must not report local responder output,
  operation-plan-only output, modeled output, or `planned-checks-only` output
  as success.
- `collect-evidence` must emit role-local Jenkins controller checkpoint evidence
  using the Evidence Contract defined above.
- Do not run builds on the controller except for explicit simulation-only
  checks; production-like validation should use the Jenkins agent.

Verification:

```bash
bash -n scripts/jenkins-controller-setup.sh
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-controller-setup.sh print-env-template
scripts/jenkins-controller-setup.sh --env examples/jenkins-controller.env.example --dry-run preflight
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-controller
simulation/docker/docker-harness.sh stage-artifacts --role jenkins-controller
simulation/docker/docker-harness.sh run-role-gate --role jenkins-controller
find simulation/evidence/docker -type f -name '*jenkins-controller*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find simulation/evidence/docker -type f -name '*jenkins-controller*')
rg -n "bundle_contains_keys=no|os_dependency_source=approved-internal-os-repos|public_internet_fallback=simulation-only" simulation/state/docker/<run-id>/bundle-factory/artifacts/jenkins-controller/manifest.txt simulation/staging/docker/<run-id>/jenkins-controller/manifest.txt
! find simulation/state/docker/<run-id>/bundle-factory/artifacts/jenkins-controller simulation/staging/docker/<run-id>/jenkins-controller -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "JCasC|LDAP|Gerrit Trigger|prepare-artifacts|collect-evidence" docs/jenkins-controller-setup-manual.md scripts/jenkins-controller-setup.sh
! scripts/jenkins-controller-setup.sh --help | rg -n "generate-integration-key|generate-agent-key|configure-integration|configure-agent|validate-agent|verify-trigger"
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/jenkins-controller-setup-manual.md scripts/jenkins-controller-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes" docs/jenkins-controller-native-operations-reference.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, deferred integration credential
  boundaries, and secret-redaction expectations.
- Jenkins controller artifact bundles contain no SSH key material, public-key
  handoff files, or `authorized_keys`; Jenkins-to-Gerrit and Jenkins-to-agent
  keypair generation and public-key handoff remain later integration-step work.
- Jenkins controller validation covers startup, endpoint reachability, LDAP,
  plugins, JCasC, controller runtime configuration, artifact freshness, bounded
  logs, and role-local evidence.
- Gerrit SSH connectivity, Gerrit Trigger readiness, build-agent
  registration, agent scheduling, and Gerrit Trigger voting are deferred to
  the later integration step.
- Jenkins controller service commands pass the shared Docker harness role gate
  without dummy, placeholder, operation-plan-only, or modeled success.
- Jenkins controller role-local evidence follows the Evidence Contract and
  includes bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Jenkins controller native operations remain helper-free and consistent with
  the role manual's OS, Jenkins, plugin, JCasC, validation, backup, and
  recovery operations.

## Step 9: Create The Jenkins Agent Manual And Helper

Use the Jenkins agent helper behavior summarized in `docs/reference-digest.md`.

Create:

- `docs/jenkins-agent-setup-manual.md`
- `docs/jenkins-agent-native-operations-reference.md`
- `scripts/jenkins-agent-setup.sh`
- `examples/jenkins-agent.env.example`
- Jenkins agent templates under `templates/jenkins-agent/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated agent artifact preparation.
4. Agent host installation.
5. Agent runtime account and SSH setup.
6. Agent host validation.
7. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-runtime
validate
collect-evidence
```

Implementation notes:

- Jenkins connects out to the agent over SSH.
- `docs/jenkins-agent-native-operations-reference.md` is the strong reference
  for direct OS, OpenSSH, and Jenkins agent operations. Keep it consistent with
  the agent manual and helper behavior, but never add repository helper
  commands to it.
- The agent must have a dedicated runtime user and remote filesystem path.
- Jenkins agent defaults to the Version Baseline: Ubuntu 24.04.4 LTS `noble`,
  OpenJDK 21, SSH server/client tooling, and the Jenkins SSH Build Agents
  plugin from the controller plugin bundle.
- `prepare-artifacts` must run in the shared Docker harness bundle factory
  environment, and Jenkins agent target commands must consume only staged
  bundle factory output.
- Jenkins agent artifact bundles must be key-free. `prepare-artifacts` must
  not write Jenkins-to-agent public keys, private keys, `authorized_keys`, or
  generated key handoff files, and staged artifact verification must reject
  them before target mutation.
- Jenkins agent manifests must record `artifact_source=curated-bundle-factory`,
  `os_dependency_source=approved-internal-os-repos`,
  `public_internet_fallback=simulation-only`, and `bundle_contains_keys=no`.
- Target-side manifests and checksums must be verified in the Jenkins agent
  target before install or runtime configuration mutates the agent host.
- The agent helper configures only the agent host runtime and SSH service
  side; it must not write `authorized_keys`, register a Jenkins node, prove
  scheduling, configure Gerrit Trigger, or prove `Verified` voting.
- Jenkins controller node registration belongs to the shared integration
  helper after Jenkins controller and Jenkins agent role-only bringup are
  accepted.
- Step 9 is agent host-only bringup. Jenkins-to-agent key generation, public
  key transfer, runtime-account key installation, controller node
  registration, controller credential selection, node-name/label/executor
  policy, scheduling, validation jobs, and Gerrit Trigger execution are later
  integration-step outputs, not Step 9 acceptance outputs.
- The controller's built-in node should remain at zero executors in
  production-like docs.
- Agent validation must prove OS/tooling readiness, SSH daemon reachability,
  runtime account ownership, remote filesystem readiness, staged artifact
  checks, bounded logs, and role-local evidence. Jenkins node name and labels
  are handoff metadata only in the agent role. Jenkins controller key handoff,
  node registration, and controller-side scheduling proof are deferred to the
  later integration step.
- `install`, `configure-runtime`, and `validate` must be functional against the
  Jenkins agent target in the shared Docker harness.
- Agent validation must pass real SSH daemon and filesystem readiness checks,
  not operation-plan-only or `planned-checks-only` output.
- `collect-evidence` must emit role-local Jenkins agent checkpoint evidence
  using the Evidence Contract defined above.

Verification:

```bash
bash -n scripts/jenkins-agent-setup.sh
scripts/jenkins-agent-setup.sh --help
scripts/jenkins-agent-setup.sh print-env-template
scripts/jenkins-agent-setup.sh --env examples/jenkins-agent.env.example --dry-run preflight
simulation/docker/docker-harness.sh prepare-artifacts --role jenkins-agent
simulation/docker/docker-harness.sh stage-artifacts --role jenkins-agent
simulation/docker/docker-harness.sh run-role-gate --role jenkins-agent
find simulation/evidence/docker -type f -name '*jenkins-agent*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find simulation/evidence/docker -type f -name '*jenkins-agent*')
rg -n "agent|SSH|label|executor|collect-evidence" docs/jenkins-agent-setup-manual.md scripts/jenkins-agent-setup.sh
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/jenkins-agent-setup-manual.md scripts/jenkins-agent-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes|configure-" docs/jenkins-agent-native-operations-reference.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, host-only readiness checks, and
  secret-redaction expectations.
- Jenkins agent artifact bundles contain no SSH key material, public-key
  handoff files, or `authorized_keys`; Jenkins-to-agent keypair generation and
  public-key handoff remain later integration-step work.
- Agent validation covers OS/tooling readiness, SSH daemon reachability, remote
  filesystem readiness, runtime account ownership, staged artifact checks,
  bounded logs, and role-local evidence.
- Agent service commands pass the shared Docker harness role gate without
  dummy, placeholder, operation-plan-only, or modeled success.
- Jenkins agent role-local evidence follows the Evidence Contract and includes
  bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Jenkins agent native operations remain helper-free and consistent with the
  role manual's OS, OpenSSH, host-only validation, backup, and recovery
  operations.

## Step 10: Standardize Validation And Evidence Collection

Create `docs/validation-and-evidence.md` and `scripts/collect-evidence.sh`.
This step documents the Evidence Contract for operators and implements global
evidence aggregation over role-local and verifier-produced records.

The operator-facing evidence model must cover:

- Verification mode.
- Timestamp, package version, and helper command version or git commit.
- Role or environment name.
- Checkpoint and command names.
- Pass, fail, blocked, unsupported, or not-applicable status.
- Hostnames and service endpoints.
- Sanitized config input manifest.
- Artifact manifest and checksums.
- Service startup, endpoint, LDAP, SSH, plugin, JCasC, and runtime-account
  checks where applicable.
- Jenkins agent scheduling and execution results where applicable.
- Gerrit Trigger event, build, and `Verified` vote results where applicable.
- Bounded log references.
- Redaction status.

Implementation notes:

- Role-local `collect-evidence` commands from Steps 7, 8, and 9 produce
  role-scoped records using the Evidence Contract.
- `scripts/collect-evidence.sh` validates and aggregates role-local records,
  Docker/VM verifier records, and end-to-end integration records into the final
  evidence package.
- Do not store secrets in evidence.
- Do not stream verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, or
  verification logs into normal command output.
- Collect evidence at every operator workflow checkpoint so failed runs can be
  reviewed from the last completed boundary.
- Summaries must distinguish simulation-only runs from production-like runs.
- Evidence should be useful for audit review without requiring repo history.

Verification:

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|production-like|checksums|Verified|LDAP|agent" docs/validation-and-evidence.md scripts/collect-evidence.sh
```

Acceptance criteria:

- Global evidence collection can be run after role-specific validation and after
  full integration validation.
- Global evidence collection consumes role-local evidence from Gerrit, Jenkins
  controller, and Jenkins agent helpers, plus Docker/VM verifier evidence when
  present.
- Evidence collection can retain per-checkpoint summaries for inputs,
  artifacts, artifact staging, role readiness, integration, agent validation,
  end-to-end acceptance, and final evidence.
- Evidence summaries follow the Evidence Contract and include mode labels,
  checksum references, bounded log references, and redaction status.
- Secret-looking env values are omitted or redacted.

## Step 11: Build Docker Simulation

Use the Docker simulation behavior summarized in `docs/reference-digest.md`.

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
simulation/docker/docker-harness.sh [--env FILE] preflight
simulation/docker/docker-harness.sh [--env FILE] render-config
simulation/docker/docker-harness.sh [--env FILE] status
simulation/docker/docker-harness.sh [--env FILE] prepare-artifacts
simulation/docker/docker-harness.sh [--env FILE] stage-artifacts
simulation/docker/docker-harness.sh [--env FILE] up
simulation/docker/docker-harness.sh [--env FILE] check
simulation/docker/docker-harness.sh [--env FILE] full-verify
simulation/docker/docker-harness.sh [--env FILE] down
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
- `docker-harness.sh prepare-artifacts` runs role helper
  `prepare-artifacts` commands inside the bundle factory container. Do not add
  a `bundle-factory-helper.sh`.
- `docker-harness.sh stage-artifacts` stages prepared role artifacts from bundle
  factory output to the Gerrit, Jenkins controller, and Jenkins agent
  containers, then verifies manifests and checksums on the target side before
  service mutation.
- `docker-harness.sh check` is an independently repeatable readiness gate
  before `docker-harness.sh full-verify`.
- `docker-harness.sh check` must invoke `scripts/integration-setup.sh
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
- Docker logs must be written to bounded log files, not streamed verbosely into
  normal operator output.
- Any internet use during Docker artifact preparation or fallback must be
  labeled simulation-only.
- Generated local state must be ignored or clearly documented as generated.

Verification:

```bash
bash -n simulation/docker/docker-harness.sh
simulation/docker/docker-harness.sh --help
simulation/docker/docker-harness.sh preflight
simulation/docker/docker-harness.sh render-config
simulation/docker/docker-harness.sh status
simulation/docker/docker-harness.sh prepare-artifacts
simulation/docker/docker-harness.sh stage-artifacts
simulation/docker/docker-harness.sh up
simulation/docker/docker-harness.sh check
simulation/docker/docker-harness.sh full-verify
```

Acceptance criteria:

- Docker simulation starts all five machines, including the bundle factory
  container.
- Prepared artifacts, manifests, and checksums are produced by the bundle
  factory and verified after staging to service containers.
- Docker simulation uses the role helpers' functional install, configuration,
  validation, and role-local evidence commands, then uses
  `scripts/integration-setup.sh` for cross-role integration, agent scheduling,
  trigger verification, and integration evidence instead of reimplementing or
  modeling that behavior inside `docker-harness.sh`.
- LDAP, local OS runtime account, Gerrit HTTP/SSH, Jenkins HTTP/LDAP/JCasC/plugin,
  Jenkins-to-Gerrit SSH, stream-events, and Jenkins agent readiness checks pass
  with separate evidence.
- Full verification separately proves Gerrit event receipt, Jenkins job
  scheduling, agent execution, and Gerrit `Verified +1` vote posting.
- Verification writes a summary that labels the mode as Docker simulation.
- A successful full verification summary does not use modeled pass results for
  required runtime outcomes and must include proof from the real Gerrit,
  Jenkins controller, and Jenkins agent services.

## Step 12: Add VM Verification Scaffold

Step 12 is not a real VM implementation. VM infrastructure is not available by
default, so this step creates only the non-mutating verifier scaffold needed to
document and gate future VM work.

Use the VM simulation behavior summarized in `docs/reference-digest.md` as the
future command contract, but do not claim that real VM provisioning,
configuration, or end-to-end verification is implemented in this step.

Create scaffold assets under `simulation/vm/` after Docker verification is
stable.

Expected command surface:

```text
simulation/vm/vm-verify.sh create
simulation/vm/vm-verify.sh bootstrap
simulation/vm/vm-verify.sh prepare-artifacts
simulation/vm/vm-verify.sh stage-artifacts
simulation/vm/vm-verify.sh configure
simulation/vm/vm-verify.sh check
simulation/vm/vm-verify.sh execute
simulation/vm/vm-verify.sh audit
simulation/vm/vm-verify.sh full
```

Implementation notes:

- The scaffold must implement command dispatch, `--help`, env parsing,
  `--preflight-only`, approval guardrails, bounded-log references, and evidence
  record structure.
- The scaffold must parse and report Version Baseline inputs. It must not claim
  VM readiness or comparable verification when requested VM inputs differ from
  the baseline.
- Non-preflight commands that would create VMs, transfer files, mutate remote
  hosts, configure services, or run verification must exit nonzero with a clear
  blocked or unsupported status unless real VM infrastructure support is added
  in the future Step 15.
- The future real VM model should use separate bundle factory, LDAP, Gerrit,
  Jenkins controller, and Jenkins agent VMs.
- Future VM `prepare-artifacts` will run role helper artifact preparation on
  the bundle factory VM and record manifests, checksums, and any
  `simulation-only` internet-use labels.
- Future VM `stage-artifacts` will transfer prepared artifacts to service VMs
  and verify manifests and checksums on each target VM before install or
  configuration.
- VM verification must use the Step 10 evidence model for scaffold,
  production-like, or simulation mode labels.
- VM verification must use the same version combination as the Docker harness
  and Docker simulation: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, Gerrit
  `3.13.6`, Jenkins `2.555.3 LTS`, Jenkins Plugin Installation Manager Tool
  `2.15.0`, and the Jenkins SSH Build Agents plugin from the controller plugin
  bundle.
- The future VM model is production-like validation, not strict air-gap
  verification.
- The VM scaffold must reference `scripts/integration-setup.sh` as the future
  cross-role SSH, trigger, validation, verification, and integration-evidence
  surface. It must fail closed until VM support exists.
- Remove or rename reference workflow concepts that imply supported offline
  Ubuntu dependency bundles.
- VM commands that mutate remote or host state require explicit operator
  approval and must describe expected side effects. In Step 12 they must not
  perform those mutations by default.

Verification:

```bash
bash -n simulation/vm/vm-verify.sh
simulation/vm/vm-verify.sh --help
simulation/vm/vm-verify.sh check --preflight-only --env simulation/vm/example.env
simulation/vm/vm-verify.sh full --preflight-only --env simulation/vm/example.env
```

Acceptance criteria:

- VM preflight can validate local host tooling, env shape, approval flags, and
  target address syntax without mutating host or remote state.
- The scaffold makes real VM lifecycle commands visible but blocks them with
  clear nonzero statuses when real VM infrastructure support is absent.
- Evidence labels the mode as VM scaffold/preflight and does not imply that VM
  artifact preparation, service configuration, or end-to-end verification ran.
- VM scaffold evidence records the requested Version Baseline values and blocks
  non-matching VM verification inputs.
- Real VM artifact preparation, staging, configuration, and full verification
  are deferred to Step 15 and skipped in the current default plan.

## Step 13: Add Cross-Repository Boundary Checks

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

## Step 14: Final End-To-End Acceptance

Run final acceptance in this order:

1. Static docs and shell checks.
2. Helper `--help`, `print-env-template`, and `--dry-run preflight` checks.
3. Docker simulation preflight and setup phases through `docker-harness.sh`.
4. Docker full verification through `docker-harness.sh`.
5. Global evidence aggregation.
6. VM scaffold preflight-only checks.
7. Real VM implementation and verification from Step 15 is skipped for the
   current default plan.

Retained rendered inputs, prepared artifacts, staged artifacts, and harness
state may be reused only when manifests and checksums verify against the current
reviewed inputs and implementation commit. If reusable state is absent or
invalid, rerun rendering, artifact preparation, and artifact staging before
Docker verification.

Minimum command set:

```bash
bash -n scripts/*.sh simulation/docker/docker-harness.sh simulation/vm/*.sh
scripts/gerrit-setup.sh --help
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-agent-setup.sh --help
scripts/integration-setup.sh --help
scripts/collect-evidence.sh --help
simulation/docker/docker-harness.sh preflight
simulation/docker/docker-harness.sh render-config
simulation/docker/docker-harness.sh prepare-artifacts
simulation/docker/docker-harness.sh stage-artifacts
simulation/docker/docker-harness.sh up
simulation/docker/docker-harness.sh check
simulation/docker/docker-harness.sh full-verify
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes validate-integration
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes verify-trigger
scripts/collect-evidence.sh
simulation/docker/docker-harness.sh down
simulation/vm/vm-verify.sh --help
simulation/vm/vm-verify.sh check --preflight-only --env simulation/vm/example.env
simulation/vm/vm-verify.sh full --preflight-only --env simulation/vm/example.env
```

Final acceptance criteria:

- A new operator can follow the docs without repo history.
- Gerrit, Jenkins controller, and Jenkins agent have manual and helper flows.
- LDAP-backed identity assumptions are documented and simulated.
- Jenkins can schedule a job on the agent.
- Jenkins posts `Verified +1` back to Gerrit through the Gerrit REST review
  API.
- Validation artifacts are produced and retained for review.
- The package does not claim strict air-gapped support in v1.
- The package does not support offline Ubuntu dependency bundles in v1.
- Step 12 VM scaffold checks pass without claiming real VM implementation or
  real VM end-to-end verification.
- Step 15 real VM implementation and verification is documented as skipped for
  now.

## Step 15: Future Real VM Implementation And Verification

Step 15 is future work and must be skipped in the current default plan. It
exists to preserve the intended production-like VM verification path without
claiming that the repository implements it now.

When explicitly scheduled later, Step 15 should implement the real VM behavior
behind the Step 12 scaffold:

- Provision or identify separate bundle factory, LDAP, Gerrit, Jenkins
  controller, and Jenkins agent VMs.
- Verify that every VM matches the Version Baseline before artifact
  preparation, staging, service configuration, or end-to-end verification.
- Run role helper artifact preparation on the bundle factory VM.
- Stage prepared artifacts to service VMs and verify target-side manifests and
  checksums before service mutation.
- Configure LDAP, Gerrit, Jenkins controller, and Jenkins agent with
  systemd-oriented service behavior.
- Run readiness checks for host tooling, env values, SSH reachability, target
  addresses, service state, runtime accounts, LDAP, endpoints,
  Gerrit/Jenkins integration, and agent readiness.
- Run the Docker-proven Gerrit Trigger, Jenkins scheduling, agent execution,
  and `Verified +1` vote flow.
- Collect and aggregate production-like or VM simulation evidence using the
  Step 10 evidence model.
- Record the Version Baseline in VM evidence and fail or block the run when the
  VM version combination differs.

Skip rule:

- Do not run Step 15 as part of current default acceptance.
- Do not claim real VM implementation, real VM readiness, or real VM
  end-to-end verification until Step 15 is explicitly implemented and run in an
  approved VM environment.

## Commit Strategy

Keep commits small and logical:

1. Add repository structure and implementation plan.
2. Add account model.
3. Add simulation model docs.
4. Add operator workflow contract.
5. Add Gerrit Trigger integration contract.
6. Add shared Docker harness.
7. Add Gerrit manual/helper/templates.
8. Add Jenkins controller manual/helper/templates.
9. Add Jenkins agent manual/helper/templates.
10. Add validation and evidence collection.
11. Add Docker simulation.
12. Add VM verification scaffold.
13. Add boundary checks.
14. Add final acceptance docs.
15. Document future real VM implementation.

Use standard Git-style commit messages with concise imperative subjects, for
example:

```text
Add Gerrit setup helper
Add Docker role gate harness
Add Docker simulation verification
Document validation evidence
```
