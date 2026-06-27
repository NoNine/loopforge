## Repository Context

This repository contains the Gerrit/Jenkins setup package described in
`docs/prd.md`.

Keep the v1 product boundary clear:

- v1 is not a strict air-gapped installer.
- v1 does not support offline Ubuntu dependency bundles.
- Public internet fallback on target hosts is simulation-only and must be
  labeled as such in docs, logs, and verification summaries.
- `root` is forbidden as a Loopforge account or direct login identity. When
  privileged target operations are unavoidable, document them as delegated
  privilege from the operator account; root-owned OS custody is not a
  Loopforge account role.

## Interaction Rules

- Do not use question countdowns or timed auto-resolution prompts when asking
  the user for input; ask directly and wait, unless higher-priority system or
  developer instructions require otherwise.

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

Never repair a stale or inconsistent Docker simulation run in place. Use a
fresh `HARNESS_RUN_ID`/generated run root for new validation; run `down` and
`clean` for the old run first.

## Remote Access Safety

Read-only inspection of remote machines, VMs, containers, Jenkins, Gerrit, or
SSH-accessible verification hosts is allowed when it supports the current task.
Use bounded log inspection for remote commands as described above.

Never modify a remote machine, VM, container host, Jenkins controller or agent,
Gerrit host, or SSH-accessible verification machine without explicit user
approval for that specific target and action.

Remote actions that require explicit approval include:

- Installing, upgrading, removing, or reconfiguring packages.
- Editing, creating, deleting, moving, or changing ownership or permissions of
  remote files.
- Running `sudo` actions or changing users, groups, SSH keys, or credentials.
- Starting, stopping, restarting, enabling, disabling, or reloading services.
- Creating, deleting, restoring, snapshotting, resizing, rebooting, or shutting
  down VMs.
- Running Docker or Compose lifecycle commands, pruning resources, changing
  Docker networks, mounting the Docker socket, or running privileged
  containers.
- Changing Jenkins or Gerrit configuration, plugins, credentials, jobs, queues,
  agents, permissions, or triggering builds that affect external state.
- Changing firewall rules, routes, proxies, DNS, TLS certificates, or exposed
  service bindings.
- Deleting logs, workspaces, artifacts, caches, databases, queues, or test
  results.
- Running destructive cleanup, load tests, stress tests, or verification that
  may leave persistent side effects.

Prefer read-only checks and documented dry runs before requesting approval for
remote mutation. State the expected side effects before asking for approval.
