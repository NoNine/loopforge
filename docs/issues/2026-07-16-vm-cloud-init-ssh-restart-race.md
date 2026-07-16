# VM Cloud-Init SSH Restart Race

## Report Metadata

| Field | Value |
| --- | --- |
| Status | Code fixed and locally verified; fresh remote VM validation pending |
| Discovered | 2026-07-16 CST (2026-07-15 UTC in guest logs) |
| Reported | 2026-07-16 |
| Affected component | VM simulation `create`, VM-set base-image bake |
| Failed checkpoint | Base-image OS dependency installation |
| Primary fix | This commit (`Prevent VM cloud-init SSH restart race`) |
| Diagnostic support | `640f751` (`Preserve failed VM image bakes for debugging`) |

This report is a historical root-cause analysis. The current VM behavior is
owned by [the VM simulation documentation](../../simulation/vm/README.md),
and current resume state is owned by
[`project-state/execution-status.md`](../../project-state/execution-status.md).

## Executive Summary

A fresh remote VM simulation failed while baking its reusable base image.
Ubuntu's `openssh-server` package could not restart `ssh.socket`, causing
`dpkg` and the VM `create` command to return nonzero before any role or
integration configuration ran.

The VM harness considered SSH reachability sufficient to open its first guest
connection while cloud-init was still configuring SSH. That connection caused
Ubuntu's socket-activated `ssh.service` to start. The seed configuration then
processed `ssh_pwauth: false`; cloud-init updates `PasswordAuthentication` and
restarts an active SSH service when that setting changes. The restart left the
old `sshd` process holding the inherited port-22 listener descriptors.

Later, the OpenSSH package upgrade stopped the current SSH service and socket,
but the old process retained those descriptors. The package post-install step
then failed to start `ssh.socket` because port 22 was still owned by the stale
listener.

The owning defect was VM seed and readiness ordering. It was not a Jenkins
controller or agent role defect, an SSH policy defect in the staged Jenkins
changes, or an OpenSSH package workaround requirement.

## Impact

- A fresh VM-set base-image bake failed during `create`.
- No Gerrit, Jenkins controller, Jenkins agent, or integration role phase ran.
- The failure blocked fresh VM agent and end-to-end integration validation.
- Docker simulation was unaffected because it does not use the VM seed,
  cloud-init, libvirt, or guest systemd path.
- Target deployment was not exercised and no target-deployment state changed.
- Normal failure cleanup originally removed the transient bake domain and work
  files, limiting direct diagnosis until opt-in preservation was added.

The failure was reproducible on fresh remote VM sets. Existing sets with a
previously baked base image could avoid the failing path, so reuse could make
the defect appear intermittent even though the fresh-bake sequence was
deterministic.

## Observed Failure

The package post-install operation invoked:

```text
systemctl --quiet --system restart ssh.socket
```

The delegated command returned `1`. Systemd reported:

```text
ssh.socket: Failed to receive listening socket (0.0.0.0:22): Input/output error
ssh.socket: Failed to listen on sockets: Input/output error
ssh.socket: Failed with result 'resources'.
```

Listener inspection showed that the old daemon still owned both address
families:

```text
0.0.0.0:22  users:(("sshd",pid=1009,fd=3))
[::]:22     users:(("sshd",pid=1009,fd=4))
```

The package transaction ended with:

