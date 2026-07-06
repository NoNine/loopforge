# Gerrit/Jenkins Setup Package Implementation Plan

## Purpose

This document is the active implementation roadmap for building the v1
Gerrit/Jenkins setup package described in `docs/prd.md`. It is not the stable
product authority; use `docs/docs-management.md` to resolve the owning
authority for current product facts.

The behavior digest is `docs/references/reference-digest.md`. That digest
summarizes the known-working draft repository behavior without allowing
implementation agents to copy code, docs, templates, scripts, config files,
command bodies, or verbatim implementation from
`/home/ubuntu/ai-assisted/gerrit-jenkins`.

Implementation agents must use `docs/references/reference-digest.md`,
`docs/prd.md`, the role native-operations references, and this plan as their
reference set. Do not open or copy from the draft repository unless a human
explicitly approves a new reference review.

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

`docs/version-baseline.md` owns the default v1 version baseline and update
rules. Implementation steps below must keep helpers, Docker harnesses, Docker
simulation, VM simulation scaffolds, future real VM verification, tests, and
evidence expectations aligned with that baseline.

## Evidence Contract

`docs/validation-and-evidence.md` owns the evidence schema, mode labels,
redaction rules, producer responsibilities, and global aggregation behavior.
Implementation steps below should add producers and verification commands that
emit records conforming to that topic document instead of redefining evidence
fields here.

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
  references/reference-digest.md
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
- `simulation/vm/` contains the later target-deployment verification model.
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

Create and maintain `docs/account-model.md` as the account authority for v1.
The implementation plan must not duplicate the account taxonomy, source
classification, credential custody rules, or separation rules.

Implementation notes:

- Topic docs, examples, templates, and helpers must use the account roles and
  custody boundaries from `docs/account-model.md`.
- `docs/system-model.md` may place accounts in the end-to-end system, but
  `docs/account-model.md` owns account definitions and separation rules.
- Keep examples account-name neutral where possible.

Verification:

```bash
rg -n "runtime|admin|integration|test user|LDAP|bind" docs/account-model.md
rg -n "air-gapped|offline bundle|offline-bundle" docs/account-model.md
```

Acceptance criteria:

- `docs/account-model.md` defines product accounts, the shared integration
  group, the simulation environment account, and credential custody.
- Topic docs reference the account model instead of restating the full
  taxonomy.
- Any offline-related match is reference-only, non-goal, or prohibition text.

## Step 3: Define The Simulation Model

Create the simulation model docs without duplicating the system, account,
source-boundary, or evidence authorities.

Step 3-owned files:

```text
simulation/README.md
simulation/docker/README.md
simulation/vm/README.md
```

Implementation notes:

- `simulation/README.md` owns the common five-environment topology, version
  baseline, source boundaries, generated-output conventions, and checkpoint
  meanings for simulation layers.
- `simulation/docker/README.md` owns Docker simulation command behavior and
  Docker-specific generated paths.
- `simulation/vm/README.md` owns VM simulation and future VM command
  behavior.
- The simulation docs must derive account usage from `docs/account-model.md`
  and mode terminology from `docs/system-model.md`.
- The bundle factory remains an environment, not a public helper API.
  Artifact preparation stays exposed through role helpers' `prepare-artifacts`
  commands.
- Do not port the reference repo's supported offline Ubuntu dependency bundle
  workflow into v1 simulation.

Verification:

```bash
test -f simulation/README.md
test -f simulation/docker/README.md
test -f simulation/vm/README.md
rg -n "bundle factory|LDAP|Gerrit|Jenkins controller|Jenkins agent|ci-operator" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "docker-simulation|vm-simulation|target-deployment|simulation-only" simulation/README.md simulation/docker/README.md simulation/vm/README.md
rg -n "supported offline|offline Ubuntu|offline-bundle" simulation/README.md simulation/docker/README.md simulation/vm/README.md
```

Acceptance criteria:

- Simulation docs describe the shared topology and point to the account,
  system-model, source-boundary, and evidence authorities instead of redefining
  them.
