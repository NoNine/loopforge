# Validation And Evidence

## Purpose

This manual defines the operator-facing validation and evidence flow for the
v1 Gerrit/Jenkins setup package.

The goal is audit-friendly proof without needing repo history. Evidence must
show what was checked, when it was checked, which environment or role produced
it, and which logs or manifests support the result.

v1 boundaries still apply:

- v1 is not a strict air-gapped installer.
- v1 does not support offline Ubuntu dependency bundles.
- Public internet fallback on target hosts is simulation-only and must be
  labeled that way in docs, logs, and verification summaries.

## Native Target-Deployment Acceptance

Native `target-deployment` installation and configuration are fully manual.
The operator records acceptance through
`docs/operations/native/acceptance-checklist.md`, not through machine-generated
records or global aggregation. The checklist tracks observed outcomes and
retains only three system-of-record references: the deployment/change ticket,
the disposable Gerrit verification change, and the Jenkins verification
build.

Service logs remain in their normal target locations and are inspected when a
check fails. Native acceptance does not require copied logs, structured record
authoring, or an evidence package. The completed checklist remains in the
organization's approved change-management system and must not contain private
keys, passwords, tokens, LDAP bind secrets, or secret-bearing configuration.

## Helper-Assisted Target-Deployment Acceptance

Helper-assisted `target-deployment` produces machine-generated structured
checkpoint results, but a human operator or reviewer remains the acceptance
authority.
The operator records checkpoint decisions in
`docs/operations/setup/acceptance-checklist.md` and retains the completed
checklist in the approved change-management system.

A structured helper result with `status=pass`, zero exit status, evidence
package, or terminal summary does not accept a target-deployment checkpoint or
authorize later target work. Those artifacts support the human decision. The
checklist is the durable acceptance record.

## Structured Checkpoint Result Contract

The product lifecycle contract defines a checkpoint result without requiring a
file representation. This section defines the structured result emitted by a
helper or other machine utility that owns one product checkpoint instance. One
result carries both the outcome and its supporting evidence; the owner does not
write a separate completion record for the same attempt. A simulation harness
may invoke the owner, capture the exact result, and verify it, but must not
manufacture a passing result from an exit status, log, or presentation summary.

Every structured checkpoint result must include:

- Verification mode.
- Timestamp.
- Package version and helper command version or git commit.
- Role or environment name.
- Product checkpoint family and any role or target qualifier needed to identify
  the product checkpoint instance.
- Command name.
- Status: `pass`, `fail`, `blocked`, `unsupported`, or `not-applicable`.
- Hostnames and service endpoints.
- Sanitized product input manifest or reviewed product-input fingerprint, plus
  an opaque execution-binding fingerprint supplied by the mode coordinator.
- Artifact manifest reference.
- Checksum reference and checksum verification result.
- Service startup checks where applicable.
- For VM and target deployment, systemd unit name, enabled state, active
  state, MainPID, runtime-account ownership, and a bounded journal reference
  where applicable.
- Endpoint checks where applicable.
- LDAP checks where applicable.
- SSH checks where applicable.
- Plugin checks where applicable.
- JCasC checks where applicable.
- Runtime-account checks where applicable.
- Shared integration group and shared Jenkins storage checks where applicable.
- Jenkins agent scheduling and execution results where applicable.
- Gerrit Trigger event, build, and `Verified` vote results where applicable.
- Gerrit ACL realization, effective-permission results, target project,
  inherited scope, ACL mode, Gerrit version, and actor/group references where
  applicable.
- Target SSH aliases or reviewed host identifiers where applicable.
- Service API origin, such as control node, Gerrit target, or Jenkins
  controller target, where applicable.
- For target deployment, Gerrit config-review change IDs, URLs, and submit
  actor where applicable.
- Bounded log references.
- Redaction status.

Structured results must not include private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Secret-looking values should be omitted or
redacted.

The execution-binding fingerprint lets the mode coordinator reject replay
without exposing simulation set/run internals or target-deployment change
management details to the product helper. Workflow predecessors, run-plan
heads, acceptance decisions, Docker identities, and libvirt identities do not
belong in a structured checkpoint result.

