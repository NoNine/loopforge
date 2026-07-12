## Step 15: Final End-To-End Acceptance

Run final acceptance in this order:

1. Static docs and shell checks.
2. Helper `--help`, `print-env-template`, and `--dry-run preflight` checks.
3. Docker simulation preflight and setup phases through `simulate.sh`.
4. Docker full verification through `simulate.sh`.
5. Global evidence aggregation.
6. Shared simulation library checks from Step 12.
7. VM simulation checks from Step 13 when VM implementation is in scope.

Retained rendered inputs, prepared artifacts, staged artifacts, and harness
state may be reused only when manifests and checksums verify against the current
reviewed inputs and implementation commit. If reusable state is absent or
invalid, rerun rendering, artifact preparation, and artifact staging before
Docker verification.

Minimum command set:

```bash
bash -n scripts/*.sh simulation/docker/simulate.sh simulation/vm/*.sh
scripts/gerrit-setup.sh --help
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-agent-setup.sh --help
scripts/integration-setup.sh --help
scripts/collect-evidence.sh --help
simulation/docker/simulate.sh preflight
simulation/docker/simulate.sh init-run
simulation/docker/simulate.sh create
simulation/docker/simulate.sh up
simulation/docker/simulate.sh prepare-artifacts
simulation/docker/simulate.sh stage-artifacts
simulation/docker/simulate.sh configure-role
simulation/docker/simulate.sh validate-role
simulation/docker/simulate.sh configure-integration
simulation/docker/simulate.sh validate-integration
simulation/docker/simulate.sh prove-integration
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes validate-integration
scripts/integration-setup.sh --gerrit-env examples/gerrit.env.example --jenkins-controller-env examples/jenkins-controller.env.example --jenkins-agent-env examples/jenkins-agent.env.example --integration-env examples/integration.env.example --yes prove-integration
scripts/collect-evidence.sh
simulation/docker/simulate.sh down
simulation/docker/simulate.sh destroy
simulation/vm/simulate.sh --help
simulation/vm/simulate.sh preflight --env simulation/vm/examples/vm.env.example
```

When Step 13 is in scope for the release, also run the VM lifecycle through
`prove-integration`, `reboot --all`, `down`, and `clean` in an approved VM
environment. When Step 13 is not in scope, final acceptance must say it was
skipped and must not claim VM readiness or VM end-to-end verification.

Final acceptance criteria:

- A new operator can follow the docs without repo history.
- Gerrit, Jenkins controller, and Jenkins agent have manual and helper flows.
- LDAP-backed identity assumptions are documented and simulated.
- Jenkins can schedule a job on the agent.
- Jenkins posts `Verified +1` back to Gerrit through the Gerrit REST review
  API.
- Validation artifacts are produced and retained for review.
- The package does not claim strict air-gapped support in v1.
- The package does not support offline Ubuntu dependency bundles in v1.
- Step 12 shared library extraction preserves Docker behavior.
- Step 13 VM simulation either passes in an approved VM environment or is
  explicitly documented as out of scope without claiming VM readiness.
