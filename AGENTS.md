## Repository Context

This repository contains the Gerrit/Jenkins setup package described in
`docs/product/prd.md`.

Use `docs/README.md` to resolve documentation authority before
changing product, process, or implementation facts. Use
`docs/planning/implementation-plan.md` for implementation sequencing and
`project-state/execution-status.md` for mutable resume state.

## Interaction Rules

- Do not use question countdowns or timed auto-resolution prompts when asking
  the user for input; ask directly and wait, unless higher-priority system or
  developer instructions require otherwise.

## State Handling

Do not add backward-compatibility guards or fallback paths to fix stale or
broken state. Stale or broken state should fail clearly and be repaired
through explicit cleanup, migration, or operator action.

## Issue Resolution And Code Fixes

Fix defects by proving and repairing the root cause at the layer that owns the
broken contract. Do not add workaround paths that make callers tolerate a
lower-layer defect.

Procedure:

1. Start from the observed failure: bounded log, evidence, failing test, or
   runtime probe.
2. Identify the failed contract and owning layer before editing.
3. If the failing environment is accessible, debug it too. Start read-only; if
   practical, prove causality with the smallest temporary owning-layer change.
   Remote or shared mutation still requires explicit approval.
4. Make the formal fix at the owning layer, keeping code readable and scoped.
5. Add or update a focused regression test for the broken contract.
6. Verify narrowly first, then broaden only for shared behavior.
7. Report root cause, fix location, and verification.

Existing broken environments are diagnostic evidence, not compatibility
targets. Use them to prove root cause when useful, but keep the formal fix
scoped to the owning contract for valid new state. Do not add repair paths,
compatibility behavior, or recovery instructions for already-broken state
unless the user explicitly asks for recovery.

Do not call these root-cause fixes unless the contract requires them: larger
timeouts, sleeps, retries, raw-IP DNS bypasses, lower-level state bypasses,
stale-state fallback paths, service repair inside validation, or compatibility
with broken generated state.

Temporary environment changes may prove causality; they must not replace the
formal code fix or become hidden recovery paths.

## Test File Modes

Commit new runnable `tests/**/*-test.sh` files as executable (`100755`);
keep sourced fixtures non-executable unless they are also direct commands.

## Commit Messages

Use standard Git-style commit messages. Treat these as hard requirements, not
preferences:

- Write a non-empty, short, imperative subject, for example
  `Add Jenkins validation docs`.
- Capitalize the subject and do not end it with a period.
- Keep the subject under 72 characters; prefer about 50 characters.
- Separate the subject from the body with exactly one blank line when a body is
  needed.
- Use the body to explain why the change exists and any important context; do
  not merely repeat the subject.
- Wrap every body line at 72 characters or fewer.
- Keep each commit to one logical change.
- Add issue references or trailers at the end when relevant.

Do not require `Prompt:` or `Conversation context:` sections unless the user
explicitly asks for them.

Before creating or amending a commit, draft the full message and check each
line length. After creating or amending a commit, inspect
`git log -1 --pretty=format:%B` and verify the subject, body shape, and line
lengths before reporting completion.

Prefer `git commit -F -` for multiline messages:

```bash
git commit -F - <<'EOF'
Add Jenkins validation docs

Explain why the validation evidence is needed and note any important
operator-facing context.
EOF
```

Do not use repeated `-m` flags to simulate wrapped body lines; each `-m`
argument creates a separate paragraph.

## Commit Scope

- Never stage or commit `project-state/execution-status.md` as part of implementation,
  documentation, cleanup, or a broad request to commit current changes.
- Keep `project-state/execution-status.md` as unstaged mutable resume state by default,
  including when other repository changes are committed.
- Commit that file only when the user explicitly requests a ledger snapshot
  commit and names `project-state/execution-status.md` or the execution ledger.
- Before every commit or amend, verify that the staged path list excludes
  `project-state/execution-status.md` unless that explicit exception applies.

## Command Preflight

Construct safely, validate fast, then run long. Identify every interpreter and
which layer owns each expansion before composing a command. Prefer direct
arguments, shell arrays, quoted heredocs, temporary scripts, and environment
variables over nested inline command strings.

Before any time-consuming operation, verify the exact command with cheap
checks: validate syntax and quoting, confirm expansion at each interpreter
boundary, check paths, arguments, environment, and prerequisites, and use a
dry run or minimal harmless probe when available. Confirm log capture before
starting the full operation.