Integration-scoped results from `scripts/integration-setup.sh` are distinct
from role-qualified checkpoint results and from the final global
aggregation. They may record public key fingerprints, Jenkins credential IDs,
account names, service endpoints, helper-owned `/var/lib/loopforge/` and
`/var/log/loopforge/` references, the shared integration group name and GID,
shared storage path, bounded read/write proof, bounded log paths,
target SSH aliases, service API origins, ACL mode and realization, effective
permission results, mode-appropriate Gerrit review fields,
trigger/build/change identifiers, and redaction status. They must not record
private keys, tokens, passwords, LDAP bind secrets, or full secret-bearing env
values.

The global collector accepts legacy role-readiness results that do not yet carry
explicit `package_version` or `helper_command_version` fields. It enriches
those results in the final package with collector metadata and marks the source
metadata as `legacy-inferred`. New results should include both fields when
possible.

## Evidence Modes

Use mode labels consistently:

- `simulation-only` for Docker or VM simulation environment evidence and for
  explicitly labeled bundle-factory public-download fallback in simulation.
- `target-deployment` for realistic but non-production verification.
- `docker-simulation` for the shared Docker harness path.
- `vm-simulation` for VM-scaffold or VM-simulation evidence.

Summaries must clearly distinguish simulation-only runs from target-deployment
runs. A `pass` status must be backed by real runtime checks for the claimed
product checkpoint instance. Use `blocked`, `unsupported`, or `not-applicable`
for lifecycle work that did not run; do not use modeled results as passing
service
readiness, Jenkins scheduling, Gerrit Trigger delivery, or `Verified` voting
proof.

Structured checkpoint results must reject contradictory success and failure
signals. A success marker, terminal summary, or result `pass` is invalid for the
claimed product checkpoint instance when the referenced bounded logs contain
matching runtime failures such as package-manager errors, missing commands,
missing service
units, failed LDAP bind/search, checksum mismatch, ownership mismatch,
permission denial, timeout, traceback, exception, or explicit failure markers.
In that case the checkpoint outcome must be recorded as `fail` or `blocked`, not
accepted as a pass with caveats or used to complete the product checkpoint
instance.

## Simulation Operation Records

Simulation lifecycle owners write simulation operation records for retained
proof of resource creation, startup, shutdown, restoration, cleanup, and
destruction. These records use `record_kind=simulation-operation`, contain no
product checkpoint claim, cannot supply a run-step checkpoint-result digest,
and never advance the product run plan. Read-only `preflight`, `status`,
`audit-state`, and `ssh` commands create no durable record by default.

`simulation/docs/shared/operation-records.md` owns their exact simulation
schema, operation mapping, state-transition relationship, storage, and
retention. This document continues to own their shared status vocabulary,
redaction, bounded-log, contradiction, and aggregation requirements.

## Product Checkpoint Results

Every applicable product checkpoint instance has one checkpoint result from its
owner. Helpers and machine utilities emit structured results so their outcomes
and proof can be reviewed and consumed by a mode coordinator. Native
`target-deployment` presents observed results directly to the human acceptance
authority and does not require structured result files or run-step records.

A structured checkpoint result states an outcome and its proof but does not
itself advance the simulation run plan or authorize later target work.
`simulation/docs/shared/run-plan-transition-protocol.md` defines how the
simulation harness captures and verifies structured results before committing
run-plan transitions. This document continues to own their content, status,
redaction, and aggregation rules.

Structured results must use the canonical product checkpoint family names from
`docs/contracts/lifecycle-contract.md` and add the role or target qualifier
needed to identify the instance. Do not create evidence-only checkpoint names:
service installation and startup evidence belongs to `Role-local setup`, role
readiness evidence belongs to `Role-local validation`, and final aggregation
belongs to `Evidence audit`.

