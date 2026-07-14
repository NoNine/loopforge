## Step 1: Establish The Repository Structure

Create the package layout before porting behavior. Keep manuals, templates,
helpers, simulations, examples, and logs separated so future changes have
clear ownership.

Current structure:

```text
README.md
AGENTS.md
docs/
  README.md
  execution-status.md
  product/
    prd.md
  architecture/
    system-model.md
  contracts/
  baselines/
  operations/
    setup/
    native/
  planning/
    implementation-plan.md
    steps/
  references/
examples/
scripts/
templates/
simulation/
  README.md
  docs/
  docker/
  vm/
    docs/
logs/
```

Implementation notes:

- `README.md` is the top-level operator entrypoint and should orient new
  operators and reviewers to the setup flow, v1 boundaries, manuals,
  simulations, and validation evidence.
- `docs/` separates product, architecture, contracts, baselines, operations,
  planning, and reference material by ownership.
- `docs/execution-status.md` contains mutable repository resume state and is
  not part of the stable documentation authority tree.
- `examples/` contains reviewed env-file examples with placeholder values.
- `scripts/` contains helper commands that match manual phases.
- `templates/` contains service config, JCasC, job, and integration templates.
- `simulation/docker/` contains the first executable simulation model.
- `simulation/vm/` contains the later target-deployment verification model.
- `logs/` is used for local command logs and should not store committed
  verbose runtime output.

Verification:

```bash
test -f README.md
find . -maxdepth 1 -type f | sort
find docs project-state simulation -maxdepth 4 -type d | sort
find docs project-state simulation -maxdepth 4 -type f | sort
rg -n "air-gapped|offline-bundle" docs examples scripts templates simulation
```

Acceptance criteria:

- The directory layout exists and matches the structure above unless a later
  accepted documentation-organization change supersedes it.
- `README.md` exists as the top-level orientation document and points readers
  to the setup flow and v1 boundaries.
- Any `air-gapped` or `offline-bundle` match is reference-only, non-goal, or
  prohibition text; no supported v1 command or path uses those terms.
- `logs/` exists or is documented as a generated runtime directory.