```text
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

## Durable Evidence Summary

This table preserves the decisive observations in the tracked report. The
original generated logs are supplemental and are not required to understand
or verify the causal analysis.

| Evidence | Durable observation |
| --- | --- |
| Wrapper contract | The smoke test forwarded `--quiet --system restart ssh.socket` exactly and returned the delegated test status `23`. |
| Failing operation | The real `systemctl --quiet --system restart ssh.socket` call returned `1`. |
| Service lifecycle | Systemd reported that PID `1009` remained after `ssh.service` stopped. |
| Listener ownership | PID `1009` retained IPv4 file descriptor `3` and IPv6 file descriptor `4` on port 22. |
| Systemd failure | `ssh.socket` failed with `Result=resources` and an `Input/output error` while receiving the listening socket. |
| Package failure | `openssh-server` remained unconfigured and `dpkg` returned `1`. |
| Cleanup discipline | Temporary systemctl instrumentation was restored while the selected failed bake and debug marker remained preserved. |
| Fix verification | All 16 VM suites, shell syntax, and diff checks passed; the rendered user-data passed YAML parsing and cloud-init schema validation. |

## Operation Timeline

Guest timestamps below are UTC on 2026-07-15. They correspond to early
2026-07-16 CST on the remote control node.

| Time (UTC) | Operation | Observed result |
| --- | --- | --- |
| 17:30:34 | The bake VM booted and systemd activated `ssh.socket`. | Port 22 became socket-activated before cloud-init completed. |
| 17:30:36 | The harness made its first successful SSH readiness connection. | `ssh.socket` started `ssh.service`; listener PID `1009` accepted the connection. |
| 17:30:39 | The harness made its next SSH connection. | By harness ordering, this connection waited for cloud-init completion while SSH configuration was still active. |
| 17:30:41 | Cloud-init's SSH password-authentication module restarted the active SSH service. | Systemd reported PID `1009` as a left-over process while starting a replacement service. This attribution is supported by the seed's `ssh_pwauth: false` setting and cloud-init's documented restart path. |
| 17:30:42 | Replacement `ssh.service` listener PID `1426` started and the harness opened the package-install connection. | PID `1009` remained in the service cgroup with inherited listener descriptors. |
| 17:30:42-17:35:48 | The base-image script updated package indexes and downloaded the dependency set. | SSH remained reachable, so the stale listener did not yet surface as the command failure. |
| 17:35:48 | The OpenSSH package pre-install step stopped `ssh.socket`, `ssh.service`, and `rescue-ssh.target`. | The current listener PID `1426` terminated, but systemd recorded that PID `1009` remained after `ssh.service` stopped. |
| 17:38:35 | The OpenSSH post-install step restarted `ssh.socket`. | Systemd could not acquire port 22 because PID `1009` retained the descriptors; `ssh.socket` failed with `Result=resources`. |
| After 17:38:35 | Package configuration completed its remaining triggers. | `openssh-server` remained unconfigured, `dpkg` returned `1`, and VM `create` failed. |

The causal sequence was therefore:

```text
early SSH readiness probe
  -> socket-activated ssh.service starts
  -> cloud-init ssh_pwauth processing restarts active SSH
  -> old sshd retains inherited port-22 descriptors
  -> OpenSSH package stops the replacement service and socket
  -> stale sshd still owns port 22
  -> OpenSSH package cannot restart ssh.socket
  -> dpkg and VM create fail
```

## Failed Contract And Owning Layer

The VM simulation contract requires cloud-init and target OS control-plane
readiness before base-image package preparation is accepted. The old flow was:

```text
wait for DHCP
  -> prove SSH accepts a connection
  -> wait for cloud-init through SSH
  -> install packages
