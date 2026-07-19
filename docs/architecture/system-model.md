# Loopforge System Model

## Purpose And Authority

This document models Loopforge's initial experiment environment. The initial
environment constructs and verifies a Gerrit/Jenkins integration stack with
LDAP-backed identity assumptions, a Jenkins SSH build agent, Gerrit Trigger,
`Verified` voting, and evidence collection. This model defines the
environments, actors, accounts, utilities, services, interfaces, deployment
modes, and evidence relationships used by Loopforge. It is not a command
transcript or lifecycle procedure.

`docs/product/prd.md` remains the product scope authority. This system model sits below
the PRD and above topic-specific docs, operator manuals, simulation docs, and
helper script implementations. Topic-specific docs provide details inside the
boundaries defined here. `docs/contracts/lifecycle-contract.md` defines how setup moves
through phases, checkpoints, mutation boundaries, and resume/rerun behavior.

Use `docs/README.md` for the full layered authority model and review
checklist.

If this model exposes a new product requirement or changes the product
boundary, update `docs/product/prd.md` explicitly instead of carrying the requirement
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
interfaces, lifecycle effects, and evidence limits before or alongside
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
homes and from operator input custody. Helper state holds staging handoff,
evidence, bounded logs, bundle-factory preparation state, and related
helper-managed state. Full reviewed helper env files remain operator inputs
and are transferred to target-side operator input locations for execution;
they are not helper state. Service-owned state remains under the native
Gerrit, Jenkins controller, and Jenkins agent homes.

The helper-owned paths are not service homes. They are the workspace used by
helper scripts and integration workflows to prepare, stage, validate, and
record execution state. `docs/contracts/directory-model.md` defines these
target-visible paths, their ownership, permission model, sensitivity, and
evidence behavior. `simulation/docs/shared/generated-state-layout.md` separately
defines the host-side generated storage used to realize simulation.

Helper utilities should be self-contained when practical. A helper should
create, clean, validate, and report on the role-local helper-owned paths it
can reasonably manage as the operator account. Simulation harnesses and
environment setup provide prerequisites that helpers cannot provide
themselves, such as generated run roots, bind-mount backing paths, container
lifecycle, or file transfer waivers; they must not replace helper-owned
lifecycle work, create container-visible Loopforge roots for role helpers, or
pre-populate helper outputs as success.

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
Structured checkpoint results state machine-produced outcomes and proof without
exposing secrets.

## Logical Environments

The setup system has these logical environments. Docker, VM, and target
deployment modes realize them differently, but the logical responsibilities
remain stable.

| Environment | Responsibility |
| --- | --- |
| Operator workstation or control node | Holds reviewed input files, invokes utilities, receives short summaries, and collects generated evidence references. It is not a Gerrit/Jenkins runtime target. |
| Bundle factory | Loopforge preparation environment that produces reviewed, version-pinned application artifacts, manifests, checksums, and source-boundary records before target runtime identity, application, or service mutation. |
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

`docs/contracts/account-model.md` is the account authority. This model uses that account
taxonomy and places each account in the end-to-end system.

| Account or group | Used by | Placement |
| --- | --- | --- |
| Gerrit runtime account | Gerrit service and Gerrit role helper | Local OS account on the Gerrit target. Owns Gerrit process and role-local files only. |
| Jenkins runtime account | Jenkins service, Jenkins role helper, and integration helper | Local OS account on the Jenkins controller target. Owns Jenkins process, Jenkins home, and Jenkins-held integration private keys. |
| Jenkins agent runtime account | Jenkins agent service and integration helper | Local OS account on the Jenkins agent target. Owns SSH build-agent sessions and workspace paths. |
| Jenkins shared integration group | Integration helper | Local OS group shared by Jenkins controller and Jenkins agent runtime accounts for reviewed shared storage proof only. |
| Gerrit admin account | Human Gerrit administrator or approved machine runner | LDAP-backed human account or group used to create or approve Gerrit configuration changes. |
| Jenkins admin account | Human Jenkins administrator or approved machine runner | LDAP-backed human account or group used to configure Jenkins credentials, nodes, trigger server, and verification jobs. |
| Jenkins Gerrit integration account | Jenkins controller runtime and Gerrit service | Gerrit service account used by Jenkins for Gerrit SSH `stream-events` and REST `Verified` voting with a Gerrit-generated auth token. |
| Test user account | Verification utility | LDAP-backed human-style account used to prove login/change workflow and disposable Gerrit change behavior. |
| LDAP bind account | Gerrit and Jenkins services | Read-only LDAP service account used for directory search. |
| Operator account | Human operator, machine runner, and simulation harness | Configurable local OS account for orchestration, SSH access, helper commands, delegated privileged operations, and evidence collection. Default example is `ci-operator`; `root` is forbidden. |

