## Step 10: Standardize Validation And Evidence Collection

Create `docs/validation-and-evidence.md` and `scripts/collect-evidence.sh`.
The topic doc owns evidence schema, mode labels, redaction rules, producer
responsibilities, review guidance, and aggregation behavior.

Implementation notes:

- Role-local `collect-evidence` commands from Steps 7, 8, and 9 must emit
  records that conform to `docs/validation-and-evidence.md`.
- `scripts/collect-evidence.sh` validates and aggregates role-local records,
  Docker/VM simulation utility records, and end-to-end integration records into
  the final evidence package.
- Do not store secrets in evidence.
- Do not stream verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, or
  verification logs into normal command output.

Verification:

```bash
bash -n scripts/collect-evidence.sh
scripts/collect-evidence.sh --help
rg -n "Evidence Contract|role-local|aggregate|simulation-only|target-deployment|checksums|Verified|LDAP|agent" docs/validation-and-evidence.md scripts/collect-evidence.sh
```

Acceptance criteria:

- Global evidence collection can be run after role-specific validation and after
  full integration validation.
- Global evidence collection consumes role-local evidence from Gerrit, Jenkins
  controller, and Jenkins agent helpers, plus Docker/VM simulation utility
  evidence when present.
- Evidence summaries follow `docs/validation-and-evidence.md` and omit or
  redact secret-looking values.