```

The cloud-init wait occurred after the first connection had already activated
SSH. Waiting was therefore insufficient: the readiness probe itself changed
the service state that cloud-init later restarted.

The VM seed generator owned the restart trigger because it supplied
`ssh_pwauth: false`. The VM readiness functions also weakened the contract by
ending their cloud-init command with `|| true`, which converted missing
cloud-init or a failed cloud-init module into apparent readiness.

The formal repair therefore belonged in VM seed generation and VM readiness,
not in apt handling, OpenSSH package scripts, systemd validation, Jenkins role
helpers, or failure cleanup.

## Root Cause

The root cause was an ordering interaction between three valid mechanisms:

1. Ubuntu Noble used socket activation for OpenSSH.
2. The harness opened SSH before cloud-init finished its SSH modules.
3. Cloud-init's `ssh_pwauth` handler restarted an SSH service that the harness
   had made active.

That interaction left an obsolete `sshd` process holding systemd's inherited
listening sockets. The later package lifecycle correctly attempted to restart
`ssh.socket`, but could not reclaim port 22.

## Contributing Factors

### Readiness changed the observed system

The initial probe was treated as passive readiness, but connecting to a
socket-activated service is a state-changing event. It started `ssh.service`
before cloud-init's SSH work finished.

### Cloud-init errors were tolerated

Both bake and normal VM readiness used a command shaped as:

```text
cloud-init status --wait ... || true
```

That fallback could not prevent the restart and could also hide future
cloud-init failures.

### Fresh and reused VM sets exercised different paths

A run that reused a valid baked base image did not execute the failing package
upgrade. Explicit cleanup forced a new bake and exposed the latent ordering
defect.

### Failure cleanup removed diagnostic state

Before `640f751`, a failed bake normally removed its transient domain and work
directory. Logs showed the package failure but did not preserve the guest for
direct inspection.

### Current package state was an exposure condition, not the owner

The reproduced bake upgraded `openssh-server` from Ubuntu package revision
`.16` to `.18`. Revision `.18` executed the failing socket restart in the
observed run. No comparison proved that the package revision introduced the
stale listener behavior; the listener was created earlier by the harness and
cloud-init interaction.

## Non-Causes

### Staged Jenkins changes

The Jenkins changes committed in `48eb537` configure controller authorization
and the agent's account policy during later role phases. The failure happened
inside base-image baking before VM role configuration. Those changes neither
executed in the failed phase nor changed the static VM package matrix.

### The diagnostic wrapper

The wrapper delegated every call to the real `/usr/bin/systemctl`, preserved
arguments and exit codes, and passed a smoke test that forced a delegated exit
of `23`. In the real bake, stop calls returned `0` and the actual
`restart ssh.socket` call returned `1`. The wrapper observed the failure; it
did not synthesize it.

### A slow package download

Long package download and configuration time widened the timeline but did not
own the stale descriptor. Increasing timeouts or adding sleeps would not
release PID `1009`'s sockets.

## Investigation

### Reproduction and preservation

The failure was reproduced on fresh VM-set identities. Opt-in debug
preservation retained the transient bake domain, qcow2 disk, seed media, XML,
and a private ownership marker. A repeated `create` correctly failed instead
of replacing the evidence.

Known retained diagnostic set IDs at report creation were:

- `jenkins-debug-165900`
- `jenkins-rootcause-171800`
- `jenkins-rootcause-172800`

The last set used network `192.168.128.0/24` and contained the fully
instrumented reproduction.

### Wrapper validation

An initial `PATH`-based wrapper was ineffective because apt and dpkg normalized
their execution path. The effective diagnostic temporarily replaced
`/usr/bin/systemctl`, moved the real binary to a private delegated path, and
logged the call and result before collecting bounded systemd diagnostics.

Before the remote run, a smoke test proved exact argument forwarding and exit
status preservation:

```text
LOOPFORGE_SYSTEMCTL_CALL args= --quiet --system restart ssh.socket
FAKE_SYSTEMCTL_ARGS=--quiet --system restart ssh.socket
LOOPFORGE_SYSTEMCTL_RESULT rc=23
wrapper_basic_check=pass delegated_rc=23
```

### Direct failure evidence

The live instrumentation proved:

- the OpenSSH pre-install stop calls all returned `0`;
- systemd recorded PID `1009` remaining after `ssh.service` stopped;
- PID `1009` still held IPv4 and IPv6 port-22 listener descriptors;
- `systemctl --quiet --system restart ssh.socket` returned `1`;
- `ssh.socket` failed with `Result=resources`;
- `dpkg` returned `1` and `create` failed.

Guest SSH access failed after the broken package transaction, and the bake
domain had no QEMU guest agent configured. The systemctl wrapper therefore
provided the decisive guest-side status, journal, listener, and unit-link
evidence without repairing the environment.

### Instrumentation restoration

After evidence collection, only the temporary wrapper hunk was reversed. The
remote source file matched the locally tested debug-preservation
implementation byte-for-byte. The retained failed VM set and marker were not
cleaned or repaired.

## Resolution

This commit, `Prevent VM cloud-init SSH restart race`, repaired the VM-owned
contract:

1. Normal and bake seed generation now share one operator user-data renderer.
2. The seed no longer supplies `ssh_pwauth`, so cloud-init does not use its
   active-service restart path.
3. Seed media installs a root-owned, account-scoped OpenSSH drop-in for the VM
   operator. It requires public-key authentication and disables password,
   keyboard-interactive, and empty-password authentication without owning
   listener ports or addresses.
4. Cloud-init validates the effective SSH configuration, enables the existing
   Ubuntu SSH unit if needed, and uses `reload`, not `restart`.
5. Bake and normal VM readiness now require `cloud-init status --wait` to
   succeed. Missing cloud-init or failed modules return nonzero.
6. The baked-image schema advanced from `6` to `7`, preventing a cached image
   created under the broken seed contract from satisfying the new
   fingerprint.

The corrected flow is:

```text
cloud-init writes account-scoped operator policy
  -> SSH configuration validation succeeds
  -> SSH is enabled if needed and reloaded without restart
  -> mandatory cloud-init completion succeeds
  -> package installation begins
  -> OpenSSH package can stop and start its socket without a stale listener
