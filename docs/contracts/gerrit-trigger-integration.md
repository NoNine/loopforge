# Gerrit Trigger Integration

This document defines the v1 contract for Gerrit Trigger integration between
Jenkins and Gerrit. It is based on the behavior digest in
`docs/references/reference-digest.md` and stays within the product boundary in
`docs/product/prd.md`.

The contract covers the integration account, SSH key custody, the reviewed
Gerrit ACL workflow, the `Verified` label, Gerrit Trigger controller settings,
default REST vote posting, disposable verification artifacts, failure
classification, and the simulation acceptance contract. It is a policy and
validation contract, not the command manual. Operators should use
`docs/operations/setup/integration.md` for the shared helper command workflow.

## Required State

Before shared integration mutation starts:

- Gerrit is running with LDAP-backed authentication.
- Jenkins is running with LDAP-backed human admin access.
- The Gerrit admin account is provisioned in Gerrit, not only present in LDAP.
- The test user account is provisioned in Gerrit, not only present in LDAP.
- Gerrit, Jenkins controller, and Jenkins agent role-readiness handoffs have
  passed for the same reviewed target inventory.
- `examples/integration.env.example` has been reviewed for the shared Jenkins
  integration group name, group GID, shared storage path, target project, ref
  pattern, node, labels, credential IDs, and ACL mode.

Before end-to-end verification starts:

- The Jenkins Gerrit integration account exists as a Gerrit service account,
  is separate from human administrator accounts, and belongs to the reviewed
  integration group.
- Both Gerrit configuration reviews are submitted and effective.
- Jenkins controller owns both integration private keys; Gerrit and the Jenkins
  agent consume only their matching public keys.
- Shared storage setup and its controller-write/agent-read setup check passed.
- The Jenkins agent is registered under the reviewed node name and is online
  with the selected scheduling label.
- Gerrit Trigger is configured with SSH event streaming and REST vote posting.

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

1. Integration preflight observes the three role-readiness handoffs, reviewed
   inputs, target inventory, administrator access, selected state, and ACL mode.
   Unsupported or unavailable behavior fails before mutation.
2. Gerrit creates or validates the Jenkins Gerrit integration service account
   and group. The account remains separate from human administrators.
3. Gerrit creates two reviewable configuration changes through REST: an
   `All-Projects` change for the global `Verified` label and `streamEvents`, and
   a target-project change for read and `label-Verified -1..+1` on the reviewed
   ref pattern.
4. `target-deployment` records both review identifiers and URLs, reports
   `blocked`, and stops without shared-setup success until both changes are
   externally approved and submitted. Docker and VM simulation create the same
   reviews and may auto-submit them under simulation policy.
5. A matching resume validates that both changes are effective before further
   mutation. The resume must use the same reviewed inputs, targets, ACL mode,
   selected state, and review identifiers.
6. Jenkins controller creates or validates the Jenkins-to-Gerrit and
   Jenkins-to-agent keypairs. Gerrit and the agent receive only the matching
   public keys, without truncating unrelated authorized keys.
7. Gerrit generates the initial HTTP auth token for the integration account.
   Jenkins stores the keys and token under its credential and Gerrit Trigger
   custody boundaries.
8. Shared setup creates or validates the shared group/GID, agent-hosted NFS
   export, controller mount, and setgid storage permissions, then records one
   bounded controller-write/agent-read setup result.
9. Jenkins registers the SSH agent node and configures Gerrit Trigger for SSH
   `stream-events` and REST review posting.
10. Cross-role validation observes effective ACLs, both read-only SSH paths,
    key custody, shared storage configuration, node configuration and online
    state, and Gerrit Trigger connection state. It does not create or repair
    target or application state.
11. End-to-end proof creates the labeled disposable verification job and one
    disposable Gerrit change. The change emits `patchset-created`, Gerrit
    Trigger schedules the job on the reviewed agent, and the successful build
    posts `Verified +1` through Gerrit REST.
12. Evidence records the reviewed-input and selected-state binding, both ACL
    reviews, public key fingerprints, shared storage result, change, build,
    event delivery, vote, bounded logs, and verification mode.

## State And Existing Credentials

Integration phase markers must bind to the reviewed input set, target
identities, mode, run or selected state, and both Gerrit review identifiers.
Marker existence without that binding does not satisfy a later prerequisite.

An expected target-deployment review wait may resume only with its original
bound reviews and inputs. This is the only resumable mutation boundary. Exact
input-bound completed integration state returns non-mutating
`already-complete`. Stale, partial, conflicting, changed, or unbound state
fails clearly and requires explicit cleanup, migration, site-owned credential
administration, or a fresh selected state.

