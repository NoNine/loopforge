# Loopforge Operations

Use this page to choose how you will install and configure Loopforge on target
hosts. You can follow the native OS and application procedures directly, or use
the repository helpers after reviewing their inputs and stop points.

Both paths are for initial setup. They must produce the same product state and
reach the same validation outcomes. They differ in who performs each operation
and how proof is produced. A human operator or reviewer accepts checkpoints for
both target-deployment paths and records those decisions in the applicable
checklist.

## Native Operation References

Use the native path when you will perform and review each OS and application
operation yourself. `native/` documents direct OS and application procedures
without repository helper commands or helper-equivalent workflows.

Choose the document for the target you are preparing:

- `native/gerrit.md`: install and validate the Gerrit role.
- `native/jenkins-controller.md`: install and validate the Jenkins controller.
- `native/jenkins-agent.md`: prepare and validate the outbound SSH agent host.
- `native/integration.md`: connect the three completed roles and prove the
  Gerrit-to-Jenkins workflow.

Perform commands in the documented order and stop when a prerequisite or
expected result does not match. Native validation is observational: it checks
the state you established without starting, repairing, or reconfiguring it.
The operator records the result in the native acceptance checklist; detailed
logs remain on the target hosts.

Open `native/acceptance-checklist.md` when beginning the fresh native run and
record checkpoint decisions progressively. After completing all four
procedures, use its final result for the single end-to-end native
`target-deployment` signoff. The checklist records outcomes without duplicating
commands or requiring helper-generated evidence.

## Setup Manuals

`setup/` documents repository-assisted setup workflows. Use this path when
reviewed inputs are ready and the Loopforge helpers are available for the
selected target mode.

Choose the manual that matches the role or integration work:

- `setup/gerrit.md`: review inputs, run the Gerrit helper phases, and validate
  the role.
- `setup/jenkins-controller.md`: review inputs, run the controller helper
  phases, and validate the role.
- `setup/jenkins-agent.md`: review inputs, run the agent helper phases, and
  validate the host.
- `setup/integration.md`: connect the completed roles and prove the shared
  workflow.

Each setup manual identifies its inputs, commands, stop points, effects, and
handoff. Review those details before invoking a helper. Helpers perform the
same initial setup scope as the native path and collect the redacted evidence
required for the selected mode.

For helper-assisted `target-deployment`, record each human checkpoint decision
in `setup/acceptance-checklist.md`. Passing structured helper results and
evidence support that decision but do not authorize the next target phase by
themselves. Docker and VM simulation use their run step ledgers
instead of a human target checklist.

## Before You Begin

- Start with freshly provisioned target state. Loopforge v1 does not reinstall,
  reconfigure, repair, or rotate credentials in existing product state.
- Use the operator account for control-plane work. Direct root login is not a
  supported Loopforge identity; privileged OS operations use delegated
  privilege.
- Review all declared inputs before mutation. Stop if an account, endpoint,
  credential, artifact, or selected mode differs from the approved input.
- OS dependency provisioning may occur before application artifacts are
  prepared and staged. Verify staged artifacts before creating runtime
  identities, product homes, application configuration, or services.
- Follow the phase, checkpoint, mutation, and reboot rules in
  `docs/contracts/lifecycle-contract.md`. Configuration establishes runtime
  state; validation observes it.

The helper returns non-mutating `already-complete` for exact input-bound completed state.
A native operator may likewise confirm only exact completed work that is bound
to the reviewed inputs. Stale, partial, conflicting, changed, or unrecognized
state is not resumable; stop for explicit operator action or begin again with
fresh selected state.

## Equivalent Outcomes

The native and helper paths may use different command sequences, but they must
agree on:

- runtime accounts and protected paths;
- reviewed and verified inputs;
- installed application and service configuration;
- credential-custody boundaries;
- role-local and integration ownership;
- validation results and secret redaction.
- human checkpoint acceptance and final deployment signoff for target
  deployment.

Gerrit and the Jenkins controller use systemd in VM simulation and target
deployment. The outbound Jenkins agent uses the target's SSH service and does
not require a separate Jenkins agent daemon.

Role setup ends with a role-readiness handoff. It does not create cross-role
keys or credentials, register the Jenkins node, configure the Gerrit trigger,
prove scheduling, or cast a Gerrit vote. Perform that work only after all three
roles are ready, using `native/integration.md` or `setup/integration.md`.

## Documentation And Support

Native references are the direct procedural baseline. Setup manuals describe
how the helpers apply that baseline. Helper scripts implement the setup-manual
interface, and simulation documentation explains how each backend realizes it.

Maintainers and reviewers use `native/review-guide.md` to review native manuals;
operators do not need that guide to perform a documented procedure.

This page owns the relationship between the native and helper paths. Detailed
lifecycle behavior belongs to `docs/contracts/lifecycle-contract.md`, and
evidence schemas belong to `docs/contracts/validation-and-evidence.md`. Current
implementation availability, blockers, and waivers are recorded in
`project-state/execution-status.md`.
