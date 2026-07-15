# Native Operations Manual Review Guide

## Purpose

Use this guide to review a native role or integration manual without turning
the review into a helper or harness rewrite. Native manuals remain the direct
OS and application procedural baseline. This guide describes review method;
it does not own product, lifecycle, account, endpoint, artifact, security, or
validation facts.

Resolve authority through `docs/README.md` before changing a manual. Read the
relevant product, lifecycle, account, directory, endpoint, artifact, package,
validation, and integration authorities for the role under review.

## Review Status

Report these statuses separately:

- **Static review**: the manual agrees with its authorities, uses an
  operator-first procedure, and passes documentation contract tests.
- **Tool-resolution proof**: an external native tool assumption was executed
  and its result was reviewed, such as plugin dependency resolution.
- **Runtime acceptance**: the complete native procedure and its acceptance
  checks were exercised against a real target-like runtime.

Static review or tool-resolution proof must not be reported as runtime
acceptance. Record unproven runtime behavior and deferred helper alignment
explicitly.

## Review Sequence

Review one bounded lifecycle slice at a time:

1. Operator inputs and preflight.
2. Artifact preparation and target staging.
3. Runtime identity and installation.
4. Configuration and service startup.
5. Role-local validation.
6. Backup and operations.
7. Integration handoff.
8. Whole-document consistency.

Present findings and proposed alignment before changing uncertain behavior.
Keep security changes, helper alignment, and runtime verification as separate
tasks when combining them would make review or rollback unsafe.

## Authority And Scope Checks

- Identify the state the role must produce and the later workflow that
  consumes its handoff.
- Remove cross-role inputs, probes, mutations, and acceptance claims from
  role-local setup.
- Keep lifecycle order, mutation boundaries, stop conditions, and rerun rules
  aligned with `docs/contracts/lifecycle-contract.md`.
- Compare the manual with helpers, templates, tests, and harness behavior to
  find drift. Treat verified implementation as evidence, not automatic
  authority.
- Do not modify a working helper or harness merely to match an unproven manual.
  Record the mismatch for a separately approved, runtime-verified task.

## Operator Procedure Checks

- Trace every placeholder from the input inventory to each command and
  configuration consumer.
- Remove unused inputs and replace hardcoded values that override reviewed
  choices.
- Keep commands independently runnable, with inspectable output and an
  immediate expected result or stop condition.
- Prefer application and OS native validation over shell parsing.
- Reject broad diagnostic dumps, helper-like orchestration, masked failures,
  retries that hide defects, and unavailable tools.
- Check delegated privilege at the point of use; root is not a Loopforge
  account or direct login identity.

## State And Security Checks

- Search for destructive or recovery-like behavior such as `rm -rf`, implicit
  overwrite, hidden cleanup, stale-state fallback, and `|| true`.
- Require fresh selected state to fail clearly when it already exists. Cleanup,
  migration, and recovery remain explicit operator actions.
- Verify runtime, operator, human administrator, integration, test, and LDAP
  bind accounts remain separate.
- Verify security realm behavior, authorization entries, credential custody,
  bootstrap-account limitations, secret file permissions, and backup exposure.
- Ensure evidence, logs, checklists, and examples never include private keys,
  passwords, tokens, or LDAP bind secrets.

## Validation And Operations Checks

- Map every acceptance statement to an observable command or application UI
  check or to the successful result of its earlier owning checkpoint.
- Combine earlier identity, filesystem, artifact, and configuration outcomes
  with current service, endpoint, authentication, and application observations.
  Do not replay completed checkpoint operations during role validation.
- Prove external tool assumptions with the actual native tool when practical.
- Review backup and restore as production procedures: consistent capture,
  complete recovery unit, versioning, protected storage and transport, numeric
  ownership, and isolated restore testing.
- Keep role readiness distinct from shared integration and end-to-end proof.

## Regression And Completion

Add focused documentation tests that require the corrected contract and reject
the exact stale patterns found during review. Run the focused test first, then
adjacent documentation and acceptance contracts, shell syntax checks, and
`git diff --check`.

Before declaring the review complete, record:

- Manual and lifecycle slices reviewed.
- Authority or implementation drifts resolved.
- Native tool assumptions executed and their bounded evidence.
- Runtime behavior not yet exercised.
- Deferred helper, harness, security, or integration alignment.
- Final status using the three review-status terms above.
