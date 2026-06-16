# Gerrit Trigger Integration

This document defines the v1 contract for Gerrit Trigger integration between
Jenkins and Gerrit. It is based on the behavior digest in
`docs/reference-digest.md` and stays within the product boundary in
`docs/prd.md`.

The contract covers the integration account, SSH key custody, Gerrit
permissions, the `Verified` label, Gerrit Trigger controller settings,
disposable verification artifacts, failure classification, and the Docker
simulation acceptance contract. It does not execute the Docker simulation.

## Required State

Before Gerrit Trigger verification starts:

- Gerrit is running with LDAP-backed authentication.
- Jenkins is running with LDAP-backed human admin access.
- The Jenkins agent is registered and can run jobs on the reviewed agent label.
- The Jenkins Gerrit integration account exists as a Gerrit service account or
  is represented by a Gerrit group intended for automation.
- The Jenkins Gerrit integration account is separate from human Gerrit and
  Jenkins admin accounts.
- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.

Jenkins must authenticate to Gerrit as the Jenkins Gerrit integration account.
It must not use a human Jenkins admin or human Gerrit admin account for trigger
connectivity, `stream-events`, or `Verified` voting.

## Integration Sequence

1. Jenkins controller generates or receives the Jenkins-to-Gerrit SSH keypair
   through the controller integration-key workflow.
2. Gerrit receives only the Jenkins-to-Gerrit public key and associates it with
   the Jenkins Gerrit integration account.
3. Gerrit defines the `Verified` label in project configuration.
4. Gerrit grants read access, `stream-events`, and `Verified` voting permission
   to the Jenkins Gerrit integration actor or group.
5. Jenkins stores the controller-held private key as a credential. The
   credential ID may be recorded in evidence only when it does not encode a
   username, hostname, secret value, or other sensitive material.
6. Jenkins configures a Gerrit Trigger server that connects as the Jenkins
   Gerrit integration account.
7. Jenkins registers a disposable verification job that responds to
   `patchset-created`.
8. Verification creates a disposable Gerrit project and change labeled as
   verification artifacts.
9. The disposable change emits a `patchset-created` event.
10. Jenkins receives the event and schedules the verification job on the
    Jenkins agent label.
11. The job runs on the Jenkins agent and Jenkins posts `Verified +1` to the
    Gerrit change.
12. Evidence records the change, build, vote, and verification mode.

## Templates

Step 5 provides declarative templates for the later Gerrit and Jenkins helper
steps. They are placeholders for reviewed operator values and are not
standalone executable automation.

| Template | Purpose |
| --- | --- |
| `templates/gerrit/verified-label.config.template` | Defines the Gerrit `Verified` label shape. |
| `templates/gerrit/jenkins-integration-access.config.template` | Documents read, `stream-events`, and `Verified` voting permissions for the Jenkins Gerrit integration actor or group. |
| `templates/gerrit/disposable-verification-change.env.template` | Captures disposable Gerrit verification project/change inputs. |
| `templates/jenkins-controller/gerrit-trigger-server.yaml.template` | Captures Jenkins Gerrit Trigger server settings and credential references. |
| `templates/jenkins-controller/disposable-verification-job.yaml.template` | Captures the disposable Jenkins verification job that responds to `patchset-created`. |

Operators must replace placeholders with reviewed environment values before
using these templates in later helper steps.

## Gerrit Permissions

Gerrit must grant the Jenkins Gerrit integration actor or group:

- Read access on the verification project and any project pattern under test.
- `stream-events` capability so Gerrit Trigger can receive events.
- Permission to vote `Verified -1..+1` on the verification project or intended
  project scope.

The Gerrit admin account may apply the access configuration, but the granted
actor must be the Jenkins Gerrit integration account or group. The human admin
account must not be configured as the Gerrit Trigger identity.

## Disposable Verification Artifacts

Verification may create disposable projects, Jenkins jobs, and Gerrit changes.
Every disposable artifact must be clearly labeled as a verification artifact in
its name, description, or metadata.

Recommended naming pattern:

```text
verification-disposable-<run-id>
```

The run ID should be recorded in evidence with the verification mode. Evidence
may record project names, change numbers, build URLs, public key fingerprints,
bounded log paths, and sanitized config fingerprints. Credential IDs may be
recorded only when they do not encode usernames, hostnames, secret values, or
other sensitive material. Evidence must not include private keys, passwords,
tokens, LDAP bind secrets, or verbose logs.

## Failure Classification

End-to-end verification must report these failures separately:

| Failure point | Report as |
| --- | --- |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` permission or Gerrit Trigger server connectivity failure. |
| A `patchset-created` event is received but no build runs | Jenkins verification job, trigger mapping, or agent scheduling failure. |
| The build runs but not on the Jenkins agent label | Jenkins agent scheduling failure. |
| The build succeeds but Gerrit rejects the review command | `Verified` label or voting permission failure. |

Failed `Verified` voting must not be collapsed into event-stream or
job-scheduling failures. It is a distinct label-definition or access-control
problem.

## Docker Simulation Acceptance Contract

The Docker simulation acceptance contract for this integration is:

- A disposable Gerrit change emits a `patchset-created` event.
- Jenkins receives the event and schedules the disposable verification job.
- The job runs on the Jenkins agent.
- Jenkins posts `Verified +1` to the Gerrit change.
- Evidence records the change, build, vote, bounded log references, and
  verification mode.

This document defines the acceptance contract only. It does not claim that the
Docker simulation has been executed.
