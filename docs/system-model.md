# Loopforge System Model

## Purpose And Authority

This document models Loopforge's initial experiment environment. The initial
environment constructs and verifies a Gerrit/Jenkins integration stack with
LDAP-backed identity assumptions, a Jenkins SSH build agent, Gerrit Trigger,
`Verified` voting, and evidence collection. This model defines the
environments, actors, accounts, utilities, services, interfaces, lifecycle
boundaries, deployment modes, and evidence relationships used by Loopforge. It
is not a command transcript.

`docs/prd.md` remains the product scope authority. This system model sits below
the PRD and above topic-specific docs, operator manuals, simulation docs, and
helper script implementations. Topic-specific docs provide details inside the
boundaries defined here.

Authority order:

1. `docs/prd.md`: product scope, goals, non-goals, and acceptance criteria.
2. `docs/system-model.md`: system entities, relationships, interfaces, modes,
   lifecycle boundaries, and ownership rules.
3. Topic docs and manuals, including `docs/account-model.md`,
   `docs/directory-model.md`, `docs/artifact-bundle-contract.md`,
   `docs/validation-and-evidence.md`, `docs/gerrit-trigger-integration.md`,
   role setup manuals, and simulation docs.
4. Helper scripts and verifier scripts, which implement the documented model.

If this model exposes a new product requirement or changes the product
boundary, update `docs/prd.md` explicitly instead of carrying the requirement
only here.

## Deployment Modes

Every setup or verification run has one mode. Modes describe the environment
class and policy choices. They do not change the logical system being modeled.

| Mode | Meaning |
| --- | --- |
| `docker-simulation` | Non-production containerized simulation. Uses simulation-owned hosts, accounts, LDAP data, and secrets. The bundle factory is a container. |
| `vm-simulation` | Non-production VM simulation. Uses simulation-owned VMs, accounts, LDAP data, and secrets. The bundle factory is a VM. |
| `target-deployment` | Real controlled target deployment or acceptance environment. May run on physical hosts or managed VMs. Uses operator-approved hosts, accounts, LDAP, secrets, package sources, review approvals, and evidence custody. |

`target-deployment` is distinguished from simulation modes by the use of
operator-approved target infrastructure and real or approved target-owned
identity sources, not by whether the hosts are physical machines or VMs.

## Product Behavior Modeling

Product behavior should be modeled as early as practical and as much as
practical. New or changed behavior should document the intended
`target-deployment` behavior, simulation realization, ownership boundaries,
interfaces, lifecycle checkpoints, and evidence limits before or alongside
implementation.

Simulation modes model the same logical product behavior as target deployment.
Simulation-specific mechanisms may create, host, or observe the lab
environment, but they must not replace normal product lifecycle operations.
Simulation must not bypass role helpers, shared integration helper ownership,
staged artifact verification, native product paths, declared service APIs,
runtime accounts, or real runtime and evidence checks to manufacture success.

Any simulation-only waiver must be narrow, explicit, opt-in, clearly labeled in
docs, logs, and evidence, and fail closed outside simulation modes. Waivers may
explain a lab limitation, but they do not become a supported product path and
must not be presented as `target-deployment` proof.

## Helper-Owned Generated State

Helper-owned generated execution state is separate from service-owned product
homes. Helper state holds rendered inputs, runtime inputs, staging handoff,
evidence inputs, bounded logs, and related helper-managed state. Service-owned
state remains under the native Gerrit, Jenkins controller, and Jenkins agent
homes.

The helper-owned paths are not service homes. They are the workspace used by
helper scripts and integration workflows to prepare, stage, validate, and
record execution state. `docs/directory-model.md` defines the concrete paths,
ownership, permission model, sensitivity, evidence behavior, and simulation
backing rules.

## Actors

Actors are entities that intentionally invoke package utilities or external
administrative tools. Actors are separate from accounts, services, utilities,
and environments.

| Actor | Responsibility |
| --- | --- |
| Human operator | Reviews inputs, invokes package commands, coordinates setup phases, reviews summaries and evidence. |
| Human Gerrit administrator | Reviews and submits Gerrit configuration changes when the selected mode requires an approval boundary. |
| Human Jenkins administrator | Reviews or approves Jenkins administrative changes when site policy requires a Jenkins approval boundary. |
| Machine runner | Invokes package utilities noninteractively in CI or orchestration. It may run simulation or target-deployment flows, but external approval boundaries still apply. |

