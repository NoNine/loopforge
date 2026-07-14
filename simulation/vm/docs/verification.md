# VM Milestone Verification

## Purpose

This companion document defines the verification gate for VM simulation
milestones. It is narrower than the public command contract in
`simulation/vm/README.md` and more detailed than the milestone roadmap in
`simulation/vm/docs/design.md`.

A milestone is complete only when its required runtime assertions pass, the
bounded logs do not contain contradictory failure evidence, and success
summaries or markers are emitted after the proof they summarize. A zero exit
code, marker file, or terminal summary is not sufficient when the supporting
log shows failed commands.

## Gate Rules

- Commands must fail closed when a required runtime assertion cannot be
  proven.
- Success markers such as `baseline-prereqs=ready`, `os-baseline`,
  `ldap-service=ready`, role validation summaries, and proof markers are
  summaries of completed checks, not independent proof.
- Bounded logs invalidate matching readiness markers when they contain
  relevant failure evidence such as apt errors, missing commands, missing
  service units, failed bind/search, checksum mismatch, ownership mismatch,
  permission denial, timeout, traceback, exception, or explicit `FAILED`
  markers.
- Evidence must identify the checked environment and bounded log reference
  without exposing private keys, tokens, passwords, LDAP bind secrets, or full
  secret-bearing env values.
- Verification must inspect the runtime side that owns the claim. Target OS
  package, service, SSH, LDAP, artifact, role, and integration readiness must
  be proven from the VM guest or product API path that would fail in real use.

## Canonical Verification Matrix

VM harness changes must be verified against lifecycle state sequences, not
only individual command success paths. The harness has separate run state and
VM-set state: a `fresh` run means the selected run marker is absent, but the
selected reusable VM set can still exist and contain retained libvirt
resources, seed media, snapshots, metadata, and logs.

Use three verification tiers:

- Static/local checks inspect scripts, docs, shell syntax, and repository
  formatting without mutating VM, libvirt, host, guest, Gerrit, Jenkins, or
  agent resources.
- Stubbed lifecycle checks use deterministic test fixtures such as
  `tests/fixtures/vm-libvirt-stub.sh` to model command order, generated
  state, ownership checks, retained artifacts, and failure paths.
- Approved remote KVM checks run real libvirt/VM lifecycle commands only after
  explicit operator approval for the target and expected side effects.

Every VM harness code change must either run or explicitly justify skipping
these local checks:

```bash
bash -n simulation/vm/simulate.sh simulation/vm/lib/*.sh simulation/lib/*.sh tests/vm-*.sh
tests/vm-docs-contract-test.sh
tests/vm-harness-terminal-summary-test.sh
VM_TEST_INCLUDE_M5=1 tests/vm-harness-m3-lifecycle-test.sh
tests/vm-harness-ldap-seed-test.sh
tests/vm-harness-role-lifecycle-test.sh
tests/vm-harness-reboot-test.sh
tests/vm-harness-vm-set-ownership-test.sh
git diff --check
```

Changes touching artifacts, integration, status output, systemd-resolved
helpers, or cleanup tooling must also run the matching focused
`tests/vm-harness-*-test.sh` or `tests/vm-*-test.sh` file.

The stubbed lifecycle gate must cover these command and state sequences where
the changed subsystem can affect them:

- fresh run with an empty selected VM set;
- fresh run that reuses a retained selected VM set;
- resume run with an existing selected run marker;
- `create -> up -> down -> create` VM-set reuse;
- `clean -> init-run -> create -> up` with the retained VM-set SSH identity;
- `down -> restore-baseline -> clean` generated-state cleanup;
- `clean` after stale metadata that is irrelevant to teardown ownership;
- `destroy` after partial create or missing VM-set metadata;
- `reboot` with SSH host-key and guest service readiness diagnostics;
- `audit-state` before and after `clean` and `destroy`.

Tests should model retained-state side effects when practical. Examples
include stale target SSH known-host entries, non-teardown metadata drift,
retained VM-set SSH identity, libvirt-managed disk metadata, retained seed
media attachment and readability, unowned selected-pool volumes, and bounded
logs that contain runtime failure markers. These are not workaround
scenarios; they are the normal state boundaries created by reusable VM sets
and explicit cleanup commands. Ready-baseline reuse verifies retained seed
media; it must not rewrite or chmod-normalize valid retained seed media as a
hidden repair path.