In target deployment, the owning actor records the product outcome for `Input
review or source selection` and `OS dependency provisioning` through the
applicable procedure and acceptance checklist. Simulation waives those two
families from its product run plan: `init-run` records source selection and
`create` records dependency-baseline preparation as simulation operations.
Neither operation emits a structured checkpoint result. Effective-input
rendering and publication are also simulation operation boundaries, not
another product checkpoint result.

## Role-Qualified Checkpoint Results

Artifact preparation, Artifact staging, Role-local setup, and Role-local
validation each expand into separate Gerrit, Jenkins controller, and Jenkins
agent checkpoint instances. Each instance has its own result from the utility
that owns that checkpoint; a result for one family or role does not satisfy
another instance.

| Product checkpoint family | Structured-result owner | Required proof focus |
| --- | --- | --- |
| Artifact preparation | Corresponding role helper in the bundle factory | Bound manifest, checksums, payload digests, source boundary, and verification outcome |
| Artifact staging | Staging actor or simulation utility | Bound target-side manifest and checksum-verification outcome |
| Role-local setup | Corresponding role helper | Bound identity, installation, configuration, initial runtime, and applicable service-manager outcome |
| Role-local validation | Corresponding role helper | Observations against the completed setup result and current live role state without mutation |

Role-local validation has role-specific proof obligations:

- Gerrit results cover startup, HTTP, SSH, LDAP, and plugin readiness.
- Jenkins controller results cover startup, HTTP, LDAP, plugins, JCasC, and
  controller runtime readiness.
- Jenkins agent results cover SSH readiness, runtime-account ownership, and
  remote filesystem readiness.

For `vm-simulation` and helper-based `target-deployment`, Gerrit and Jenkins
controller setup and validation results include the applicable guest systemd
unit state in addition to application checks. Jenkins agent results include the
enabled and active guest `ssh.service` or `sshd.service` state.
`docker-simulation` records its direct process and endpoint checks instead,
because it has no guest systemd manager and does not claim reboot persistence.
Native `target-deployment` tracks the corresponding role and reboot outcomes in
the acceptance checklist.

Machine-generated role-qualified results are primary inputs to global
aggregation.

## Integration Checkpoint Results

The shared integration helper owns structured checkpoint results for
Integration preflight, mode-appropriate access, Shared integration setup,
Cross-role validation, and End-to-end trigger verification. These results are
not substitutes for role-qualified results or the final evidence package. They
are inputs to simulation coordination and global aggregation.

- The target-deployment Reviewed Access result includes both Gerrit
  reviews and a non-success `blocked` state while approval or submission is
  pending.
- The simulation shared-setup result sets `reviewed_access.status` to
  `not-applicable`, `reviewed_access.reason=unsupported-in-simulation`,
  `acl_realization=simulation-only-direct-rest-apply`, and real effective ACL
  validation. It must not claim review creation, approval, or submission.
- The shared-setup result also includes public key fingerprints,
  credential and node identifiers, trigger configuration, shared storage
  state, and its
  bounded controller-write/agent-read result without claiming validation.
- The cross-role validation result includes effective ACL
  observations, read-only SSH results, key custody, storage configuration, node
  configuration and online
  state, and Gerrit Trigger connection state. It must not result from target or
  application mutation performed by validation.
- The end-to-end proof result includes the disposable job and change,
  SSH event delivery, agent scheduling and execution, REST vote, and Gerrit
  review state.

Every integration checkpoint result and private prerequisite marker must bind to the same
target-deployment reviewed input set or published simulation effective input
set, target identities, mode, and run or selected state. Target-deployment
review state also binds both Gerrit review identifiers. A constant label or
marker existence alone is not an input fingerprint and must not authorize a
later phase. Public structured results contain only the redacted binding;
private state may retain the protected detail needed to verify it. Ephemeral simulation
transport hosts may be recorded as observations but are not part of the stable
effective-input fingerprint.

For target deployment, `examples/integration.env.example` is the template for
the single reviewed source of the cross-role Jenkins shared group name, shared
group GID, and shared storage path. In simulation it is a source template whose
stable values are published in the effective input bundle. Helper-generated
shared state and helper logs live under
`/var/lib/loopforge/` and `/var/log/loopforge/` on target environments.

