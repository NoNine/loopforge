# Gerrit Trigger Integration

This document defines the v1 contract for Gerrit Trigger integration between
Jenkins and Gerrit. It is based on the behavior digest in
`docs/reference-digest.md` and stays within the product boundary in
`docs/prd.md`.

The contract covers the integration account, SSH key custody, the reviewed
Gerrit ACL workflow, the `Verified` label, Gerrit Trigger controller settings,
default REST vote posting, disposable verification artifacts, failure
classification, and the Docker simulation acceptance contract. It is a policy
and validation contract, not the command manual. Operators should use
`docs/integration-setup-manual.md` for the shared helper command workflow.

## Required State

Before Gerrit Trigger verification starts:

- Gerrit is running with LDAP-backed authentication.
- Jenkins is running with LDAP-backed human admin access.
- The Jenkins agent is registered under the reviewed node name and can run
  jobs on the selected scheduling label.
- The Jenkins Gerrit integration account exists as a Gerrit service account or
  is represented by a Gerrit group intended for automation.
- The Jenkins Gerrit integration account is separate from human Gerrit and
  Jenkins admin accounts.
- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.
- `examples/integration.env.example` has been reviewed for the shared Jenkins
  integration group name, group GID, and shared storage path.

Jenkins must authenticate to Gerrit as the Jenkins Gerrit integration account.
It must not use a human Jenkins admin or human Gerrit admin account for trigger
connectivity, `stream-events`, or `Verified` voting.

The shared integration helper also owns Jenkins controller and agent shared
storage setup. In Docker simulation it creates or validates the shared group
from `examples/integration.env.example` on both Jenkins containers, adds the
controller runtime account and agent runtime account to that group, makes the
configured shared storage path group-writable on both sides, and records a
controller-write/agent-read proof.

## Integration Sequence

1. Jenkins controller generates or receives the Jenkins-to-Gerrit SSH keypair
   through the controller integration-key workflow.
2. Gerrit receives only the Jenkins-to-Gerrit public key and associates it with
   the Jenkins Gerrit integration account.
3. Product-like setup defines the global `Verified` label in reviewed
   `All-Projects` configuration.
4. The operator chooses an explicit Gerrit project and ref scope for Jenkins
   read access and `label-Verified -1..+1` grants.
5. Gerrit grants `stream-events` as a global capability to the Jenkins Gerrit
   integration actor or group. Production-like setup uses reviewed Gerrit
   configuration changes created through the REST API and must not auto-submit
   them; Docker and VM simulation may use labeled direct Gerrit REST test
   automation.
6. Jenkins stores the controller-held private key as a credential. The
   credential ID may be recorded in evidence only when it does not encode a
   username, hostname, secret value, or other sensitive material.
7. The integration helper validates shared Jenkins controller/agent storage
   using `examples/integration.env.example`.
8. Jenkins configures a Gerrit Trigger server that connects as the Jenkins
   Gerrit integration account.
9. Jenkins registers a disposable verification job that responds to
   `patchset-created`.
10. Verification creates a disposable Gerrit project and change labeled as
   verification artifacts.
11. The disposable change emits a `patchset-created` event.
12. Jenkins receives the event and schedules the verification job on the
    selected Jenkins agent scheduling label.
13. The job runs on the Jenkins agent and Jenkins posts `Verified +1` to the
    Gerrit change through the Gerrit REST review API.
14. Evidence records the shared storage proof, change, build, vote, and
    verification mode.

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

REST API is the selected Gerrit configuration and review interface for the
package. Production-like label and ACL setup must create reviewable Gerrit
config changes through REST and must not auto-submit them. Direct editing of
`All-Projects.git` is not the automation path, even though
`refs/meta/config/project.config` remains Gerrit's underlying storage model.
Dashboard or remote-management integrations should use REST for the same
reason.

Apply modes:

- `--dry-run` reads reviewed inputs and renders a bounded planned ACL summary
  without mutation.
- `--create-review` is the production-like path. It creates a Gerrit config
  review through REST when real implementation is available, and it never
  auto-submits.
- `--apply-direct` is allowed only for explicitly labeled
  `simulation-only`, `docker-harness-simulation`, or `vm-simulation` lab
  modes and requires `--yes`. It must fail closed in `production-like` mode
  even when credentials would permit direct mutation.