Credential custody rules from `docs/contracts/account-model.md` apply throughout the
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
users, groups, bind accounts, and bind passwords only. Simulation-owned fake
LDAP bind passwords may appear in simulation bootstrap env files so the local
LDAP service can seed its read-only user. They must stay labeled as
simulation-owned test credentials and must not be embedded in bundles,
evidence, logs, helper-owned state, or target-deployment inputs. Simulation
env files, mounted secrets, generated state, logs, and evidence must not
contain real LDAP bind DNs or passwords. If a simulation run is configured
with real target LDAP secrets, it must fail closed rather than preserve or
exercise those secrets.

Simulation evidence must identify LDAP as simulation or test LDAP.
`target-deployment` evidence may record LDAP URL, base DN, bind account
identifier, and search/check results when allowed, but never the bind password
or full secret-bearing values.

## Utilities

Utilities are invoked by actors and implement lifecycle phases. Utilities are
not actors.

| Utility | Ownership boundary |
| --- | --- |
| Role helpers: `scripts/gerrit-setup.sh`, `scripts/jenkins-controller-setup.sh`, `scripts/jenkins-agent-setup.sh` | Own role-local lifecycle work only: preflight, artifact preparation, target-local install/configuration, role-local validation, role-local evidence, and role-local helper-generated state. They should be self-contained where practical and manage their own role-local helper paths. |
| Shared integration helper: `scripts/integration-setup.sh` | Owns cross-role work: Jenkins-held keys, Gerrit public-key registration, Gerrit integration ACL/label workflow, Jenkins credentials, Jenkins node registration, Jenkins-agent-hosted shared storage, Gerrit Trigger configuration, cross-role validation, trigger verification, integration evidence, and shared helper-generated state. |
| Docker simulation utility: `simulation/docker/simulate.sh` | Realizes the logical environments in containers and orchestrates Docker run steps. It prepares only simulation infrastructure it must provide and does not replace role helper lifecycle work. Docker APIs are simulation lifecycle internals, not the product communication surface. |
| VM simulation utility: `simulation/vm/simulate.sh` | Realizes the logical environments in libvirt/KVM VMs and orchestrates VM run steps when VM support exists. |
| Global evidence collector: `scripts/collect-evidence.sh` | Validates and aggregates generated evidence. It must not create runtime success or replace lifecycle proof. |

Role helpers must not expose cross-role commands. Cross-role SSH, Gerrit
Trigger setup, Jenkins agent registration from the controller side, scheduling
proof, `Verified` voting, and integration evidence belong to
`scripts/integration-setup.sh`.

## Lifecycle Boundary

`docs/contracts/lifecycle-contract.md` owns phase behavior rules, product
checkpoint semantics,
mutation boundaries, product workflow sequencing, and resume/rerun behavior.
Simulation documents own shared and backend command semantics. This system
model defines the conceptual architecture used by that lifecycle contract.

Lifecycle implementations must preserve these system invariants:

- Simulation modes model the same logical product behavior as target
  deployment and must not manufacture success by bypassing declared
  interfaces, role helpers, shared integration helper ownership, native
  product paths, runtime accounts, staged artifact verification, or real
  runtime and evidence checks.
- Target-environment operations use the operator account as the default
  control-plane identity whenever practical. Direct root login or root as a
  workflow identity is not supported; privileged target operations are
  delegated from the operator account.
