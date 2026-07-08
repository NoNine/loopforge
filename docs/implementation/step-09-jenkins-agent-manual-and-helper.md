## Step 9: Create The Jenkins Agent Manual And Helper

Use the Jenkins agent helper behavior summarized in `docs/references/reference-digest.md`.

Create:

- `docs/jenkins-agent-setup-manual.md`
- `docs/jenkins-agent-native-operations-reference.md`
- `scripts/jenkins-agent-setup.sh`
- `examples/jenkins-agent.env.example`
- Jenkins agent templates under `templates/jenkins-agent/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated agent artifact preparation.
4. Agent host installation.
5. Agent runtime account and SSH setup.
6. Agent host validation.
7. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-runtime
validate
collect-evidence
```

Implementation notes:

- Jenkins connects out to the agent over SSH.
- `docs/jenkins-agent-native-operations-reference.md` is the strong reference
  for direct OS, OpenSSH, and Jenkins agent operations. Keep it consistent with
  the agent manual and helper behavior, but never add repository helper
  commands to it.
- The agent must have a dedicated runtime user and remote filesystem path.
- Jenkins agent defaults to `docs/version-baseline.md`.
- `prepare-artifacts` must run in the shared Docker harness bundle factory
  environment, and Jenkins agent target commands must consume only staged
  bundle factory output.
- Jenkins agent artifact bundles must be key-free. `prepare-artifacts` must
  not write Jenkins-to-agent public keys, private keys, `authorized_keys`, or
  generated key handoff files, and staged artifact verification must reject
  them before target mutation.
- Jenkins agent manifests must record compact artifact identity and inventory
  fields only; policy and source-boundary facts belong in docs, logs, and
  evidence.
- Target-side manifests and checksums must be verified in the Jenkins agent
  target before install or runtime configuration mutates the agent host.
- The agent helper configures only the agent host runtime and SSH service
  side; it must not write `authorized_keys`, register a Jenkins node, prove
  scheduling, configure Gerrit Trigger, or prove `Verified` voting.
- Jenkins controller node registration belongs to the shared integration
  helper after Jenkins controller and Jenkins agent role-only bringup are
  accepted.
- Step 9 is agent host-only bringup. Jenkins-to-agent key generation, public
  key transfer, runtime-account key installation, controller node
  registration, controller credential selection, node-name/label/executor
  policy, scheduling, validation jobs, and Gerrit Trigger execution are later
  integration-step outputs, not Step 9 acceptance outputs.
- The controller's built-in node should remain at zero executors in
  target-deployment docs.
- Agent validation must prove OS/tooling readiness, SSH daemon reachability,
  runtime account ownership, remote filesystem readiness, staged artifact
  checks, bounded logs, and role-local evidence. Jenkins node name and labels
  are handoff metadata only in the agent role. Jenkins controller key handoff,
  node registration, and controller-side scheduling proof are deferred to the
  later integration step.
- `install`, `configure-runtime`, and `validate` must be functional against the
  Jenkins agent target in the shared Docker harness.
- Agent validation must pass real SSH daemon and filesystem readiness checks,
  not operation-plan-only or `planned-checks-only` output.
- `collect-evidence` must emit role-local Jenkins agent checkpoint evidence
  using the Evidence Contract defined above.

Verification:

```bash
bash -n scripts/jenkins-agent-setup.sh
scripts/jenkins-agent-setup.sh --help
scripts/jenkins-agent-setup.sh print-env-template
scripts/jenkins-agent-setup.sh --env examples/jenkins-agent.env.example --dry-run preflight
simulation/docker/simulate.sh prepare-artifacts --role jenkins-agent
simulation/docker/simulate.sh stage-artifacts --role jenkins-agent
simulation/docker/simulate.sh configure-role --role jenkins-agent
simulation/docker/simulate.sh validate-role --role jenkins-agent
find generated/simulation/docker/<run-id>/target/evidence/jenkins-agent -type f -name '*jenkins-agent*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/jenkins-agent -type f -name '*jenkins-agent*')
rg -n "agent|SSH|label|executor|collect-evidence" docs/jenkins-agent-setup-manual.md scripts/jenkins-agent-setup.sh
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/jenkins-agent-setup-manual.md scripts/jenkins-agent-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes|configure-" docs/jenkins-agent-native-operations-reference.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, host-only readiness checks, and
  secret-redaction expectations.
- Jenkins agent artifact bundles contain no SSH key material, public-key
  handoff files, or `authorized_keys`; Jenkins-to-agent keypair generation and
  public-key handoff remain later integration-step work.
- Agent validation covers OS/tooling readiness, SSH daemon reachability, remote
  filesystem readiness, runtime account ownership, staged artifact checks,
  bounded logs, and role-local evidence.
- Agent service commands pass the shared Docker harness role gate without
  dummy, placeholder, operation-plan-only, or modeled success.
- Jenkins agent role-local evidence follows the Evidence Contract and includes
  bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Jenkins agent native operations remain helper-free and consistent with the
  role manual's OS, OpenSSH, host-only validation, backup, and recovery
  operations.

