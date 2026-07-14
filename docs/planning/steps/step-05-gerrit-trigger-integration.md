## Step 5: Define Gerrit Trigger Integration

Use the trigger behavior summarized in `docs/references/reference-digest.md` as source
material, and make `docs/contracts/gerrit-trigger-integration.md` the topic authority
for Gerrit Trigger, ACL, label, vote, and failure-classification behavior.

Create `docs/contracts/gerrit-trigger-integration.md` and templates for:

- Gerrit `Verified` label definition.
- Gerrit access permissions for the Jenkins integration actor.
- Jenkins Gerrit Trigger server configuration.
- Disposable Jenkins verification job.
- Disposable Gerrit verification project/change.

Implementation notes:

- Keep detailed ACL, `All-Projects`, `Verified`, `stream-events`, REST vote,
  disposable artifact, and failure-classification policy in
  `docs/contracts/gerrit-trigger-integration.md`, not in this implementation plan.
- Templates must remain placeholders for reviewed operator values and must not
  become standalone automation.
- Cross-role helper command workflow belongs in `docs/operations/setup/integration.md`.

Verification:

```bash
rg -n "Verified|Gerrit Trigger|stream-events|patchset-created|integration" docs/contracts/gerrit-trigger-integration.md templates scripts simulation
```

Acceptance criteria:

- The trigger topic doc defines the integration contract and Docker simulation
  acceptance behavior.
- This implementation plan does not duplicate the topic doc's ACL or voting
  policy.