```

Commit `640f751` separately added the diagnostic control
`VM_DEBUG_PRESERVE_FAILED_BAKE=1`. It keeps failed bake state only when
explicitly enabled, blocks replacement by another `create`, and requires
ownership-checked `destroy` for cleanup.

## Rejected Workarounds

The resolution intentionally did not add:

- sleeps or larger timeouts;
- package-install retries;
- stale-PID killing before apt;
- a port-22 or raw-IP bypass;
- `systemctl reset-failed` or service repair inside validation;
- tolerance for failed cloud-init;
- compatibility paths for already-broken VM sets.

Those actions would hide or repair the symptom after the VM seed contract had
already failed.

## Regression Coverage

Focused tests now verify:

- both bake and normal VM seeds omit `ssh_pwauth`;
- both seeds contain the root-owned account-scoped public-key policy;
- the seed validates, enables, and reloads SSH without a restart command;
- cloud-init completion happens before base-image package installation;
- a cloud-init failure prevents apt from running and prevents `create`
  readiness;
- normal VM `up` fails when cloud-init completion fails;
- the baked-image marker records schema `7`;
- debug-enabled bake failure preserves evidence and rejects replacement;
- explicit `destroy` removes preserved selected state.

All 16 VM test suites, shell syntax checks, and `git diff --check` passed. The
rendered operator user-data also passed PyYAML parsing and the available
cloud-init schema validator.

## Validation Status And Remaining Work

Local implementation verification is complete. A fresh remote runtime proof
has not yet been claimed.

Remote completion requires explicit approval for these side effects:

1. Run ownership-checked `destroy` for retained diagnostic sets using each
   retained environment file. This removes their selected domains, disks,
   seed media, networks, storage, markers, and VM-set metadata.
2. Select fresh `HARNESS_RUN_ID` and `LOOPFORGE_VM_SET_ID` values.
3. Run fresh VM `init-run` and `create` with
   `VM_DEBUG_PRESERVE_FAILED_BAKE=1`.
4. Continue role and integration phases only after `create` succeeds.
5. If any phase fails, preserve and investigate the direct failure, then stop
   for operator instruction rather than repairing or cleaning it implicitly.

## Supplemental Investigation Artifacts

The following paths identify untracked, investigation-time artifacts. They may
be deleted by later workspace or log cleanup and are not durable dependencies
of this report. The durable observations they support are reproduced above.

- Wrapper smoke test:
  `logs/root-cause-wrapper-basic-check-20260716012957.log`
- Instrumented systemctl call sequence:
  `logs/root-cause-call-sequence-20260716013934.log`
- Exact listener, process, unit, and journal evidence:
  `logs/root-cause-exact-failure-20260716013925.log`
- Failed create result:
  `logs/root-cause-vm-create2-wrapper-20260716013010.log`
- Bounded final package failure and preserved marker:
  `logs/root-cause-failure-evidence-20260716013912.log`
- Cloud-init `ssh_pwauth` restart-path source inspection:
  `logs/plan-cloud-init-ssh-pwauth-source-20260716014948.log`
- Temporary instrumentation restoration:
  `logs/root-cause-wrapper-restore-20260716014252.log`
- Full local VM regression suite:
  `logs/vm-cloud-init-fix-all-vm-20260716091704.log`
- Rendered user-data schema validation:
  `logs/vm-cloud-init-seed-schema-20260716091942.log`