If a command fails, identify the parsing or execution layer that broke and fix
the construction method. Do not blindly add escapes and retry the expensive
operation.

## Log Handling

Never stream verbose Docker, Jenkins, Gerrit, package-manager, build, download,
SSH, VM, or verification logs into the conversation.

Before running a command that may emit long output or run for more than a few
seconds, redirect stdout and stderr to a timestamped log file:

```bash
log="logs/command-$(date +%Y%m%d%H%M%S).log"
command >"$log" 2>&1
rc=$?
printf 'exit=%s log=%s\n' "$rc" "$log"
```

For long-running local commands, prefer foreground execution redirected to a
timestamped log. In Codex, let the command-runner tool keep the command alive
and poll it through its returned tool session handle while inspecting only
bounded log output:

```bash
log="logs/command-$(date +%Y%m%d%H%M%S).log"
command >"$log" 2>&1
rc=$?
printf 'exit=%s log=%s\n' "$rc" "$log"
```

Avoid plain `(...) &`, `nohup`, or `disown` in command-runner tool calls. If
true detachment is unavoidable, use `setsid`, write PID/status files, and poll
those files. Do not use `wait "$pid"` from a later shell; Bash returns `127`
because the PID is not that shell's child.

Inspect only bounded output:

- Exit code or process status.
- Log path and PID for detached commands.
- `rg` markers such as `ERROR`, `FAILED`, `Timed out`, `Traceback`,
  `Exception`, or `Completed`.
- `tail -40 "$log"` or a similarly small bounded tail.
- Specific failure snippets needed to explain the next action.

Terminal success summaries must stay short and scan-friendly. Do not print
absolute generated paths when a basename, run ID, snapshot name, or bounded
`log=`/`evidence=` reference is enough. Keep full paths in generated
evidence/log files when operators need traceability.

For long-running remote verification, poll sparsely after confirming the
process is alive and logs are being written. Each poll should inspect only
process state, exit code, log size, phase/error markers, and bounded failure
snippets.

For Docker simulation in this workspace, assume `docker-compose` v1 is
available. Do not run separate Compose discovery probes before every Docker
simulation; let `simulation/docker/simulate.sh` perform its own internal
Compose selection unless a failure specifically points at Compose.

## Simulation Cleanup And Recovery

Never repair stale or inconsistent simulation state in place. Use
explicit inspection and cleanup commands, then start new validation from
fresh selected state.

- Use `audit-state` for read-only state inspection, not recovery.
- Do not hide recovery inside `run`, role phases, integration phases, or
  verification commands.
- Treat `stop`, `restore-baseline`, `clean`, and `destroy` as explicit
  lifecycle/recovery commands with their documented side effects.
- For Docker and VM simulation, `stop` followed by `start` continues the same
  immutable `HARNESS_RUN_ID`. Begin new validation only after `stop`,
  `restore-baseline`, and `clean`; then let `init-run` generate a fresh run ID.
- Never reuse an old run ID, completion marker, or retained evidence as a new
  validation prerequisite.
- When reusable resource identity is suspect, select a fresh `HARNESS_SET_ID`;
  clean up old simulation sets only with their retained env file.
- VM host-wide libvirt cleanup must run
  `simulation/vm/tools/cleanup-libvirt-resources.sh --dry-run` first.
  Actual host-wide cleanup requires explicit approval for that target
  and action.

## Remote Access Safety

Read-only inspection of remote machines, VMs, containers, Jenkins, Gerrit, or
SSH-accessible verification hosts is allowed when it supports the current task.
Use bounded log inspection for remote commands as described above.

Never modify a remote machine, VM, container host, Jenkins controller or agent,
Gerrit host, or SSH-accessible verification machine without explicit user
approval for that specific target and action.

Remote mutation that requires explicit approval includes changes to:

- packages, files, users, groups, permissions, credentials, SSH keys, or
  delegated-privilege actions;
- services, VMs, containers, Docker or Compose lifecycle, networks, storage,
  snapshots, reboots, or shutdowns;
- Jenkins or Gerrit configuration, plugins, credentials, jobs, queues, agents,
  permissions, or triggered builds;
- firewall rules, routes, proxies, DNS, TLS certificates, or exposed service
  bindings;
- logs, workspaces, artifacts, caches, databases, queues, test results, or any
  destructive cleanup, load test, stress test, or verification that may leave
  persistent side effects.

Prefer read-only checks and documented dry runs before requesting approval for
remote mutation. State the expected side effects before asking for approval.