Non-actors include helper scripts, harnesses, verifiers, evidence collectors,
Gerrit, Jenkins, LDAP, SSH daemons, runtime accounts, service accounts, and
generated jobs. Those are modeled as utilities, services, accounts, or runtime
state.

Actors invoke utilities. Utilities use accounts and service APIs to inspect or
mutate environments. Services authenticate accounts and produce runtime state.
Evidence records prove lifecycle checkpoints without exposing secrets.

## Logical Environments

The setup system has these logical environments. Docker, VM, and target
deployment modes realize them differently, but the logical responsibilities
remain stable.

| Environment | Responsibility |
| --- | --- |
| Operator workstation or control node | Holds reviewed input files, invokes utilities, receives short summaries, and collects generated evidence references. It is not a Gerrit/Jenkins runtime target. |
| Bundle factory | Loopforge preparation environment that produces reviewed, version-pinned application artifacts, manifests, checksums, and source-boundary records before target-host mutation. |
| LDAP environment | Provides LDAP-backed users, groups, and bind/search behavior for Gerrit and Jenkins. |
| Gerrit target | Runs Gerrit, stores Gerrit configuration, exposes Gerrit HTTP and Gerrit SSH service endpoints, and records reviews/votes. |
| Jenkins controller target | Runs Jenkins, owns Jenkins-held integration private keys, stores Jenkins credentials and jobs, configures Gerrit Trigger, and schedules builds. |
| Jenkins agent target | Runs the SSH build-agent environment and owns build workspaces and agent-side runtime filesystem state. |

The bundle factory is not a Gerrit/Jenkins runtime service. It prepares
artifacts and proof inputs; target environments install from staged artifacts.
In simulation modes, the bundle factory is always part of the simulation and
is realized as a container or VM. In `target-deployment`, the bundle factory is
a controlled artifact preparation environment, such as a staging machine,
release pipeline, or managed VM. It remains logically separate from
target-host installation even when infrastructure is co-located.

In `target-deployment`, LDAP may be real external LDAP or an approved
target-owned LDAP service. It is not simulation-owned LDAP.

## Account Placement

`docs/account-model.md` is the account authority. This model uses that account
taxonomy and places each account in the end-to-end system.

| Account or group | Used by | Placement |
| --- | --- | --- |
| Gerrit runtime account | Gerrit service and Gerrit role helper | Local OS account on the Gerrit target. Owns Gerrit process and role-local files only. |
| Jenkins runtime account | Jenkins service, Jenkins role helper, and integration helper | Local OS account on the Jenkins controller target. Owns Jenkins process, Jenkins home, and Jenkins-held integration private keys. |
| Jenkins agent runtime account | Jenkins agent service and integration helper | Local OS account on the Jenkins agent target. Owns SSH build-agent sessions and workspace paths. |
| Jenkins shared integration group | Integration helper | Local OS group shared by Jenkins controller and Jenkins agent runtime accounts for reviewed shared storage proof only. |
| Gerrit admin account | Human Gerrit administrator or approved machine runner | LDAP-backed human account or group used to create or approve Gerrit configuration changes. |
| Jenkins admin account | Human Jenkins administrator or approved machine runner | LDAP-backed human account or group used to configure Jenkins credentials, nodes, trigger server, and verification jobs. |
| Jenkins Gerrit integration account | Jenkins controller runtime and Gerrit service | Gerrit service account used by Jenkins for Gerrit SSH authentication, `stream-events`, and `Verified` voting. |
| Test user account | Verification utility | LDAP-backed human-style account used to prove login/change workflow and disposable Gerrit change behavior. |
| LDAP bind account | Gerrit and Jenkins services | Read-only LDAP service account used for directory search. |
| `ci-operator` account | Simulation machine runner and simulation harness | Simulation-only local OS account for orchestration, SSH access, helper commands, privileged simulation operations, and evidence collection. |

Credential custody rules from `docs/account-model.md` apply throughout the
system:

- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.
- Jenkins agent consumes only the Jenkins-to-agent public key.
- Evidence may include public key paths, fingerprints, credential IDs, account
  names, and bounded log references.
- Evidence must not include private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing environment values.

## LDAP Secret Boundary

Real organization LDAP bind credentials are valid only in `target-deployment`
and must follow approved secret handling and evidence redaction rules.

Simulation modes must not consume real organization LDAP bind secrets.
`docker-simulation` and `vm-simulation` use simulation-owned LDAP directories,
users, groups, bind accounts, and bind passwords only. Simulation env files,
mounted secrets, generated state, logs, and evidence must not contain real
LDAP bind DNs or passwords. If a simulation run is configured with real target
LDAP secrets, it must fail closed rather than preserve or exercise those
secrets.