- Docker is documented as the first full integration verification gate, and VM
  verification is documented as later work.
- Generated state, staged artifacts, evidence, and bounded logs are documented
  as generated output.
- No bundle factory helper or offline Ubuntu dependency bundle workflow is
  introduced.

## Step 4: Define The Operator Workflow Contract

Durable lifecycle behavior now lives in `docs/lifecycle-contract.md`. Keep
this implementation step as historical context only. Future changes to phase
order, checkpoint semantics, mutation boundaries, resume/rerun behavior, or
Docker command mapping belong in the lifecycle contract, not in this plan.

The cross-role command sequence belongs in `docs/integration-setup-manual.md`.
Gerrit Trigger, ACL, label, vote, and failure-classification behavior belongs
in `docs/gerrit-trigger-integration.md`. Account and credential custody
belongs in `docs/account-model.md`.

Verification:

```bash
test -f docs/lifecycle-contract.md
rg -n "Operator Workflow Contract|Lifecycle Checkpoints|Docker Command Mapping" docs/lifecycle-contract.md
rg -n "lifecycle-contract.md" docs/docs-management.md docs/system-model.md simulation/docker/README.md
rg -n "^[[:space:]]*(run|configure-controller-node)$" docs/implementation-plan.md
```

Acceptance criteria:

- The stable workflow contract is in `docs/lifecycle-contract.md`.
- This implementation plan does not embed the durable lifecycle authority.
- Consumer docs link to the lifecycle contract instead of redefining shared
  checkpoint semantics.

## Step 5: Define Gerrit Trigger Integration

Use the trigger behavior summarized in `docs/references/reference-digest.md` as source
material, and make `docs/gerrit-trigger-integration.md` the topic authority
for Gerrit Trigger, ACL, label, vote, and failure-classification behavior.

Create `docs/gerrit-trigger-integration.md` and templates for:

- Gerrit `Verified` label definition.
- Gerrit access permissions for the Jenkins integration actor.
- Jenkins Gerrit Trigger server configuration.
- Disposable Jenkins verification job.
- Disposable Gerrit verification project/change.

Implementation notes:

- Keep detailed ACL, `All-Projects`, `Verified`, `stream-events`, REST vote,
  disposable artifact, and failure-classification policy in
  `docs/gerrit-trigger-integration.md`, not in this implementation plan.
- Templates must remain placeholders for reviewed operator values and must not
  become standalone automation.
- Cross-role helper command workflow belongs in `docs/integration-setup-manual.md`.

Verification:

```bash
rg -n "Verified|Gerrit Trigger|stream-events|patchset-created|integration" docs/gerrit-trigger-integration.md templates scripts simulation
```

Acceptance criteria:

- The trigger topic doc defines the integration contract and Docker simulation
  acceptance behavior.
- This implementation plan does not duplicate the topic doc's ACL or voting
  policy.

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
- Use `docs/version-baseline.md` for the bundle factory, Gerrit target,
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
simulation/docker/simulate.sh up
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
simulation/docker/simulate.sh down
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
simulation/docker/simulate.sh up
! simulation/docker/simulate.sh prepare-artifacts --role unknown
! simulation/docker/simulate.sh configure-role --role gerrit
! simulation/docker/simulate.sh validate-role --role gerrit
simulation/docker/simulate.sh down
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
`docs/references/reference-digest.md`.

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
- Gerrit manifests must record compact artifact identity and inventory fields
  only; policy and source-boundary facts belong in docs, logs, and evidence.
