# Native Target-Deployment Acceptance Checklist

Use this checklist for one fresh native `target-deployment` acceptance run in
a production-equivalent acceptance environment. The operator follows the
detailed procedures in:

- `docs/operations/native/gerrit.md`
- `docs/operations/native/jenkins-controller.md`
- `docs/operations/native/jenkins-agent.md`
- `docs/operations/native/integration.md`

This checklist records outcomes only. It does not replace or duplicate the
native procedures. It does not require machine-generated evidence, copied
service logs, or repository automation. Detailed logs remain in their normal
target locations and are inspected when a check fails.

The acceptance operator should not be an author of the native procedures. Mark
an item complete only after observing the documented result. Every required
item must pass. Reboot checks are optional and may be left unchecked when not
performed. If a reboot check is attempted, mark it complete only after it
passes; a failed optional reboot check makes the run `BLOCKED`. Any other
failed or undocumented step also makes the run `BLOCKED`.
Never repair service state during validation. Correct the owning procedure or
environment explicitly, provision fresh target state, and start a new
checklist.

## Deployment

```text
Operator:
Date:
Change/ticket:
Loopforge revision:
```

## Preparation

- [ ] The run uses freshly provisioned target hosts with no prior Gerrit,
  Jenkins, or Loopforge runtime state.
- [ ] The control node, bundle factory, Gerrit target, Jenkins controller
  target, Jenkins agent target, and approved non-simulation LDAP service are
  identified in the reviewed inventory.
- [ ] Operator access, delegated privileges, runtime accounts, package
  sources, DNS, time, routes, storage, and target-to-target connectivity are
  ready.
- [ ] Backup, rollback, and approval owners are recorded in the change/ticket.
- [ ] Reviewed artifact inventories and checksums match the artifacts staged on
  each target.

## Checkpoint Decisions

The checklist items below are observations. The operator records an acceptance
decision for each applicable product checkpoint instance only after its
required observations and procedure result are complete. A passing observation
does not authorize the next checkpoint until the decision is recorded.
Complete these decisions progressively during the run; do not reconstruct them
only at final signoff.

```text
Input review or source selection: ACCEPTED / BLOCKED

OS dependency provisioning
  Gerrit:             ACCEPTED / BLOCKED
  Jenkins controller: ACCEPTED / BLOCKED
  Jenkins agent:      ACCEPTED / BLOCKED

Artifact preparation
  Gerrit:             ACCEPTED / BLOCKED
  Jenkins controller: ACCEPTED / BLOCKED
  Jenkins agent:      ACCEPTED / BLOCKED

Artifact staging
  Gerrit:             ACCEPTED / BLOCKED
  Jenkins controller: ACCEPTED / BLOCKED
  Jenkins agent:      ACCEPTED / BLOCKED

Role-local setup - Gerrit:         ACCEPTED / BLOCKED
Role-local setup - Jenkins controller: ACCEPTED / BLOCKED
Role-local setup - Jenkins agent:  ACCEPTED / BLOCKED
Role-local validation - Gerrit:    ACCEPTED / BLOCKED
Role-local validation - Jenkins controller: ACCEPTED / BLOCKED
Role-local validation - Jenkins agent: ACCEPTED / BLOCKED
Integration preflight:             ACCEPTED / BLOCKED
Reviewed integration access:       ACCEPTED / BLOCKED
Shared integration setup:          ACCEPTED / BLOCKED
Cross-role validation:              ACCEPTED / BLOCKED
End-to-end trigger verification:   ACCEPTED / BLOCKED
Evidence audit:                    ACCEPTED / BLOCKED
```

Decision reviewer:
Decision date:

## Gerrit

- [ ] The native Gerrit installation and configuration procedure completed.
- [ ] The Gerrit systemd unit is enabled and active under the reviewed runtime
  account.
- [ ] The Gerrit HTTP and SSH endpoints respond as documented.
- [ ] The reviewed LDAP administrator and test user can sign in.
- [ ] Optional reboot check: Gerrit returns to the same ready state after a
  reviewed reboot.

## Jenkins Controller

- [ ] The native Jenkins controller installation and configuration procedure
  completed.
- [ ] The Jenkins systemd unit is enabled and active under the reviewed runtime
  account.
- [ ] The Jenkins HTTP and API endpoints respond as documented.
- [ ] The reviewed LDAP administrator can sign in.
- [ ] Required plugins load without errors and the active Jenkins configuration
  matches the reviewed JCasC or UI-driven configuration.
- [ ] The built-in node has zero executors.
- [ ] Optional reboot check: Jenkins returns to the same ready state after a
  reviewed reboot.

## Jenkins Agent

- [ ] The native Jenkins agent preparation procedure completed.
- [ ] The target SSH service is enabled and active.
- [ ] The reviewed runtime account and workspace ownership are correct.
- [ ] Java is available.
- [ ] Optional reboot check: The agent target returns to the same ready state
  after a reviewed reboot.

## Integration

- [ ] Jenkins-held private keys remain on the Jenkins controller and only the
  matching public keys were transferred.
- [ ] Jenkins-to-Gerrit SSH authentication succeeds as the reviewed integration
  account.
- [ ] Gerrit `stream-events` succeeds for the reviewed integration account.
- [ ] The reviewed `Verified` label and project/ref permissions are effective.
- [ ] Jenkins-to-agent SSH authentication succeeds from the controller.
- [ ] The Jenkins agent node is online with the reviewed label and executor
  count.
- [ ] Shared Jenkins storage passes the documented controller/agent read-write
  check.

## End-To-End Result

- [ ] A disposable Gerrit change triggered the reviewed Jenkins job.
- [ ] The build ran on the reviewed Jenkins agent, not the controller.
- [ ] The build completed successfully.
- [ ] Gerrit shows `Verified +1` on the expected change and patch set.
- [ ] Both Gerrit event delivery and the final review vote were observed.

```text
Gerrit verification change:
Jenkins verification build:
Result: ACCEPTED / BLOCKED
Notes:
Reviewer:
```

Do not place passwords, tokens, private keys, LDAP bind secrets, or
secret-bearing configuration in this checklist or its three references.
