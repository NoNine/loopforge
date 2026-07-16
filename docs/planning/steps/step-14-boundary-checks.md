## Step 14: Add Cross-Repository Boundary Checks

Run this step only after Step 13a fresh-state role lifecycle and Step 13b shared
integration lifecycle alignment are accepted. Boundary checks must inspect the
aligned helper and documentation surfaces rather than preserve earlier
reinstall, reconfigure, rotation, or unbound-rerun behavior.

Add a lightweight verification check that prevents old reference language from
re-entering v1 docs and helper command surfaces.

Recommended checks:

```bash
rg -n "strict air-gapped|supported offline|offline Ubuntu dependency|prepare-offline-deps|install-offline-deps" docs scripts templates simulation examples
rg -n "simulation-only" docs scripts templates simulation examples
rg -n "reinstall|reconfigure|rotate|idempotent target operations" docs scripts templates simulation examples
```

Implementation notes:

- Matches from the first command are acceptable only when they are
  reference-only, non-goal, or prohibition text.
- Historical source references may mention the old repo, but they must be
  clearly identified as reference-only or non-goal context.
- The second command should find explicit labels wherever public internet
  fallback appears in simulation.
- Matches from the third command are acceptable only in non-goals,
  prohibitions, historical context, site-owned administration boundaries, or
  tests that reject the old behavior.

Acceptance criteria:

- PRD non-goals are enforced by docs and helper interfaces.
- Simulation-only fallback is visibly labeled in docs, logs, and summaries.
- No helper exposes supported offline Ubuntu dependency bundle workflows.
- Role and integration helpers accept only fresh selected state or exact
  input-bound completed state, with only the Gerrit external-review wait
  resumable during mutation.
- No v1 helper or native setup procedure claims reinstall, reconfiguration,
  repair, or credential rotation support.
