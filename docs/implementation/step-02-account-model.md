## Step 2: Define The Account Model

Create and maintain `docs/account-model.md` as the account authority for v1.
The implementation plan must not duplicate the account taxonomy, source
classification, credential custody rules, or separation rules.

Implementation notes:

- Topic docs, examples, templates, and helpers must use the account roles and
  custody boundaries from `docs/account-model.md`.
- `docs/system-model.md` may place accounts in the end-to-end system, but
  `docs/account-model.md` owns account definitions and separation rules.
- Keep examples account-name neutral where possible.

Verification:

```bash
rg -n "runtime|admin|integration|test user|LDAP|bind" docs/account-model.md
rg -n "air-gapped|offline bundle|offline-bundle" docs/account-model.md
```

Acceptance criteria:

- `docs/account-model.md` defines product accounts, the shared integration
  group, the simulation environment account, and credential custody.
- Topic docs reference the account model instead of restating the full
  taxonomy.
- Any offline-related match is reference-only, non-goal, or prohibition text.