Docker and VM simulation may use direct Gerrit REST calls for test automation,
including label, access, disposable project, and disposable verification setup,
when the run is explicitly labeled as simulation-only. Direct REST simulation
automation must be recorded in logs and evidence as simulation behavior and
must not be presented as production-like reviewed ACL proof. This simulation
allowance does not permit direct `All-Projects.git` editing, direct site-Git
mutation, direct `refs/meta/config` Git editing, or `gerrit set-account`
fallbacks.

Jenkins Gerrit Trigger uses SSH for authentication and `stream-events`. The
default vote posting path is the Gerrit REST review API. Legacy SSH review
commands or flags are not part of the default workflow; they require explicit
operator justification and compatibility evidence for the installed Gerrit and
Gerrit Trigger versions. The event stream still proves Jenkins-to-Gerrit SSH
and `stream-events`; REST vote posting is validated as the review API path.

### Docker Simulation Waiver: Gerrit Admin LDAP Group Resolution

Scope: Docker Step 11 only.

The Docker simulation seeds an LDAP `gerrit-admins` group, but the observed
Step 11 Docker run did not expose that LDAP group in `gerrit-admin` REST group
membership. For Step 11 Docker simulation only, Gerrit admin rights may be
bootstrapped through Gerrit's documented first-registered-user internal
`Administrators` behavior and repaired through Gerrit REST group membership.

This waiver does not accept LDAP admin-group resolution as production-like
proof. It also does not waive Jenkins integration group validation,
`stream-events`, `Verified` label and voting proof, or the prohibition on
direct `All-Projects.git`, direct site-Git mutation, and `gerrit set-account`
fallbacks. Gerrit LDAP admin-group mapping must be fixed or separately
verified before LDAP admin-group resolution can be treated as production-like
evidence.

Gerrit must grant the Jenkins Gerrit integration actor or group:

- A global `Verified` label definition in reviewed `All-Projects`
  configuration.
- Read access on the verification project and any project pattern under test.
- Permission to vote `label-Verified -1..+1` on the reviewed project/ref scope.
- `stream-events` capability as a global capability grant so Gerrit Trigger can
  receive events.

The Gerrit admin account may apply the access configuration, but the granted
actor must be the Jenkins Gerrit integration account or group. The human admin
account must not be configured as the Gerrit Trigger identity.

The ACL workflow treats Gerrit `3.13.6` as the v1 REST baseline. Later Gerrit
versions may be used only when runtime REST compatibility checks pass. If the
server version or REST behavior is unsupported, the helper must fail closed
before any configuration mutation.

Evidence planning for ACL configuration records the `All-Projects` label
configuration review, the project/ref vote scope, apply mode, Gerrit version,
Gerrit review change and revision when one exists, Jenkins integration actor or
group, validation results, bounded log references, and redaction status.
Planned or blocked records must use `not-created` for review identifiers rather
than implying a review was opened.

Shared storage evidence records the shared group name, GID, storage path, the
controller runtime account as writer, the agent runtime account as reader, and
bounded log references. It must not include private keys, passwords, tokens,
or LDAP bind secrets.

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

Docker and VM simulation may leave disposable Gerrit changes open. The
`stream-events` validation changes prove real event streaming from Gerrit to
Jenkins. The verification change proves the trigger, Jenkins job mapping,
Jenkins agent execution, REST vote posting, and Gerrit review state. These
changes may show missing submit requirements because cleanup and submission are
not part of the current simulation evidence contract.

## Failure Classification

End-to-end verification must report these failures separately:

| Failure point | Report as |
| --- | --- |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` permission or Gerrit Trigger server connectivity failure. |
| A `patchset-created` event is received but no build runs | Jenkins verification job, trigger mapping, or agent scheduling failure. |
| The build runs but not on the selected Jenkins agent scheduling label | Jenkins agent scheduling failure. |
| The build succeeds but Gerrit rejects the REST review vote | REST vote, `Verified` label, or voting permission failure. |

Failed `Verified` voting must not be collapsed into event-stream or
job-scheduling failures. It is a distinct label-definition or access-control
problem.

## Docker Simulation Acceptance Contract

The Docker simulation acceptance contract for this integration is:

- A disposable Gerrit change emits a `patchset-created` event.
- The shared Jenkins storage path is mounted into both Jenkins controller and
  Jenkins agent containers, and a controller-write/agent-read proof succeeds.
- Jenkins receives the event and schedules the disposable verification job.
- The job runs on the Jenkins agent.
- Jenkins posts `Verified +1` to the Gerrit change through the Gerrit REST
  review API.
- Evidence records the change, build, vote, bounded log references, and
  verification mode.

This document defines the acceptance contract only. It does not claim that the
Docker simulation has been executed.
