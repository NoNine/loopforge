## Step 3: Define The Simulation Model

Create the simulation model docs without duplicating the system, account,
source-boundary, or evidence authorities.

Step 3-owned files:

```text
simulation/docs/shared/simulation-model.md
simulation/docs/docker/docker-simulation.md
simulation/docs/vm/vm-simulation.md
```

Implementation notes:

- `simulation/docs/shared/simulation-model.md` owns the common five-environment topology, version
  baseline, source boundaries, generated-output conventions, and checkpoint
  meanings for simulation layers.
- `simulation/docs/docker/docker-simulation.md` owns Docker simulation command behavior and
  Docker-specific generated paths.
- `simulation/docs/vm/vm-simulation.md` owns VM simulation and future VM command
  behavior.
- The simulation docs must derive account usage from `docs/contracts/account-model.md`
  and mode terminology from `docs/architecture/system-model.md`.
- The bundle factory remains an environment, not a public helper API.
  Artifact preparation stays exposed through role helpers' `prepare-artifacts`
  commands.
- Do not port the reference repo's supported offline Ubuntu dependency bundle
  workflow into v1 simulation.

Verification:

```bash
test -f simulation/docs/shared/simulation-model.md
test -f simulation/docs/docker/docker-simulation.md
test -f simulation/docs/vm/vm-simulation.md
rg -n "bundle factory|LDAP|Gerrit|Jenkins controller|Jenkins agent|ci-operator" simulation/docs/shared/simulation-model.md simulation/docs/docker/docker-simulation.md simulation/docs/vm/vm-simulation.md
rg -n "docker-simulation|vm-simulation|target-deployment|simulation-only" simulation/docs/shared/simulation-model.md simulation/docs/docker/docker-simulation.md simulation/docs/vm/vm-simulation.md
rg -n "supported offline|offline Ubuntu|offline-bundle" simulation/docs/shared/simulation-model.md simulation/docs/docker/docker-simulation.md simulation/docs/vm/vm-simulation.md
```

Acceptance criteria:

- Simulation docs describe the shared topology and point to the account,
  system-model, source-boundary, and evidence authorities instead of redefining
  them.
- Docker is documented as the first full integration verification gate, and VM
  verification is documented as later work.
- Generated state, staged artifacts, evidence, and bounded logs are documented
  as generated output.
- No bundle factory helper or offline Ubuntu dependency bundle workflow is
  introduced.