Recovery remains explicit. Only `down`, `restore-baseline`, `clean`, and
`destroy` may recover VM lifecycle state as defined by
`docs/contracts/lifecycle-contract.md` and `simulation/vm/README.md`. Other commands
must fail clearly on inconsistent state instead of deleting, repairing,
re-owning, or bypassing stale state.

## Milestone Gates

| Milestone | Gate |
| --- | --- |
| M1 | CLI dispatch, env custody, generated paths, summaries, and read-only state checks pass without VM, libvirt, host, guest, Gerrit, Jenkins, or agent mutation. |
| M2 | Libvirt/KVM tooling and VM-set ownership checks are read-only, fail on inconsistent selected resources, and do not repair state. |
| M3 | `create`, `up`, `status`, `ssh --role ROLE`, and `down` prove real VM definitions, guest boot, stable SSH host keys, target OS SSH readiness as the operator account, and clean shutdown. |
| M4 | `create` proves role OS dependency installation, expected command availability, real LDAP service readiness, seeded entries, local LDAP bind/search, and Gerrit/Jenkins controller LDAP bind/search before writing baseline readiness. |
| M5 | Baseline snapshot, `restore-baseline`, `clean`, `destroy`, and `audit-state` prove selected VM-set ownership before rollback, generated-state cleanup, or deletion and do not touch unowned resources. |
| M6 | `prepare-artifacts` and `stage-artifacts` prove artifact manifests, checksums, source-boundary labels, transfer, and target-side staging paths before mutation. |
| M7 | `configure-role` establishes real role service/runtime readiness through role helpers. `validate-role` only observes it. `reboot` must prove guest service recovery before post-reboot validation; readiness is never inferred from reboot success. |
| M8 | `configure-integration`, `validate-integration`, `prove-integration`, and `run` prove actual cross-role SSH, Jenkins node readiness, Gerrit Trigger flow, build execution, and Gerrit `Verified` behavior. |

## M4 Runtime Proof

M4 is the baseline-prerequisite gate. It must not accept marker-only proof.
Before writing `baseline-prereqs=ready`, the harness must prove:

- `create` baked a simulation-owned dependency-prepared base image
  for the selected source image checksum, Ubuntu baseline, apt mirror,
  source-boundary label, VM disk size, and VM package matrix;
- the base-image bake completed package installation from the configured
  simulation apt mirror, and a VM-set-local ready marker proves qcow2 format
  and the recorded baked-image SHA-256 through libvirt volume metadata and
  mediated download;
- existing VM disks prove through libvirt volume metadata that their recorded
  pool, volume, backing path, fingerprint, SHA-256, and disk size match the
  selected baked image, without requiring direct host file access, and domain
  XML attaches the libvirt-reported volume path as a file-backed disk so the
  host security driver can apply its runtime label;
- each VM proves the expected packages and commands are available from the
  baked base image, such as `java`, `curl`, `ssh`, `rsync`, `tar`, `wget`,
  `git`, `unzip`, `sshd`, and `ldapsearch` where required by the VM role;
- the LDAP VM has `slapd` installed, active, and listening on the configured
  LDAP port;
- the LDAP VM can bind and search all seeded users and groups with
  simulation-owned credentials, and every search returns the exact expected
  entry DN rather than only a successful LDAP operation;
- Gerrit and Jenkins controller VMs can resolve the configured VM LDAP FQDN,
  connect to its LDAP port, and bind/search the LDAP endpoint over the VM
  network.

The M4 LDAP evidence record names the simulation endpoint, seeded accounts and
groups, local and consumer bind/search results, bounded log, simulation-only
label, and redaction status. It never contains the bind password.

A failed `create` revalidation removes baseline readiness. `status` reports a
malformed or mismatched readiness marker as `stale`, and `audit-state` fails
without repairing it.

For M4, a create log that contains apt `E:` errors, `Err:` fetch failures,
`command not found`, `Unit file ... does not exist`, failed `ldapsearch`,
permission errors, or timeouts invalidates `os-baseline`,
`base-image-bake=ready`, `base-image=ready`, `ldap-service=ready`,
`ldap-consumer=... reachable`, and `baseline-prereqs=ready` for that run.

## Review Use

Reviewers should use this document when deciding whether a VM milestone can be
accepted. If a focused test only checks marker presence, the matching runtime
gate still has to be proven by bounded logs, evidence, or an additional test
that fails when the underlying runtime command fails.
