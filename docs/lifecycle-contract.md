# Loopforge Lifecycle Contract

## Purpose And Authority

This document defines how Loopforge setup moves through time. It owns phase
behavior, checkpoint order, mutation boundaries, stop/review/resume points,
rerun rules, and lifecycle command mapping.

`docs/system-model.md` owns the conceptual architecture: environments, actors,
utilities, services, interfaces, deployment modes, and cross-cutting system
invariants. This contract applies those concepts to operator workflow and
verification sequencing.

Operator manuals and simulation docs provide concrete procedures inside this
contract. They may add role-specific or layer-specific detail, but they must
not redefine checkpoint semantics or imply success without real proof for the
claimed checkpoint.

## Phase Behavior Rules

Lifecycle phases are strict, single-purpose operations:

- Each phase checks its prerequisites before doing work.
- Missing inputs, artifacts, services, or checkpoints fail clearly and stop.
- Each phase owns only its own work and does not rerun or repair another
  phase.
- Later phases do not silently trigger earlier phases.
- Repeated operator invocation is treated as an intentional rerun of that
  same phase.
- Phase logs and evidence stay bounded and identify the producing phase.
- Phase success means the phase completed its own job, not that another phase
  was replayed or repaired implicitly.

Target-environment operations run as the operator account whenever practical.
The operator account is the default target control-plane identity for helper
commands, staging, validation, and evidence collection. Direct root login or
root as a workflow identity is not supported. Delegated privilege from the
operator account is used only for narrow OS operations that require it, such
as package installation, protected path creation, service management, or
ownership changes. Runtime accounts own and run their services; they are not
the default orchestration identity.

## Lifecycle Checkpoints

The setup system moves through checkpoints. Each checkpoint has an owner, a
mutation boundary, and evidence obligations.

Simulation docs provide layer-specific realizations of this lifecycle
contract. They may split, collapse, or add simulation-only command phases, but
they must preserve the checkpoint semantics defined here.

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

## Operator Workflow Contract

The default operator workflow is a phase contract, not a full runnable command
transcript. Operator manuals own exact commands and role-specific procedure.

| Phase | Machine/environment | Helper commands | Inputs/outputs | Side effects | Required checkpoint |
| --- | --- | --- | --- | --- | --- |
| Inputs | Operator workstation | `print-env-template`, `preflight` | Copies env examples into reviewed role env files, removes all `CHANGE_ME` values, keeps secrets out of committed examples, reviews cross-role values, and confirms browser-visible URLs for simulation. | None beyond local env-file creation. | Reviewed env files exist for Gerrit, Jenkins controller, Jenkins agent, and shared integration values; preflight failures are resolved before mutation. |
| Artifacts | Bundle factory | `prepare-artifacts` | Consumes reviewed role env files and produces role artifact directories, manifests, checksums, and source-boundary records. | Downloads or copies curated application artifacts and plugins; any public internet use is labeled `simulation-only` when it occurs in simulation. | Role artifact manifests and checksums are produced and retained as evidence inputs. |
| Artifact staging | Bundle factory and target hosts | Operator-managed file transfer or simulation utility; target-side checksum verification | Stages prepared role artifacts from the bundle factory to the Gerrit host, Jenkins controller, and Jenkins agent host. | Copies files onto target hosts but does not install services until checksums pass. | Staged artifact paths exist on each target host, and target-side manifest/checksum verification passes before installation. |
| Gerrit readiness | Gerrit host | Gerrit role helper install/configure/validate phases | Consumes Gerrit env values and staged Gerrit artifacts; produces Gerrit service config and readiness evidence. | Installs packages from approved sources, creates or updates local runtime files, and starts or restarts Gerrit. | Gerrit starts, uses LDAP, exposes HTTP/SSH, records bounded logs, and stops before Jenkins integration mutation. |
| Jenkins controller readiness | Jenkins controller | Jenkins controller role helper install/configure/validate phases | Consumes Jenkins controller env values and staged Jenkins artifacts; produces service, plugin, JCasC, and readiness evidence. | Installs packages from approved sources, creates or updates Jenkins runtime files, installs plugins, and starts or restarts Jenkins. | Jenkins starts, uses LDAP/JCasC, has required plugins, records bounded logs, and stops before Gerrit Trigger, credential transfer, node registration, scheduling, or vote proof. |
| Jenkins agent readiness | Jenkins agent | Jenkins agent role helper install/configure/validate phases | Consumes Jenkins agent env values and staged Jenkins agent artifacts; produces SSH daemon, runtime account, filesystem, bounded log, and evidence records. | Installs packages from approved sources and creates or updates agent-host runtime files and SSH service state. | The agent host proves OS/tooling, SSH daemon, runtime account, filesystem, staged artifact, bounded log, and evidence readiness, and stops before credential transfer, controller node registration, or scheduling proof. |
| Shared integration | Jenkins controller, Gerrit host, and Jenkins agent | `scripts/integration-setup.sh` | Consumes reviewed role env files plus reviewed integration env values. Produces Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, Gerrit Trigger, node, validation, vote, and integration evidence. | Creates or updates controller-held key material, Gerrit public-key registration, reviewed Gerrit config changes, Jenkins credentials, Jenkins node config, disposable verification artifacts, and review votes. | Run after all three role manuals complete. Follow `docs/integration-setup-manual.md` for the cross-role command sequence and stop/review points. |
| Evidence | All role environments | `collect-evidence` | Consumes role validation outputs, manifests, checksums, sanitized config manifests, and bounded log references. | Writes local evidence summaries only; it must not expose secrets or private keys. | Mode-labeled evidence, manifests, checksums, fingerprints, and bounded log references are retained for each checkpoint. |