Normal configuration must not delete or rotate an existing Gerrit token, key,
Jenkins credential, node, or agent authorization. It must not truncate
`authorized_keys` or delete Jenkins-agent role state.
Loopforge v1 does not perform rotation. Existing state that requires token,
key, or credential replacement blocks normal setup. A site may perform
rotation through its own separately controlled administration outside the
Loopforge v1 helper and native setup surfaces.

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
package. `target-deployment` label and ACL setup must create the reviewable
`All-Projects` and target-project changes through REST and must not auto-submit
them. Docker and VM simulation create the same two changes and may auto-submit
them under simulation policy. Direct editing of bare repositories is not the
automation path, even though `refs/meta/config/project.config` remains Gerrit's
underlying storage model. Dashboard or remote-management integrations should
use REST for the same reason.

Apply modes:

- `--dry-run` reads reviewed inputs and renders a bounded planned ACL summary
  without mutation.
- `create-review` is the `target-deployment` default. It creates Gerrit config
  reviews through REST, records change IDs and URLs, and waits for external
  approval/submission before validation can pass.
- `create-review-and-submit` is the Docker and VM simulation default. It
  creates the same Gerrit config reviews through REST, auto-submits them under
  simulation policy, and validates the effective label/access state.
- `apply-direct` is allowed only for explicitly labeled
  `simulation-only`, `docker-simulation`, or `vm-simulation` lab modes and
  requires explicit opt-in plus `--yes`. It must fail closed in
  `target-deployment` mode even when credentials would permit direct mutation.

Direct Gerrit REST label/access mutation is a simulation-only emergency or lab
fallback. It must be recorded in logs and evidence as
`simulation-only direct Gerrit REST apply` and must not be presented as
`target-deployment` reviewed ACL proof. This simulation allowance does not
permit direct `All-Projects.git` editing, direct site-Git mutation, direct
`refs/meta/config` Git editing, or `gerrit set-account` fallbacks.

Jenkins Gerrit Trigger uses SSH for `stream-events` and the Gerrit REST review
API for vote posting. The REST path authenticates as the Jenkins Gerrit
integration account with a Gerrit-generated HTTP auth token. Legacy SSH review
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

This waiver does not accept LDAP admin-group resolution as target-deployment
proof. It also does not waive Jenkins integration group validation,
`stream-events`, `Verified` label and voting proof, or the prohibition on
direct `All-Projects.git`, direct site-Git mutation, and `gerrit set-account`
fallbacks. Gerrit LDAP admin-group mapping must be fixed or separately
verified before LDAP admin-group resolution can be treated as target-deployment
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

The ACL workflow treats the Gerrit version in `docs/baselines/version-baseline.md` as
the v1 REST baseline. Non-default Gerrit versions may be used only when
runtime REST compatibility checks pass. If the server version or REST behavior
is unsupported, the helper must fail closed before any configuration mutation.

Evidence planning for ACL configuration records both review identifiers, URLs,
and revisions; the project/ref vote scope; ACL mode; Gerrit version; submit
actors when applicable; Jenkins integration actor or group; validation
results; service API origin; bounded log references; and redaction status.
Planned records must use `not-created` for review identifiers. A blocked review
wait records the real created review identifiers without claiming submission,
effective access, or shared setup success.

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

Docker and VM simulation may leave the disposable Gerrit verification change
open. The same change proves SSH event delivery, trigger and job mapping,
Jenkins agent execution, REST vote posting, and Gerrit review state. It may show
missing submit requirements because cleanup and submission are not part of the
current simulation evidence contract.

## Failure Classification

End-to-end verification must report these failures separately:

| Failure point | Report as |
| --- | --- |
| Integration mode or reviewed-change workflow is unsupported during preflight | Unsupported integration mode or ACL workflow; no mutation attempted. |
| Target-deployment reviews exist but either is not submitted and effective | `blocked` awaiting external Gerrit review approval/submission. |
| A later phase marker does not match the reviewed inputs, targets, mode, state, or review IDs | Integration state-binding failure. |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` permission or Gerrit Trigger server connectivity failure. |
| Global `Verified` label or `streamEvents` is absent | `All-Projects` reviewed-state failure. |
| Jenkins lacks read or `label-Verified -1..+1` on the reviewed project/ref | Target-project reviewed-access failure. |
| Jenkins cannot authenticate to the agent over SSH | Jenkins-to-agent credential or public-key authorization failure. |
| Shared group, export, mount, or setup-owned write/read result is wrong | Jenkins shared-storage setup failure. |
| Jenkins node is absent, offline, or has the wrong remote filesystem, executors, or labels | Jenkins node readiness failure. |
| A `patchset-created` event is received but no build runs | Jenkins verification job, trigger mapping, or agent scheduling failure. |
| The build runs but not on the selected Jenkins agent scheduling label | Jenkins agent scheduling failure. |
| The build succeeds but Gerrit rejects the REST review vote | REST vote, `Verified` label, or voting permission failure. |
| Gerrit review state does not show the expected vote from the integration account | Gerrit review-state verification failure. |

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
