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

## Machine-Generated Evidence Contract

The following contract applies to evidence produced by helpers and simulation
utilities. Every machine-generated evidence record must include:

- Verification mode.
- Timestamp.
- Package version and helper command version or git commit.
- Role or environment name.
- Checkpoint name.
- Command name.
- Status: `pass`, `fail`, `blocked`, `unsupported`, or `not-applicable`.
- Hostnames and service endpoints.
- Sanitized config input manifest or reviewed input fingerprint.
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
- Gerrit ACL reviewed-workflow planning or blocked results where applicable.
- Target project, inherited scope, ACL mode, Gerrit version, review change
  identifier, and actor/group references where applicable.
- Target SSH aliases or reviewed host identifiers where applicable.
- Service API origin, such as control node, Gerrit target, or Jenkins
  controller target, where applicable.
- ACL mode, Gerrit config-review change IDs, config-review URLs, and submit
  actor where applicable.
- Bounded log references.
- Redaction status.

Records must not include private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Secret-looking values should be omitted or
redacted.

Integration-scoped records from `scripts/integration-setup.sh` are distinct
from role-local readiness records and from the final global aggregation. They
may record public key fingerprints, Jenkins credential IDs, account names,
service endpoints, helper-owned `/var/lib/loopforge/` and
`/var/log/loopforge/` references, the shared integration group name and GID,
shared storage path, bounded read/write proof, bounded log paths,
target SSH aliases, service API origins, ACL mode, Gerrit config-review change
IDs and URLs, submit actor when applicable, trigger/build/change identifiers,
and redaction status. They must not record private keys, tokens, passwords,
LDAP bind secrets, or full secret-bearing env values.

The global collector accepts legacy Step 7-9 records that do not yet carry
explicit `package_version` or `helper_command_version` fields. It enriches
those records in the final package with collector metadata and marks the source
metadata as `legacy-inferred`. New records should include both fields when
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
checkpoint. Use `blocked`, `unsupported`, or `not-applicable` for lifecycle
work that did not run; do not use modeled records as passing service
readiness, Jenkins scheduling, Gerrit Trigger delivery, or `Verified` voting
proof.

Readiness evidence must reject contradictory success and failure signals. A
success marker, terminal summary, or evidence `pass` is invalid for the
claimed checkpoint when the referenced bounded logs contain matching runtime
failures such as package-manager errors, missing commands, missing service
units, failed LDAP bind/search, checksum mismatch, ownership mismatch,
permission denial, timeout, traceback, exception, or explicit failure markers.
In that case the checkpoint must be recorded as `fail` or `blocked`, not
accepted as a pass with caveats.

## Checkpoints

Helpers and simulation utilities collect machine-generated evidence at every
operator workflow checkpoint so failed runs can be reviewed from the last
completed boundary. Native `target-deployment` uses the acceptance checklist
to track the corresponding outcomes without producing checkpoint records.

Recommended checkpoints:

- Inputs and reviewed env files.
- Artifact preparation.
- Artifact staging and checksum verification.
- Service installation and startup.
- Role readiness.
- Integration readiness.
- Jenkins agent validation.
- Gerrit Trigger acceptance.
- End-to-end acceptance.
- Final aggregation.

## Role-Local Evidence

Role helpers from Steps 7, 8, and 9 emit checkpoint-level evidence for their
own scope.

- Gerrit evidence covers startup, HTTP, SSH, LDAP, and plugin readiness.
- Jenkins controller evidence covers startup, HTTP, LDAP, plugins, JCasC, and
  controller runtime readiness.
- Jenkins agent evidence covers SSH readiness, runtime-account ownership, and
  remote filesystem readiness.

For `vm-simulation` and helper-based `target-deployment`, Gerrit and Jenkins
controller role evidence records the guest systemd unit state in addition to
application checks. Jenkins agent evidence records the enabled and active guest
`ssh.service` or `sshd.service` state. `docker-simulation` records its direct
process and endpoint checks instead, because it has no guest systemd manager
and does not claim reboot persistence. Native `target-deployment` tracks the
corresponding role and reboot outcomes in the acceptance checklist.