- Role helpers stay role-local. Cross-role SSH, Gerrit Trigger setup,
  Jenkins agent registration from the controller side, scheduling proof,
  `Verified` voting, and integration evidence belong to
  `scripts/integration-setup.sh`.
- Favorable evidence must represent real runtime checks for the claimed product
  checkpoint instance. Unsupported, unimplemented, unavailable, or modeled
  behavior must not be represented as successful proof.

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

Endpoint identity rules for these interfaces are defined in
`docs/contracts/endpoint-identity.md`.

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

## Integration ACL Model

The initial environment uses two Gerrit configuration reviews so global
integration state and project-local authority remain separate.

The `All-Projects` review contains:

- The global `Verified` label definition.
- The `streamEvents` global capability grant.

The reviewed target-project change contains:

- Read permission for the Jenkins Gerrit integration actor or group.
- `label-Verified -1..+1` permission on the reviewed ref pattern.

The target-project grant must not be moved to `All-Projects`; doing so would
broaden Jenkins authority to every project that inherits the ref grant.

Mode-specific behavior:

| Mode | ACL behavior |
| --- | --- |
| `target-deployment` | Create the reviewable `All-Projects` and target-project changes through Gerrit REST, record both review identifiers and URLs, and stop with a non-success `blocked` result until both are approved, submitted, and effective. |
| `docker-simulation` | Apply the global and project/ref ACLs directly through Gerrit REST as `simulation-only direct Gerrit REST apply`, then validate effective state. Reviewed Access is unsupported and `not-applicable`. |
| `vm-simulation` | Apply the global and project/ref ACLs directly through Gerrit REST as `simulation-only direct Gerrit REST apply`, then validate effective state. Reviewed Access is unsupported and `not-applicable`. |

Direct ACL mutation without a review is the only supported simulation
realization. It is not an alternate target-deployment product path. It must be
selected explicitly, labeled `simulation-only direct Gerrit REST apply` in
docs, logs, and evidence, validate effective state after mutation, and fail
closed outside simulation modes.

Project selection for Jenkins Trigger and disposable verification must match
the target project named by the project-level access review. The ref pattern in
that review must match the trigger and verification-job inputs.

## Evidence Relationship

`docs/contracts/validation-and-evidence.md` owns the detailed evidence schema,
outcome vocabulary, binding fields, supporting references, and redaction rules.
This model requires evidence to bind an observed outcome to its claimed product
scope and execution context without becoming an acceptance decision.

- Integration evidence must distinguish role-local readiness from cross-role
  readiness and end-to-end trigger proof.
- Gerrit ACL evidence must prove the mode-appropriate access realization and
  effective permission state. Simulation must identify Reviewed Access as
  outside its workflow and must not claim review activity.
- Simulation evidence must be labeled as `docker-simulation` or
  `vm-simulation` and must not imply target-deployment acceptance.
- Native `target-deployment` acceptance uses
  `docs/operations/native/acceptance-checklist.md`. It records observed
  outcomes and only the approved deployment/change ticket, Gerrit verification
  change, and Jenkins verification build references.
- Helper-assisted `target-deployment` acceptance uses
  `docs/operations/setup/acceptance-checklist.md`. A human reviewer accepts or
  blocks each checkpoint from the structured helper result; the helper
  artifacts do not authorize progression by themselves.

Machine-generated records and the native checklist must never include private
keys, passwords, tokens, LDAP bind secrets, or full secret-bearing env values.

## Source Boundary

The source boundary from `docs/product/prd.md` applies to every mode:

- Ubuntu/OS dependencies and application artifacts are separate supply lanes.
- Target environments may use approved internal Ubuntu/OS package sources for
  OS dependencies. This prerequisite provisioning may occur before application
  artifact preparation and staging.
- Public internet fallback for target-host Ubuntu/OS dependency installation
  is simulation-only and must be labeled as such.
- Target environments must not download Gerrit/Jenkins application artifacts
  from the public internet as fallback.
- Application artifacts are prepared in the bundle factory, staged to targets,
  and verified by manifest and checksum before runtime identity, product-home,
  application, or service mutation on the target.
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
  simulation OS account identities described in `docs/contracts/account-model.md`.