- Gerrit defaults to `docs/version-baseline.md`. Non-default Gerrit versions
  may be used only after a reviewed baseline update.
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
simulation/docker/simulate.sh prepare-artifacts --role gerrit
simulation/docker/simulate.sh stage-artifacts --role gerrit
simulation/docker/simulate.sh configure-role --role gerrit
simulation/docker/simulate.sh validate-role --role gerrit
find generated/simulation/docker/<run-id>/target/evidence/gerrit -type f -name '*gerrit*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/gerrit -type f -name '*gerrit*')
rg -n "bundle_name=gerrit-artifacts-bundle|war=gerrit-3.13.6.war" generated/simulation/docker/<run-id>/target/artifacts/exported/gerrit/manifest.txt generated/simulation/docker/<run-id>/target/artifacts/staging/gerrit/manifest.txt
! find generated/simulation/docker/<run-id>/target/artifacts/exported/gerrit generated/simulation/docker/<run-id>/target/artifacts/staging/gerrit -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "prepare-artifacts|collect-evidence" docs/gerrit-setup-manual.md scripts/gerrit-setup.sh
! scripts/gerrit-setup.sh --help | rg -n "configure-integration|prove-integration|configure-agent"
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
`docs/references/reference-digest.md`.

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
- Jenkins controller defaults to `docs/version-baseline.md`.
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
- Jenkins controller manifests must record compact artifact identity and
  inventory fields only; policy and source-boundary facts belong in docs, logs,
  and evidence.
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
- Gerrit Trigger configuration and shared `prove-integration` behavior must
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
  checks; target-deployment validation should use the Jenkins agent.

Verification:

```bash
bash -n scripts/jenkins-controller-setup.sh
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-controller-setup.sh print-env-template
scripts/jenkins-controller-setup.sh --env examples/jenkins-controller.env.example --dry-run preflight
simulation/docker/simulate.sh prepare-artifacts --role jenkins-controller
simulation/docker/simulate.sh stage-artifacts --role jenkins-controller
simulation/docker/simulate.sh configure-role --role jenkins-controller
simulation/docker/simulate.sh validate-role --role jenkins-controller
find generated/simulation/docker/<run-id>/target/evidence/jenkins-controller -type f -name '*jenkins-controller*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/jenkins-controller -type f -name '*jenkins-controller*')
rg -n "bundle_name=jenkins-artifacts-bundle|war=jenkins-2.555.3.war" generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-controller/manifest.txt generated/simulation/docker/<run-id>/target/artifacts/staging/jenkins-controller/manifest.txt
! find generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-controller generated/simulation/docker/<run-id>/target/artifacts/staging/jenkins-controller -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "JCasC|LDAP|Gerrit Trigger|prepare-artifacts|collect-evidence" docs/jenkins-controller-setup-manual.md scripts/jenkins-controller-setup.sh
! scripts/jenkins-controller-setup.sh --help | rg -n "generate-integration-key|generate-agent-key|configure-integration|configure-agent|validate-agent|prove-integration"
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

Use the Jenkins agent helper behavior summarized in `docs/references/reference-digest.md`.

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
- Jenkins agent defaults to `docs/version-baseline.md`.
- `prepare-artifacts` must run in the shared Docker harness bundle factory
  environment, and Jenkins agent target commands must consume only staged
  bundle factory output.
- Jenkins agent artifact bundles must be key-free. `prepare-artifacts` must
  not write Jenkins-to-agent public keys, private keys, `authorized_keys`, or
  generated key handoff files, and staged artifact verification must reject
  them before target mutation.
- Jenkins agent manifests must record compact artifact identity and inventory
  fields only; policy and source-boundary facts belong in docs, logs, and
  evidence.
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
  target-deployment docs.
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
simulation/docker/simulate.sh prepare-artifacts --role jenkins-agent
simulation/docker/simulate.sh stage-artifacts --role jenkins-agent
simulation/docker/simulate.sh configure-role --role jenkins-agent
simulation/docker/simulate.sh validate-role --role jenkins-agent
find generated/simulation/docker/<run-id>/target/evidence/jenkins-agent -type f -name '*jenkins-agent*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/jenkins-agent -type f -name '*jenkins-agent*')
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
The topic doc owns evidence schema, mode labels, redaction rules, producer
responsibilities, review guidance, and aggregation behavior.

Implementation notes:

- Role-local `collect-evidence` commands from Steps 7, 8, and 9 must emit
  records that conform to `docs/validation-and-evidence.md`.
- `scripts/collect-evidence.sh` validates and aggregates role-local records,
  Docker/VM simulation utility records, and end-to-end integration records into
  the final evidence package.
- Do not store secrets in evidence.
- Do not stream verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, or
  verification logs into normal command output.

Verification:

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|target-deployment|checksums|Verified|LDAP|agent" docs/validation-and-evidence.md scripts/collect-evidence.sh
```

