## Step 1: Establish The Repository Structure

Create the package layout before porting behavior. Keep manuals, templates,
helpers, simulations, examples, and logs separated so future changes have
clear ownership.

Planned structure:

```text
README.md
docs/
  prd.md
  implementation-plan.md
  references/reference-digest.md
  account-model.md
  gerrit-setup-manual.md
  jenkins-controller-setup-manual.md
  jenkins-agent-setup-manual.md
  gerrit-trigger-integration.md
  validation-and-evidence.md
examples/
  gerrit.env.example
  jenkins-controller.env.example
  jenkins-agent.env.example
scripts/
  common.sh
  gerrit-setup.sh
  jenkins-controller-setup.sh
  jenkins-agent-setup.sh
  collect-evidence.sh
templates/
  gerrit/
  jenkins-controller/
  jenkins-agent/
simulation/
  docker/
  vm/
logs/
```

Implementation notes:

- `README.md` is the top-level operator entrypoint and should orient new
  operators and reviewers to the setup flow, v1 boundaries, manuals,
  simulations, and validation evidence.
- `docs/` contains the operator-facing manuals and design references.
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
find docs examples scripts templates simulation -maxdepth 3 -type d | sort
find docs examples scripts templates simulation -maxdepth 3 -type f | sort
rg -n "air-gapped|offline-bundle" docs examples scripts templates simulation
```

Acceptance criteria:

- The directory layout exists and matches the structure above unless a later
  implementation note explicitly justifies a small naming change.
- `README.md` exists as the top-level orientation document and points readers
  to the setup flow and v1 boundaries.
- Any `air-gapped` or `offline-bundle` match is reference-only, non-goal, or
  prohibition text; no supported v1 command or path uses those terms.
- `logs/` exists or is documented as a generated runtime directory.

