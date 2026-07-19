# Simulation Terminal Output

This document owns shared terminal presentation conventions for simulation
commands. Backend simulation guides own concrete command behavior for their
entrypoints; this document owns the cross-layer output shape and examples.

Simulation terminal output is an operator-facing summary, not an audit report.
It should stay compact, describe the result honestly, and point to bounded
logs or evidence only when an operator needs retained details.

## Shared Convention

Routine command success should use compact summary lines such as
`preflight: ok`, `init-run: ok run-id=...`, or
`prepare-artifacts[gerrit]: ok bundle=...`. Role-scoped commands should put
the role in brackets after the command name.

`ok` reports the command result. For a product run-plan phase, the command may
report committed progress only after the corresponding run-step record has
been committed. A structured-result `pass`, an owning utility exit status, or a
pre-commit summary is not committed progress. Any output that presents
run-plan progress must derive it from and identify the run-plan head.

Commands must not claim success when proof is missing. Use honest states such
as `blocked`, `unsupported`, `not-applicable`, `failed`, or `ok` instead of
synthetic readiness. Failure summaries should start with a compact reason and
then print bounded `log=` or `evidence=` references when retained details are
available.

Normal terminal output must stay concise and avoid backend internals. Do not
stream verbose Docker, VM, SSH, package-manager, Jenkins, or Gerrit logs. Do
not print raw libvirt URIs, VM resource marker values, domain dumps, Docker
bind-mount diagnostics, generated path inventories, private keys, tokens,
LDAP bind secrets, or evidence path inventories in routine command output.

## Summary Preview

These previews show intended summary shape only. They do not replace the
backend simulation guides as command contracts.

```text
preflight: ok mode=vm libvirt=available
init-run: ok run-id=step13-m3-202607082136-a1b2c3d4
prepare-artifacts[gerrit]: ok bundle=gerrit-artifacts.tar.gz
stage-artifacts[jenkins-controller]: ok verified=manifest,checksums
```

```text
start: failed reason=jenkins-controller ssh readiness timed out
log=generated/simulation/vm/step13-m3/host/logs/harness/start.log
evidence=generated/simulation/vm/step13-m3/host/evidence/harness/
```

## Status Convention

The `status` command is an operator-facing summary, not an audit report. It
supports coherent absent, unclaimed, stopped, and running states and starts
with a compact state line such as `status: absent`, `status: stopped`, or
`status: running`. It prints selected set identity, run identity when claimed,
durable classification, reset gate, and only the access information available
in that power state. When a run is claimed, it also reports the committed
run-plan head or `none`; it never derives progress from evidence files.
Contradictory state reports `status: conflicting` and exits nonzero.

Both backends show the shared set and run IDs. Docker may additionally show
the derived Compose project name and loopback browser URLs. VM simulation may
show the derived libvirt resource prefix, pending product browser URLs, and
target OS SSH access rows. Layers must not force identical backend fields when
their access models differ.

When seeded simulation login accounts are useful to operators, status output
uses the shared `Login accounts` table convention: system, username, default
simulation-only password, and purpose. It may list the seeded simulation LDAP
users documented in `simulation/docs/shared/simulation-model.md`. It must not print later
integration service accounts as password-backed login accounts.

Use layer-specific `audit-state`, bounded logs, and simulation operation
records for backend state. Use structured checkpoint results for product-step outcomes and
proof.

## Docker Preview

This preview shows the intended shape for Docker simulation status output. It
is not a complete transcript and does not replace `simulation/docs/docker/docker-simulation.md`
as the command contract.

```text
status: running

Run
  Run ID        summary-12345
  Set ID        default
  Compose       loopforge-docker-default
  Gerrit URL    http://127.0.0.1:18081/
  Jenkins URL   http://127.0.0.1:18082/login

Login accounts
  System              Username        Password              Purpose
  ------------------  --------------  --------------------  ----------------------------------------
  Gerrit              gerrit-admin    admin-password        Gerrit admin user
  Jenkins             jenkins-admin   admin-password        Jenkins admin user
  Gerrit              test-user       test-password         Test/change workflow user
  ------------------  --------------  --------------------  ----------------------------------------
```

## VM Preview

This preview shows the intended shape for VM simulation status output. It is
not a complete transcript and does not replace `simulation/docs/vm/vm-simulation.md` as
the command contract.

```text
status: running

Run
  Run ID        step13-m3-202607082136
  Set ID        default
  VM prefix     loopforge-vm-default
  Gerrit URL    http://192.168.126.133:8080/
  Jenkins URL   http://192.168.126.87:8080/login

Target SSH
  Role                User          Host             State
  ------------------  ------------  ---------------  -------------------
  gerrit              ci-operator   192.168.126.133  ready
  jenkins-controller  ci-operator   192.168.126.87   ready
  jenkins-agent       ci-operator   192.168.126.159  ready
  ------------------  ------------  ---------------  -------------------

Login accounts
  System              Username        Password              Purpose
  ------------------  --------------  --------------------  ----------------------------------------
  Gerrit              gerrit-admin    admin-password        Gerrit admin user
  Jenkins             jenkins-admin   admin-password        Jenkins admin user
  Gerrit              test-user       test-password         Test/change workflow user
  ------------------  --------------  --------------------  ----------------------------------------
```

## Anti-Patterns

Normal simulation terminal output should not include:

- Raw backend identifiers such as `libvirt-uri=...` or `vm-resources=...`.
- Domain, container, bind-mount, or storage dumps.
- Generated state path inventories.
- Verbose Docker, VM, SSH, package-manager, Jenkins, or Gerrit logs.
- Evidence paths, bounded log paths, private keys, passwords beyond
  simulation-only seeded login previews, tokens, or LDAP bind secrets.

If an operator needs backend state or retained proof, use `audit-state`,
bounded logs, operation records, and captured checkpoint results instead of
expanding routine terminal summaries.