Acceptance criteria:

- Global evidence collection can be run after role-specific validation and after
  full integration validation.
- Global evidence collection consumes role-local evidence from Gerrit, Jenkins
  controller, and Jenkins agent helpers, plus Docker/VM simulation utility
  evidence when present.
- Evidence summaries follow `docs/validation-and-evidence.md` and omit or
  redact secret-looking values.

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

## Step 12: Add VM Verification Scaffold

Step 12 is not a real VM implementation. VM infrastructure is not available by
default, so this step creates only the non-mutating verifier scaffold needed to
document and gate future VM work.

Use the VM simulation behavior summarized in
`docs/references/reference-digest.md` as the future command contract, but do
not claim that real VM provisioning, configuration, or end-to-end verification
is implemented in this step.

Create scaffold assets under `simulation/vm/` after Docker verification is
stable.

Expected command surface:

```text
simulation/vm/simulate.sh run
simulation/vm/simulate.sh preflight
simulation/vm/simulate.sh init-run
simulation/vm/simulate.sh create
simulation/vm/simulate.sh up
simulation/vm/simulate.sh status
simulation/vm/simulate.sh ssh
simulation/vm/simulate.sh prepare-artifacts
simulation/vm/simulate.sh stage-artifacts
simulation/vm/simulate.sh configure-role
simulation/vm/simulate.sh validate-role
simulation/vm/simulate.sh configure-integration
simulation/vm/simulate.sh validate-integration
simulation/vm/simulate.sh prove-integration
simulation/vm/simulate.sh reboot
simulation/vm/simulate.sh audit-state
simulation/vm/simulate.sh down
simulation/vm/simulate.sh clean
simulation/vm/simulate.sh destroy
```

Implementation notes:

- The scaffold must implement command dispatch, `--help`, env parsing,
  `preflight`, approval guardrails, bounded-log references, and evidence record
  structure.
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
  target-deployment, or simulation mode labels.
- VM verification must use the same reviewed baseline as the Docker harness
  and Docker simulation.
- The future VM model is target-deployment validation, not strict air-gap
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
bash -n simulation/vm/simulate.sh
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/example.env
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
3. Docker simulation preflight and setup phases through `simulate.sh`.
4. Docker full verification through `simulate.sh`.
5. Global evidence aggregation.
6. VM scaffold preflight checks.
7. Real VM implementation and verification from Step 15 is skipped for the
   current default plan.

Retained rendered inputs, prepared artifacts, staged artifacts, and harness
state may be reused only when manifests and checksums verify against the current
reviewed inputs and implementation commit. If reusable state is absent or
invalid, rerun rendering, artifact preparation, and artifact staging before
Docker verification.

Minimum command set:

```bash
bash -n scripts/*.sh simulation/docker/simulate.sh simulation/vm/*.sh
scripts/gerrit-setup.sh --help
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-agent-setup.sh --help
scripts/integration-setup.sh --help
scripts/collect-evidence.sh --help
simulation/docker/simulate.sh preflight
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh prepare-artifacts
simulation/docker/simulate.sh stage-artifacts
simulation/docker/simulate.sh up
simulation/docker/simulate.sh configure-role
simulation/docker/simulate.sh validate-role
simulation/docker/simulate.sh configure-integration
simulation/docker/simulate.sh validate-integration
simulation/docker/simulate.sh prove-integration
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes validate-integration
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes prove-integration
scripts/collect-evidence.sh
simulation/docker/simulate.sh down
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/example.env
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
exists to preserve the intended target-deployment VM verification path without
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
- Collect and aggregate target-deployment or VM simulation evidence using the
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
