## Step 4: Define The Operator Workflow Contract

Durable lifecycle behavior now lives in `docs/lifecycle-contract.md`. Keep
this implementation step as historical context only. Future changes to phase
order, checkpoint semantics, mutation boundaries, resume/rerun behavior, or
Docker command mapping belong in the lifecycle contract, not in this plan.

The cross-role command sequence belongs in `docs/integration-setup-manual.md`.
Gerrit Trigger, ACL, label, vote, and failure-classification behavior belongs
in `docs/gerrit-trigger-integration.md`. Account and credential custody
belongs in `docs/account-model.md`.

Verification:

```bash
test -f docs/lifecycle-contract.md
rg -n "Operator Workflow Contract|Lifecycle Checkpoints|Docker Command Mapping" docs/lifecycle-contract.md
rg -n "lifecycle-contract.md" docs/docs-management.md docs/system-model.md simulation/docker/README.md
rg -n "^[[:space:]]*(run|configure-controller-node)$" docs/implementation-plan.md
```

Acceptance criteria:

- The stable workflow contract is in `docs/lifecycle-contract.md`.
- This implementation plan does not embed the durable lifecycle authority.
- Consumer docs link to the lifecycle contract instead of redefining shared
  checkpoint semantics.