Machine-generated role records are the primary inputs to global aggregation.

## Integration-Local Evidence

The shared integration helper owns cross-role evidence for Jenkins-to-Gerrit
SSH, Jenkins-to-agent SSH, Gerrit Trigger configuration, agent scheduling,
trigger delivery, `Verified` voting, shared Jenkins controller/agent storage,
and Gerrit ACL reviewed-workflow planning. These records are not substitutes
for role-local readiness records and are not the final evidence package. They
are additional inputs consumed by Docker/VM simulation utilities and by global
aggregation.

`examples/integration.env.example` is the single reviewed source for the
cross-role Jenkins shared group name, shared group GID, and shared storage
path. Helper-generated shared state and helper logs live under
`/var/lib/loopforge/` and `/var/log/loopforge/` on target environments.

Docker simulation evidence must prove the shared path is mounted into both
Jenkins containers by writing a file as the controller runtime account and
reading it as the agent runtime account.

VM simulation evidence must identify the selected `vm_set_id` and `run_id`
for every VM harness checkpoint. Harness records should include relevant
libvirt domain names, VM hostnames or reviewed aliases, baseline snapshot
records, VM-set ownership metadata, generated run marker references, guest SSH
readiness, and cloud-init or seed readiness where applicable.
VM LDAP evidence must record LDAP service readiness, seeded account/group
presence, bind/search proof, LDAP endpoint identity, simulation/test LDAP
labeling, and redaction status without LDAP passwords or bind secrets.
`reboot` evidence must record the selected VM targets, delegated
operator-account reboot path, SSH return, and pre-validation post-reboot
systemd recovery checks. VM shared storage evidence must prove the Jenkins
agent VM hosts the NFS-backed `/data/jenkins-shared` export, the Jenkins
controller VM mounts that export at the same path, the shared group/GID and
export options were validated, and controller and agent runtime accounts can
perform the required read/write proof. VM records must use `vm-simulation` and
`simulation-only` labels and must not imply `target-deployment` acceptance.

ACL planning records must include:

- `target_project`
- `inherited_scope`
- `acl_mode`
- `gerrit_version`
- `review_change_id` or `not-created`
- `review_url` or `not-created`
- `submit_actor` or `not-applicable`
- `integration_actor_or_group`
- `service_api_origin`
- target SSH alias or reviewed host identifier for each target involved
- validation result summaries

Blocked or dry-run records must not claim mutation success, auto-submit, or a
real Gerrit review when none occurred.

## Global Aggregation

`scripts/collect-evidence.sh` validates and aggregates:

- Role-local records from Gerrit, Jenkins controller, and Jenkins agent.
- Docker harness records.
- VM simulation utility records.
- End-to-end integration records when present.

Global aggregation applies to machine-generated records.
It is not required for the native `target-deployment` acceptance checklist.

The helper writes a final evidence package containing:

- A machine-readable summary JSON.
- A human-readable summary text file.
- Sanitized per-record manifests and status counts.
- Checksum references.
- Bounded log references.
- Enriched package metadata for legacy records that lacked explicit package or
  helper version fields.

The helper must fail on malformed JSON, missing required fields, invalid
status values, or secret-looking values in evidence records.

## Default Output

By default, the collector writes to an ignored generated path:

- `simulation/evidence/package/`

Operators may override the input and output paths with command-line flags.
Generated evidence should not be committed.

## What To Review

Use the summaries to confirm:

- Which checkpoint passed, failed, blocked, or was not applicable.
- Which hostnames and endpoints were exercised.
- Which manifests and checksums were verified.
- Which shared integration group, GID, and storage path were verified.
- Which logs support the result.
- Whether the run was simulation-only or target-deployment.
- Whether any sensitive data was redacted.

## Verification

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|target-deployment|checksums|Verified|LDAP|agent" docs/contracts/validation-and-evidence.md scripts/collect-evidence.sh
```
