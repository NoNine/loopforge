# Shared Integration Setup Manual

## Purpose And Scope

This manual is the operator guide for `scripts/integration-setup.sh`. Use it
after the Gerrit, Jenkins controller, and Jenkins agent role setup manuals have
completed and each role has passing role-local readiness evidence.

The Standard Interfaces contract in `docs/system-model.md` is authoritative
for this helper. `scripts/integration-setup.sh` must use SSH as the common
OS/control-plane interface for Gerrit, Jenkins controller, and Jenkins agent
targets across Docker simulation, VM simulation, and `target-deployment`.
Docker APIs are simulation lifecycle internals and are not the shared
integration communication surface.

Current implementation caveat: the script still executes only the Docker
simulation path until the SSH target-interface refactor is implemented. That
temporary implementation must fail closed outside `docker-simulation` and must
not be presented as `target-deployment` support.

The shared integration helper owns cross-role work only: Jenkins-to-Gerrit SSH,
Jenkins-to-agent SSH, Gerrit Trigger configuration, Jenkins node readiness,
trigger verification, `Verified` voting, and integration evidence. It does not
replace the role setup manuals and it does not provide native OS operation
instructions.

`target-deployment` workflow defaults to a global `Verified` CI label in
reviewed `All-Projects` configuration. Jenkins read access and
`label-Verified -1..+1` grants stay scoped to the reviewed project and ref
pattern. The `stream-events` permission remains a global capability grant.
Jenkins Gerrit Trigger uses SSH for authentication and event streaming, while
the Gerrit REST review API is the default path for posting `Verified` votes.

Helper-generated shared state and helper logs on target environments live
under `/var/lib/loopforge/` and `/var/log/loopforge/`.

Legacy SSH review commands and flags are not part of the default workflow. Use
them only with explicit operator justification and runtime compatibility
evidence for the installed Gerrit and Gerrit Trigger versions.

## Prerequisites

Before running the shared helper:

- Gerrit role setup is complete and `scripts/gerrit-setup.sh validate` has
  produced role-local readiness evidence.
- Jenkins controller role setup is complete and
  `scripts/jenkins-controller-setup.sh validate` has produced controller-only
  readiness evidence.
- Jenkins agent role setup is complete and `scripts/jenkins-agent-setup.sh
  validate` has produced agent-host readiness evidence.
- Reviewed env files exist for Gerrit, Jenkins controller, Jenkins agent, and
  shared integration values.
- Env files have no placeholder values and have been reviewed for role/account
  separation, endpoints, ref patterns, labels, credential IDs, evidence paths,
  and verification mode labels.
- The shared integration env defines OS SSH access for the Gerrit target,
  Jenkins controller target, and Jenkins agent target.
- Operators have confirmed that any public internet fallback on target hosts is
  simulation-only and will be labeled that way in docs, logs, and evidence.

## Operator Inputs And Custody

Required operator inputs include:

- Reviewed Gerrit env file.
- Reviewed Jenkins controller env file.
- Reviewed Jenkins agent env file.
- Reviewed shared integration env file, normally copied from
  `examples/integration.env.example`.
- Gerrit admin credential or approved automation credential for creating the
  reviewed `All-Projects` label/config change and project/ref access change.
- Jenkins admin credential or approved automation credential for credential,
  Gerrit Trigger, node, and job configuration.
- Jenkins Gerrit integration account or group.
- Gerrit project and ref scope for Jenkins read and `label-Verified -1..+1`
  grants.
- Jenkins agent node name, scheduling label, executor policy, and remote
  filesystem values.
- Disposable verification project, branch, job, and run ID values.
- Target OS SSH inventory for Gerrit, Jenkins controller, and Jenkins agent:
  host, port, user, identity file, and known-hosts file.

Custody and redaction rules:

- Jenkins controller owns the Jenkins-to-Gerrit private key and the
  Jenkins-to-agent private key.
- Gerrit receives only the Jenkins-to-Gerrit public key.
- Jenkins agent receives only the Jenkins-to-agent public key.
- Evidence may record public key fingerprints, credential IDs that do not
  encode secrets, account names, endpoints, change numbers, build URLs, mode
  labels, and bounded log paths.
- Evidence must not include private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing env values.
- Verbose Gerrit, Jenkins, Docker, SSH, package-manager, VM, or verification
  logs must be written to bounded log files and referenced, not streamed.

## Standard Interfaces

The helper separates target OS access from service endpoints.

OS/control-plane access:

- Gerrit target OS access uses the Gerrit target SSH inventory.
- Jenkins controller target OS access uses the Jenkins controller target SSH
  inventory.
- Jenkins agent target OS access uses the Jenkins agent target SSH inventory.
- SSH-based file transfer, such as `scp` or `rsync`, is the standard path for
  public-key handoff, bounded payload upload, bounded log retrieval, and
  helper-generated state retrieval.

Service endpoints:

- Gerrit HTTP REST comes from the reviewed Gerrit role env and is used for
  account/key registration, config-review workflow, review posting, and state
  checks.
- Gerrit SSH comes from the reviewed Gerrit role env and is used for
  Jenkins-to-Gerrit authentication and `stream-events` proof.
- Jenkins HTTP/API/script access comes from the reviewed Jenkins controller
  role env and is used for credentials, nodes, trigger server, jobs, builds,
  and readiness operations.
- Jenkins controller-to-agent SSH comes from the reviewed Jenkins agent role
  env and is the runtime build-agent connection, not the operator
  control-plane SSH channel.

The implementation should expose neutral primitives equivalent to:

```text
target_exec <gerrit|jenkins-controller|jenkins-agent> <command>
target_copy_to <gerrit|jenkins-controller|jenkins-agent> <local> <remote>
target_copy_from <gerrit|jenkins-controller|jenkins-agent> <remote> <local>
target_run_as <gerrit|jenkins-controller|jenkins-agent> <account> <command>
```

Those primitives must use SSH plus `scp` or `rsync`. The integration helper
must not call Docker APIs, derive container names, or require
`HARNESS_PROJECT_NAME`. Docker simulation may use Docker APIs only to create,
start, stop, inspect, and wire the simulation; it must expose logical targets
through the same SSH and service interfaces used by VM simulation and
`target-deployment`.

Service API calls may originate from the control node or from a target over
SSH when network reachability requires it. Evidence must record the selected
origin when that origin affects interpretation of the proof.

## Gerrit ACL Modes

The shared helper supports these ACL workflow modes:

| Mode | Default environment | Behavior |
| --- | --- | --- |
| `create-review` | `target-deployment` | Create reviewable Gerrit config changes through REST, record change IDs and URLs, and stop until an external approved submit makes the label/access effective. |
| `create-review-and-submit` | `docker-simulation`, `vm-simulation` | Create the same Gerrit config review changes, auto-submit them under simulation policy, and then validate effective label/access state. |
| `apply-direct` | Explicit simulation-only fallback | Directly apply Gerrit REST label/access changes only when explicitly opted in and labeled `simulation-only direct Gerrit REST apply`. |

`target-deployment` validation must fail closed until the created review has
been submitted and Gerrit reports the global `Verified` label,
`stream-events`, and scoped `label-Verified -1..+1` permissions as effective.

`create-review-and-submit` is not a `target-deployment` default. It may be
introduced for `target-deployment` only by a future documented automation
policy with explicit approval and evidence requirements.

`apply-direct` must fail closed outside simulation modes. It is retained only
as an emergency or lab fallback and must not be the normal Docker or VM
simulation path.

## Helper Command Workflow

Set the shared env arguments once and reuse them for every helper command:

```bash
common_args=(
  --gerrit-env <reviewed-gerrit.env>
  --jenkins-controller-env <reviewed-jenkins-controller.env>
  --jenkins-agent-env <reviewed-jenkins-agent.env>
  --integration-env <reviewed-integration.env>
)
```

Review the Jenkins-to-Gerrit SSH plan without mutation:

```bash
scripts/integration-setup.sh "${common_args[@]}" --dry-run configure-integration
```

Apply Jenkins-to-Gerrit SSH setup after review:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes configure-integration
```

Validate cross-role readiness:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes validate-integration
```

Run end-to-end integration proof:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes prove-integration
```

Collect sanitized integration evidence:

```bash
scripts/integration-setup.sh "${common_args[@]}" collect-evidence
```

Use `--dry-run` only for planning commands. Dry runs must not create Gerrit or
Jenkins state, disposable projects, Jenkins jobs, credentials, nodes, review
votes, or evidence that claims runtime success.

## Validation Contract

`validate-integration` and `prove-integration` must prove real cross-role behavior
or fail closed with a clear classification. Passing integration evidence must
cover:

Current `validate-integration` evidence proves Docker simulation runtime
checks. `target-deployment` and other non-simulation evidence additionally requires
the global label and scoped vote permission checks below.

- Jenkins-to-Gerrit SSH authentication as the Jenkins Gerrit integration
  account.
- `stream-events` capability for Gerrit Trigger event consumption.
- Global `Verified` label exists in reviewed `All-Projects` configuration.
- Jenkins integration actor or group can vote `label-Verified -1..+1` on the
  reviewed project and ref scope.
- Jenkins-to-agent SSH authentication from the controller to the agent runtime
  account.
- Jenkins node readiness for the reviewed node name and executor policy.
- Jenkins job scheduling on the selected scheduling label.
- Gerrit REST review API posts `Verified +1` for the disposable verification
  change.
- Gerrit review state shows the expected `Verified +1` result on the
  disposable change and patch set.

Jenkins Gerrit Trigger must use SSH for authentication and `stream-events`.
REST vote posting does not replace the SSH event-stream proof.

## Evidence And Failure Classification

`collect-evidence` emits integration-scoped records using the common evidence
contract. Records must identify the verification mode, timestamp, command,
checkpoint, reviewed input fingerprint, public key fingerprints, credential
IDs where safe, endpoints, disposable artifact IDs, observed checks, bounded
log references, redaction status, and final status.

Classify failures at the point where proof breaks:

| Failure point | Classification |
| --- | --- |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` capability or Gerrit Trigger server connectivity failure. |
| Global `Verified` label is absent | `All-Projects` label definition failure. |
| Jenkins cannot vote `Verified -1..+1` on the reviewed ref scope | Project/ref access grant failure. |
| Jenkins cannot authenticate to the agent over SSH | Jenkins-to-agent SSH credential or agent authorization failure. |
| Jenkins node is offline or has the wrong executor/label state | Jenkins node readiness failure. |
| A `patchset-created` event is received but no build runs | Gerrit Trigger job mapping or Jenkins scheduling failure. |
| The build runs on the wrong label | Jenkins agent scheduling failure. |
| REST review API rejects the `Verified +1` vote | REST vote, label, or voting permission failure. |
| Gerrit review state does not show the expected vote | Gerrit review-state verification failure. |

Failed `Verified` voting must not be collapsed into SSH, stream-events, or job
scheduling failures. Legacy SSH review command use must be recorded as an
explicit exception with the operator justification and compatibility evidence
that made it acceptable for that run.