Docker simulation results must prove the shared path is mounted into both
Jenkins containers by writing a file as the controller runtime account and
reading it as the agent runtime account.

VM shared-storage results must prove the Jenkins agent VM hosts the NFS-backed
`/data/jenkins-shared` export, the Jenkins
controller VM mounts that export at the same path, the shared group/GID and
export options were validated, and controller and agent runtime accounts can
perform the required read/write proof. VM results must use `vm-simulation` and
`simulation-only` labels and must not imply `target-deployment` acceptance.

ACL planning records must include:

- `target_project`
- `target_ref_scope`
- `acl_mode`
- `acl_realization`
- `gerrit_version`
- `all_projects_review_change_id` or `not-created`
- `all_projects_review_url` or `not-created`
- `target_project_review_change_id` or `not-created`
- `target_project_review_url` or `not-created`
- submit actor and effective-state result for each review, or `not-applicable`
- `reviewed_access.status`
- `reviewed_access.reason` when status is `not-applicable`
- effective global and project/ref permission results
- `integration_actor_or_group`
- `service_api_origin`
- target SSH alias or reviewed host identifier for each target involved
- validation result summaries

Simulation results must set review fields to `not-created`, Reviewed Access to
`not-applicable`, and ACL realization to
`simulation-only-direct-rest-apply`. Blocked or dry-run records must not claim
mutation success, submission, or a real Gerrit review when none occurred.

## Global Aggregation

`scripts/collect-evidence.sh` validates and aggregates:

- Required structured checkpoint results from role and integration owners.
- The Evidence audit structured result when collection is final.
- Supplemental Docker and VM simulation operation records when present.

Global aggregation applies to machine-generated results.
It is not required for the native `target-deployment` acceptance checklist.

The global collector runs as the final Evidence audit after the required
product checkpoint instances and end-to-end proof have produced their results.
It validates and packages the reached evidence set; it does not advance its own
run step or authorize later target work. In simulation, the active harness
captures and verifies the collector result and separately commits the
`evidence-audit` run-plan transition. In helper-assisted target deployment, the
final package is required supporting material and the human reviewer separately
accepts or blocks Evidence audit in the helper acceptance checklist.

Operators may run the collector earlier to inspect partial diagnostic evidence.
An early or incomplete package must identify itself as partial and cannot claim
Evidence audit success, committed run-plan completion, or target acceptance.

The helper writes a final evidence package containing:

- A machine-readable summary JSON.
- A human-readable summary text file.
- Sanitized per-result manifests and status counts.
- Checksum references.
- Bounded log references.
- Enriched package metadata for legacy records that lacked explicit package or
  helper version fields.

The helper must fail on malformed JSON, missing required fields, invalid
status values, secret-looking values, stale or mixed execution binding,
contradictory success and failure signals, or a missing required record for the
checkpoint set being audited. These are evidence-audit checks, not acceptance
decisions.

## Default Output

By default, the collector writes to an ignored generated path:

- `simulation/evidence/package/`

Operators may override the input and output paths with command-line flags.
Generated evidence should not be committed.

## What To Review

Use the summaries to confirm:

- Which product checkpoint claims had `pass`, `fail`, `blocked`, `unsupported`,
  or `not-applicable` evidence outcomes.
- Which hostnames and endpoints were exercised.
- Which manifests and checksums were verified.
- Which shared integration group, GID, and storage path were verified.
- Which logs support the result.
- Whether the run was simulation-only or target-deployment.
- Whether any sensitive data was redacted.

Use the simulation run-plan ledger to confirm committed run steps and the
applicable target-deployment acceptance checklist to confirm human decisions.
A summary may present either state only when it reads and identifies the
authoritative run-step or human acceptance record; evidence counts alone never
establish either claim.

## Verification

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|target-deployment|checksums|Verified|LDAP|agent" docs/contracts/validation-and-evidence.md scripts/collect-evidence.sh
```