Simulation evidence must identify LDAP as simulation or test LDAP.
`target-deployment` evidence may record LDAP URL, base DN, bind account
identifier, and search/check results when allowed, but never the bind password
or full secret-bearing values.

## Utilities

Utilities are invoked by actors and implement lifecycle phases. Utilities are
not actors.

| Utility | Ownership boundary |
| --- | --- |
| Role helpers: `scripts/gerrit-setup.sh`, `scripts/jenkins-controller-setup.sh`, `scripts/jenkins-agent-setup.sh` | Own role-local lifecycle work only: preflight, artifact preparation, target-local install/configuration, role-local validation, role-local evidence, and role-local helper-generated state. |
| Shared integration helper: `scripts/integration-setup.sh` | Owns cross-role work: Jenkins-held keys, Gerrit public-key registration, Gerrit integration ACL/label workflow, Jenkins credentials, Jenkins node registration, Gerrit Trigger configuration, cross-role validation, trigger verification, integration evidence, and shared helper-generated state. |
| Docker simulation utility: `simulation/docker/simulate.sh` | Realizes the logical environments in containers and orchestrates Docker simulation checkpoints. Docker APIs are simulation lifecycle internals, not the product communication surface. |
| VM verifier: `simulation/vm/vm-verify.sh` | Realizes or checks the logical environments in VMs when VM support exists. |
| Global evidence collector: `scripts/collect-evidence.sh` | Validates and aggregates generated evidence. It must not create runtime success or replace lifecycle proof. |

Role helpers must not expose cross-role commands. Cross-role SSH, Gerrit
Trigger setup, Jenkins agent registration from the controller side, scheduling
proof, `Verified` voting, and integration evidence belong to
`scripts/integration-setup.sh`.

## Standard Interfaces

Logical environments communicate through declared interfaces. Utilities must
prefer these interfaces over deployment-specific internals.

| Interface | Used for |
| --- | --- |
| SSH to target OS environments | Common control-plane access for Gerrit target, Jenkins controller target, and Jenkins agent target. |
| SSH-based file transfer, such as `scp` or `rsync` | Artifact staging, public-key handoff, bounded payload transfer, and evidence/log retrieval when needed. |
| Gerrit HTTP REST | Gerrit account/key registration, review/config workflows, review posting, and state checks. |
| Gerrit SSH | Jenkins-to-Gerrit authentication and `stream-events` proof. |
| Jenkins HTTP/API/script endpoint | Jenkins credential, node, trigger server, job, build, and readiness operations. |
| LDAP URL | Gerrit and Jenkins LDAP bind/search checks and LDAP-backed login assumptions. |
| Jenkins controller to agent SSH | Runtime build-agent connection used by Jenkins to schedule and execute jobs. |

`scripts/integration-setup.sh` should use SSH as the common OS/control-plane
interface across containers, VMs, and real hosts. It should not use Docker as
its target communication surface. Docker simulation may use Docker APIs to
create, start, stop, or inspect containers, but it must expose logical targets
through the same service and OS interfaces expected by VM and target
deployment modes.

Service API calls may originate from the operator workstation/control node or
from a target environment when network reachability requires it. The selected
origin must be recorded in bounded logs or evidence when it affects
interpretation of the proof.

## Lifecycle Checkpoints

The setup system moves through checkpoints. Each checkpoint has an owner, a
mutation boundary, and evidence obligations.

| Checkpoint | Owner | Boundary |
| --- | --- | --- |
| Input review | Human operator or machine runner | Prepare reviewed env files and remove placeholders. No target mutation. |
| Artifact preparation | Bundle factory through role helpers | Prepare application artifacts, manifests, checksums, and source-boundary labels. Target hosts are not mutated. |
| Artifact staging | Actor or simulation utility | Transfer prepared artifacts to target environments and verify target-side manifests/checksums before service mutation. |
| Role-local setup | Role helpers | Install/configure only the role-local target state for Gerrit, Jenkins controller, or Jenkins agent. |
| Role-local validation | Role helpers | Prove role readiness without cross-role integration claims. |
| Shared integration setup | `scripts/integration-setup.sh` | Create or validate cross-role keys, ACL workflow, credentials, node registration, trigger server, jobs, and shared storage. |
| Cross-role validation | `scripts/integration-setup.sh` plus simulation/verifier utility | Prove Jenkins-to-Gerrit SSH, `stream-events`, effective Gerrit label/access state, Jenkins-to-agent SSH, node readiness, and scheduling. |
| End-to-end trigger verification | `scripts/integration-setup.sh` plus simulation/verifier utility | Prove disposable Gerrit change, event delivery, Jenkins build, agent execution, REST vote posting, and Gerrit review state. |
| Evidence audit | Global evidence collector and actor review | Validate evidence completeness, redaction, manifests, checksums, mode labels, and bounded log references. |