## Sequencing Rules

- Run `prepare-artifacts` from the bundle factory environment for each role.
- Stage prepared artifacts from the bundle factory to each target host before
  running target-host installation, then verify manifests and checksums on the
  target host before mutation.
- Application artifact bundles for Gerrit, Jenkins controller, and Jenkins
  agent are key-free. They must not contain SSH private keys, public keys,
  `authorized_keys`, or generated key/public-key handoff files.
- Keypair generation and public-key handoff between Gerrit, Jenkins
  controller, and agent are integration-step work.
- Target-host OS dependencies come from approved internal Ubuntu/OS package
  repositories. Public internet fallback for target-host OS dependency
  installation is simulation-only and must be labeled in docs, logs,
  manifests, and verification summaries.
- Complete Gerrit, Jenkins controller, and Jenkins agent role-only bringup
  before running the shared cross-role integration helper.
- Use `docs/integration-setup-manual.md` for the approved cross-role helper
  command workflow. Role manuals must hand off to that document instead of
  duplicating the full integration command sequence.
- Treat role-local `validate` as role-only readiness validation. Treat shared
  `validate-integration` and `prove-integration` as later cross-role
  acceptance for Gerrit SSH, event streaming, Jenkins agent scheduling, REST
  vote posting, and Gerrit review state.

## Simulation Command Relationship

`simulation/README.md` owns shared simulation command semantics.
`simulation/docker/README.md` and `simulation/vm/README.md` own the concrete
command references for their layers.

Commands that perform checkpoint work must preserve the checkpoint semantics
defined here: input review, artifact preparation, artifact staging,
role-local setup, role-local validation, shared integration setup, cross-role
validation, end-to-end trigger verification, and evidence audit.

Simulation lifecycle and convenience commands such as `up`, `create`,
`status`, `ssh`, `audit-state`, `reboot`, `down`, `clean`, and `destroy` are
outside the checkpoint progression unless a layer README explicitly ties one
of them to a checkpoint. These commands must not silently rerun earlier
phases or claim checkpoint success without checkpoint evidence.

For Docker simulation, `down` and `clean` are the only commands allowed to
recover from stale existing containers. Other commands must report
inconsistent state and stop. `simulation/docker/README.md` owns the detailed
Docker generated-state, stale-container, and cleanup rules.

For VM simulation, `down`, `clean`, and `destroy` are the only commands
allowed to recover from inconsistent VM lifecycle state. Other commands must
report inconsistent state and stop. `clean` must preserve review artifacts
and must not delete the reusable VM set. Only `destroy` removes
simulation-owned VM resources.

## Evidence Obligations

Evidence obligations are detailed in `docs/validation-and-evidence.md`. This
contract requires every checkpoint to preserve enough proof for review without
replaying verbose runtime logs:

- Evidence must identify mode, timestamp, environment or role, checkpoint,
  command, status, reviewed input fingerprint, relevant endpoints, manifest
  references, checksum results, bounded logs, and redaction status.
- Integration evidence must distinguish role-local readiness from cross-role
  readiness and end-to-end trigger proof.
- Simulation evidence must be labeled as `docker-simulation` or
  `vm-simulation` and must not imply target-deployment acceptance.
- Evidence records must never include private keys, passwords, tokens, LDAP
  bind secrets, or full secret-bearing env values.
