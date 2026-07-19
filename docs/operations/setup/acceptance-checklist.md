# Helper-Assisted Target-Deployment Acceptance Checklist

Use this checklist for one fresh helper-assisted `target-deployment` acceptance
run. The human operator or reviewer is the checkpoint acceptance authority.
Helper producer records, exit statuses, evidence packages, and summaries are
inputs to the decisions below; none is an acceptance record by itself.

This checklist defines the acceptance surface when helper-assisted target
deployment is available; its presence does not claim that unimplemented helper
behavior is supported. Consult `project-state/execution-status.md` for current
implementation availability.

Follow the detailed procedures in:

- `docs/operations/setup/gerrit.md`
- `docs/operations/setup/jenkins-controller.md`
- `docs/operations/setup/jenkins-agent.md`
- `docs/operations/setup/integration.md`

Retain the completed checklist in the approved change-management system, not
in the repository. Record only redacted references. Do not place passwords,
tokens, private keys, LDAP bind secrets, or secret-bearing configuration in
this checklist.

## Deployment

```text
Operator:
Reviewer:
Date:
Change/ticket:
Loopforge revision:
Reviewed input-set reference:
```

## Decision Rules

Mark a product checkpoint instance `ACCEPTED` only after reviewing its producer
outcome and proof, input and target binding, and required accepted predecessor.
Mark it `BLOCKED` when any required result or proof is missing,
failed, stale, contradictory, or bound to different state. Do not proceed to a
later target-deployment checkpoint from evidence `pass` alone.

The checklist may be completed progressively. Every applicable row must be
`ACCEPTED` before final signoff. Use `NOT-APPLICABLE` only where the lifecycle
contract permits it.

## Input And Role Decisions

```text
Input review or source selection
  Result: ACCEPTED / BLOCKED
  Reviewed reference:

OS dependency provisioning
  Gerrit:             ACCEPTED / BLOCKED    Reference:
  Jenkins controller: ACCEPTED / BLOCKED    Reference:
  Jenkins agent:      ACCEPTED / BLOCKED    Reference:

Artifact preparation
  Gerrit:             ACCEPTED / BLOCKED    Reference:
  Jenkins controller: ACCEPTED / BLOCKED    Reference:
  Jenkins agent:      ACCEPTED / BLOCKED    Reference:

Artifact staging
  Gerrit:             ACCEPTED / BLOCKED    Reference:
  Jenkins controller: ACCEPTED / BLOCKED    Reference:
  Jenkins agent:      ACCEPTED / BLOCKED    Reference:

Role-local setup
  Gerrit:             ACCEPTED / BLOCKED    Reference:
  Jenkins controller: ACCEPTED / BLOCKED    Reference:
  Jenkins agent:      ACCEPTED / BLOCKED    Reference:

Role-local validation
  Gerrit:             ACCEPTED / BLOCKED    Reference:
  Jenkins controller: ACCEPTED / BLOCKED    Reference:
  Jenkins agent:      ACCEPTED / BLOCKED    Reference:
```

## Integration Decisions

```text
Integration preflight
  Result: ACCEPTED / BLOCKED
  Reference:

Reviewed integration access
  Result: ACCEPTED / BLOCKED
  All-Projects review:
  Target-project review:

Shared integration setup
  Result: ACCEPTED / BLOCKED
  Reference:

Cross-role validation
  Result: ACCEPTED / BLOCKED
  Reference:

End-to-end trigger verification
  Result: ACCEPTED / BLOCKED
  Gerrit verification change:
  Jenkins verification build:
```

## Evidence Audit And Final Result

- [ ] Every applicable product checkpoint instance above has an accepted human
  decision.
- [ ] Completion and evidence references bind to the same reviewed inputs,
  target identities, mode, and selected execution state.
- [ ] Evidence outcomes contain no contradictory success and failure signals.
- [ ] Bounded log, artifact manifest, and checksum references are present where
  required.
- [ ] The final global evidence package covers the complete reached checkpoint
  set and passed its evidence-audit validation.
- [ ] Evidence and this checklist contain no secret values.

The global evidence package is required supporting material for this
helper-assisted review. Its successful collection does not accept Evidence
audit or the deployment; the human decision below does.

```text
Global evidence package reference:
Evidence audit: ACCEPTED / BLOCKED
Final result: ACCEPTED / BLOCKED
Reviewer:
Decision timestamp:
Notes:
```
