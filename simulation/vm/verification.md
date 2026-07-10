# VM Milestone Verification

## Purpose

This companion document defines the verification gate for VM simulation
milestones. It is narrower than the public command contract in
`simulation/vm/README.md` and more detailed than the milestone roadmap in
`simulation/vm/design.md`.

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

## Milestone Gates

| Milestone | Gate |
| --- | --- |
| M1 | CLI dispatch, env custody, generated paths, summaries, and read-only state checks pass without VM, libvirt, host, guest, Gerrit, Jenkins, or agent mutation. |
| M2 | Libvirt/KVM tooling and VM-set ownership checks are read-only, fail on inconsistent selected resources, and do not repair state. |
| M3 | `create`, `up`, `status`, `ssh --role ROLE`, and `down` prove real VM definitions, guest boot, stable SSH host keys, target OS SSH readiness as the operator account, and clean shutdown. |
| M4 | `create` proves role OS dependency installation, expected command availability, real LDAP service readiness, seeded entries, local LDAP bind/search, and Gerrit/Jenkins controller LDAP bind/search before writing baseline readiness. |
| M5 | Baseline snapshot, `clean`, `destroy`, and `audit-state` prove selected VM-set ownership before rollback or deletion and do not touch unowned resources. |
| M6 | `prepare-artifacts` and `stage-artifacts` prove artifact manifests, checksums, source-boundary labels, transfer, and target-side staging paths before mutation. |
| M7 | `configure-role`, `validate-role`, and `reboot` prove real role service/runtime readiness through role helpers; readiness after reboot must be re-established by validation, not inferred from reboot success. |
| M8 | `configure-integration`, `validate-integration`, `prove-integration`, and `run` prove actual cross-role SSH, Jenkins node readiness, Gerrit Trigger flow, build execution, and Gerrit `Verified` behavior. |

## M4 Runtime Proof

M4 is the baseline-prerequisite gate. It must not accept marker-only proof.
Before writing `baseline-prereqs=ready`, the harness must prove:

- `create` baked or reused a simulation-owned dependency-prepared base image
  for the selected source image checksum, Ubuntu baseline, apt mirror,
  source-boundary label, VM disk size, and VM package matrix;
- the base-image bake completed package installation from the configured
  simulation apt mirror, or a matching ready marker proved the cache hit;
- cache hits prove qcow2 format and the recorded baked-image SHA-256 through
  libvirt volume metadata and mediated download, and fingerprint-scoped
  locking prevents concurrent publication races;
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
`base-image-bake=ready`, `base-image-cache=hit`, `ldap-service=ready`,
`ldap-consumer=... reachable`, and `baseline-prereqs=ready` for that run.

## Review Use

Reviewers should use this document when deciding whether a VM milestone can be
accepted. If a focused test only checks marker presence, the matching runtime
gate still has to be proven by bounded logs, evidence, or an additional test
that fails when the underlying runtime command fails.