Each mutating checkpoint must have a reviewed input source, a bounded log
reference, and a resumable status or evidence boundary. Passing evidence must
represent real runtime checks for the claimed checkpoint. Unsupported,
unimplemented, unavailable, or modeled behavior must be reported as
`blocked`, `unsupported`, or `not-applicable`, not as `pass`.

## Integration ACL Model

The initial environment uses one Gerrit configuration review in `All-Projects`
for Jenkins integration ACL and label delivery. This is a deliberate
simplification of the reviewed Gerrit configuration workflow.

The single `All-Projects` review contains:

- The global `Verified` label definition.
- Read and `label-Verified -1..+1` permissions for the Jenkins Gerrit
  integration actor or group on the reviewed ref pattern.
- The `streamEvents` global capability grant.

Mode-specific behavior:

| Mode | ACL behavior |
| --- | --- |
| `target-deployment` | Create one reviewable `All-Projects` config change through Gerrit REST and wait for approved submission outside the helper. Validation blocks until the change is submitted and effective. |
| `docker-simulation` | Create the same `All-Projects` config review and auto-submit it as simulation test automation, then validate effective state. |
| `vm-simulation` | Create the same `All-Projects` config review and auto-submit it as simulation test automation, then validate effective state. |

Direct ACL mutation without a review is an explicit simulation-only fallback.
It is a narrow waiver for lab automation only, not an alternate product path.
It must require explicit opt-in, must be labeled `simulation-only direct
Gerrit REST apply` in docs, logs, and evidence, must validate effective state
after mutation, and must fail closed outside simulation modes.

Project selection for Jenkins Trigger and disposable verification is still
configured in trigger/job inputs. In v1, the Gerrit ACL review itself is owned
by `All-Projects` and is scoped by ref pattern rather than by a separate
project-level Gerrit config review.

## Evidence Relationship

`docs/validation-and-evidence.md` owns the detailed evidence schema and
redaction rules. This model defines minimum checkpoint expectations:

- Evidence must record mode, timestamp, environment or role, checkpoint,
  command, status, reviewed input fingerprint, relevant endpoints, manifest
  references, checksum results, bounded logs, and redaction status.
- Integration evidence must distinguish role-local readiness from cross-role
  readiness and end-to-end trigger proof.
- Gerrit ACL evidence must record ACL mode, `All-Projects` change identifier
  when one exists, review URL or `not-created`, submit behavior when
  applicable, effective permission checks, integration actor or group, bounded
  log references, and redaction status.
- Simulation evidence must be labeled as `docker-simulation` or
  `vm-simulation` and must not imply target-deployment acceptance.
- `target-deployment` evidence must identify real target infrastructure only
  through approved, non-secret identifiers.

Evidence records must never include private keys, passwords, tokens, LDAP bind
secrets, or full secret-bearing env values.

## Source Boundary

The source boundary from `docs/prd.md` applies to every mode:

- Ubuntu/OS dependencies and application artifacts are separate supply lanes.
- Target environments may use approved internal Ubuntu/OS package sources for
  OS dependencies.
- Public internet fallback for target-host Ubuntu/OS dependency installation
  is simulation-only and must be labeled as such.
- Target environments must not download Gerrit/Jenkins application artifacts
  from the public internet as fallback.
- Application artifacts are prepared in the bundle factory, staged to targets,
  and verified by manifest and checksum before target mutation.
- v1 does not support offline Ubuntu dependency bundles.

## Terminology

Use these terms in docs and implementation work:

- `docker-simulation`.
- `target-deployment`.
- `operator workstation/control node` for the environment where actors invoke
  package utilities.
- `actor` only for humans and machine runners that invoke utilities.
- `utility` for scripts, helpers, harnesses, verifiers, and collectors.
- `service` for Gerrit, Jenkins, LDAP, SSH daemons, and similar runtime
  processes.
- `account` for runtime, admin, integration, test, bind, shared group, and
  simulation OS account identities described in `docs/account-model.md`.
