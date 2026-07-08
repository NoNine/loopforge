# Simulation Terminal Output

This document owns shared terminal presentation conventions for simulation
commands. Layer README files own concrete command behavior for their
entrypoints; this document owns the cross-layer output shape and examples.

Simulation terminal output is an operator-facing summary, not an audit report.
It should stay compact, describe the result honestly, and point to bounded
logs or evidence only when an operator needs retained details.

## Shared Convention

Routine command success should use compact summary lines such as
`preflight: ok`, `init-run: ok run-id=...`, or
`prepare-artifacts[gerrit]: ok bundle=...`. Role-scoped commands should put
the role in brackets after the command name.

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
layer README files as command contracts.

```text
preflight: ok mode=vm libvirt=available
init-run: ok run-id=step13-m3-202607082136
prepare-artifacts[gerrit]: ok bundle=gerrit-artifacts.tar.gz
stage-artifacts[jenkins-controller]: ok verified=manifest,checksums
```

```text
up: failed reason=jenkins-controller ssh readiness timed out
log=generated/simulation/vm/step13-m3-202607082136/host/logs/harness/up.log
evidence=generated/simulation/vm/step13-m3-202607082136/host/evidence/harness/
```

## Status Convention

The `status` command is an operator-facing summary, not an audit report. It
starts with a compact state line such as `status: running` or
`status: initialized`, then prints a `Run` section with selected run identity
and layer-appropriate access information.

Docker may show the Compose project and loopback browser URLs. VM simulation
may show the VM set, project, pending product browser URLs, and target OS SSH
access rows. Layers must not force identical fields when their access models
differ.

When seeded simulation login accounts are useful to operators, status output
uses the shared `Login accounts` table convention: system, username, default
simulation-only password, and purpose. It may list the seeded simulation LDAP
users documented in `simulation/README.md`. It must not print later
integration service accounts as password-backed login accounts.

Use layer-specific `audit-state`, bounded logs, and evidence records for
backend state, generated path inventories, and retained proof.

## Docker Preview

This preview shows the intended shape for Docker simulation status output. It
is not a complete transcript and does not replace `simulation/docker/README.md`
as the command contract.

```text
status: running

Run
  Run ID        summary-12345
  Project       summary-12345
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
not a complete transcript and does not replace `simulation/vm/README.md` as
the command contract.

```text
status: running

Run
  Run ID        step13-m3-202607082136
  VM set        step13-m3-202607082136
  Project       lf-m3-202607082136
  Gerrit URL    pending-role-configuration
  Jenkins URL   pending-role-configuration

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
bounded logs, and evidence records instead of expanding routine terminal
summaries.
