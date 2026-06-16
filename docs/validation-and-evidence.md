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

## Evidence Contract

Every evidence record must include:

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
- Endpoint checks where applicable.
- LDAP checks where applicable.
- SSH checks where applicable.
- Plugin checks where applicable.
- JCasC checks where applicable.
- Runtime-account checks where applicable.
- Jenkins agent scheduling and execution results where applicable.
- Gerrit Trigger event, build, and `Verified` vote results where applicable.
- Bounded log references.
- Redaction status.

Records must not include private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Secret-looking values should be omitted or
redacted.

The global collector accepts legacy Step 7-9 records that do not yet carry
explicit `package_version` or `helper_command_version` fields. It enriches
those records in the final package with collector metadata and marks the source
metadata as `legacy-inferred`. New records should include both fields when
possible.

## Evidence Modes

Use mode labels consistently:

- `simulation-only` for modeled or simulated verification.
- `production-like` for realistic but non-production verification.
- `docker-harness-simulation` for the shared Docker harness path.
- `vm-simulation` for VM-scaffold or VM-simulation evidence.

Summaries must clearly distinguish simulation-only runs from production-like
runs. Do not imply real Jenkins scheduling, Gerrit Trigger delivery, or
`Verified` voting unless the source record actually proves it.

## Checkpoints

Collect evidence at every operator workflow checkpoint so failed runs can be
reviewed from the last completed boundary.

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

- Gerrit evidence covers startup, HTTP, SSH, LDAP, plugin, and integration
  readiness.
- Jenkins controller evidence covers startup, HTTP, LDAP, plugins, JCasC,
  Gerrit SSH, modeled or real agent scheduling checks, and Gerrit Trigger
  checks.
- Jenkins agent evidence covers SSH readiness, runtime-account ownership,
  remote filesystem readiness, and authorized-key readiness.

These records are the primary inputs to global aggregation.

## Global Aggregation

`scripts/collect-evidence.sh` validates and aggregates:

- Role-local records from Gerrit, Jenkins controller, and Jenkins agent.
- Docker harness records.
- VM verifier records.
- End-to-end integration records when present.

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
- Which logs support the result.
- Whether the run was simulation-only or production-like.
- Whether any sensitive data was redacted.

## Verification

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|production-like|checksums|Verified|LDAP|agent" docs/validation-and-evidence.md scripts/collect-evidence.sh
```
