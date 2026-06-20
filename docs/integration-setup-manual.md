# Shared Integration Setup Manual

## Purpose And Scope

This manual is the operator guide for `scripts/integration-setup.sh`. Use it
after the Gerrit, Jenkins controller, and Jenkins agent role setup manuals have
completed and each role has passing role-local readiness evidence.

The current helper implementation is Docker simulation-only. Product-like
behavior described in this manual is the target contract until non-simulation
shared integration support exists.

The shared integration helper owns cross-role work only: Jenkins-to-Gerrit SSH,
Jenkins-to-agent SSH, Gerrit Trigger configuration, Jenkins node readiness,
trigger verification, `Verified` voting, and integration evidence. It does not
replace the role setup manuals and it does not provide native OS operation
instructions.

Product-like workflow defaults to a global `Verified` CI label in reviewed
`All-Projects` configuration. Jenkins read access and `label-Verified -1..+1`
grants stay scoped to the reviewed project and ref pattern. The `stream-events`
permission remains a global capability grant. Jenkins Gerrit Trigger uses SSH
for authentication and event streaming, while the Gerrit REST review API is the
default path for posting `Verified` votes.

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
scripts/integration-setup.sh "${common_args[@]}" --dry-run configure-gerrit-ssh
```

Apply Jenkins-to-Gerrit SSH setup after review:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes configure-gerrit-ssh
```

Review the Jenkins-to-agent SSH and node plan without mutation:

```bash
scripts/integration-setup.sh "${common_args[@]}" --dry-run configure-agent-ssh
```

Apply Jenkins-to-agent SSH and node setup after review:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes configure-agent-ssh
```

Review Gerrit Trigger server, disposable job, and vote-posting configuration
without mutation:

```bash
scripts/integration-setup.sh "${common_args[@]}" --dry-run configure-trigger
```

Apply Gerrit Trigger server, disposable job, and REST vote-posting
configuration after review:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes configure-trigger
```

Validate cross-role readiness:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes validate-integration
```

Run end-to-end trigger verification:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes verify-trigger
```

Collect sanitized integration evidence:

```bash
scripts/integration-setup.sh "${common_args[@]}" collect-evidence
```

Use `--dry-run` only for planning commands. Dry runs must not create Gerrit or
Jenkins state, disposable projects, Jenkins jobs, credentials, nodes, review
votes, or evidence that claims runtime success.

## Validation Contract

`validate-integration` and `verify-trigger` must prove real cross-role behavior
or fail closed with a clear classification. Passing integration evidence must
cover:

Current `validate-integration` evidence proves Docker simulation runtime
checks. Product-like and other non-simulation evidence additionally requires
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
