## Step 8: Create The Jenkins Controller Manual And Helper

Use the Jenkins controller helper and integration behavior summarized in
`docs/references/reference-digest.md`.

Create:

- `docs/operations/setup/jenkins-controller.md`
- `docs/operations/native/jenkins-controller.md`
- `scripts/jenkins-controller-setup.sh`
- `examples/jenkins-controller.env.example`
- Jenkins controller templates under `templates/jenkins-controller/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Jenkins controller artifact and plugin preparation.
4. Jenkins installation.
5. Jenkins runtime configuration.
6. LDAP/JCasC configuration.
7. Deferred Gerrit Trigger base configuration.
8. Deferred Jenkins-to-Gerrit SSH key generation.
9. Deferred build-agent SSH key generation.
10. Deferred build-agent registration and scheduling validation.
11. Deferred end-to-end Gerrit Trigger verification.
12. Validation.
13. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure-service
install-plugins
configure-jcasc
validate
collect-evidence
```

Implementation notes:

- Preserve the reference repo's useful Jenkins plugin and JCasC patterns.
- `docs/operations/native/jenkins-controller.md` is the strong
  reference for direct OS and Jenkins controller operations. Keep it
  consistent with the controller manual and helper behavior, but never add
  repository helper commands to it.
- Treat plugin versions and checksums as curated artifacts.
- Jenkins controller defaults to `docs/baselines/version-baseline.md`.
- `prepare-artifacts` must run in the shared Docker harness bundle factory
  environment, and Jenkins controller target commands must consume only staged
  bundle factory output.
- Jenkins controller artifact bundles must be key-free. `prepare-artifacts`
  must not write Jenkins-to-Gerrit or Jenkins-to-agent private keys, public
  keys, `authorized_keys`, or generated key handoff files, and staged artifact
  verification must reject them before target mutation. Jenkins credentials,
  Gerrit Trigger server, agent-node, disposable verification job, and
  trigger-verification env templates are cross-role integration artifacts and
  must not be staged by the controller role helper.
- Jenkins controller manifests must record compact artifact identity and
  inventory fields only; policy and source-boundary facts belong in docs, logs,
  and evidence.
- Target-side manifests and checksums must be verified in the Jenkins
  controller target before install, plugin installation, or JCasC
  configuration mutates Jenkins state. Credential setup, node setup, and
  verification jobs belong to the shared integration helper after role-local
  readiness.
- Keep Jenkins admin and Jenkins Gerrit integration identities separate.
- In Step 8, the Jenkins controller helper proves controller-only bringup:
  real Jenkins startup, endpoint reachability, staged plugin installation,
  JCasC/LDAP configuration, runtime configuration, artifact freshness, bounded
  logs, and role-local evidence.
- Jenkins-to-Gerrit private key generation, Jenkins-to-agent private key
  generation, Jenkins build-agent registration, scheduling validation, Gerrit
  Trigger configuration, and end-to-end Gerrit Trigger verification are shared
  integration-helper outputs and must not be accepted as Step 8 outputs.
- Gerrit Trigger configuration and shared `prove-integration` behavior must
  follow the Step 5 trigger integration contract when that later integration
  step is run.
- `install`, `configure-service`, `install-plugins`, `configure-jcasc`, and
  `validate` must be functional against the Jenkins controller target in the
  shared Docker harness. Cross-role integration commands must not be exposed by
  the Jenkins controller helper and must not create keypairs, Gerrit Trigger
  config, Jenkins nodes, scheduling records, or trigger/vote evidence during
  Step 8.
- Controller validation must pass real Jenkins runtime checks for the lifecycle
  phase it claims. It must not report local responder output,
  operation-plan-only output, modeled output, or `planned-checks-only` output
  as success.
- `collect-evidence` must emit role-local Jenkins controller checkpoint evidence
  using the Evidence Contract defined above.
- Do not run builds on the controller except for explicit simulation-only
  checks; target-deployment validation should use the Jenkins agent.

Verification:

```bash
bash -n scripts/jenkins-controller-setup.sh
scripts/jenkins-controller-setup.sh --help
scripts/jenkins-controller-setup.sh print-env-template
scripts/jenkins-controller-setup.sh --env examples/jenkins-controller.env.example --dry-run preflight
simulation/docker/simulate.sh prepare-artifacts --role jenkins-controller
simulation/docker/simulate.sh stage-artifacts --role jenkins-controller
simulation/docker/simulate.sh configure-role --role jenkins-controller
simulation/docker/simulate.sh validate-role --role jenkins-controller
find generated/simulation/docker/<run-id>/target/evidence/jenkins-controller -type f -name '*jenkins-controller*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/jenkins-controller -type f -name '*jenkins-controller*')
rg -n "bundle_name=jenkins-artifacts-bundle|war=jenkins-2.555.3.war" generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-controller/manifest.txt generated/simulation/docker/<run-id>/target/artifacts/staging/jenkins-controller/manifest.txt
! find generated/simulation/docker/<run-id>/target/artifacts/exported/jenkins-controller generated/simulation/docker/<run-id>/target/artifacts/staging/jenkins-controller -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "JCasC|LDAP|Gerrit Trigger|prepare-artifacts|collect-evidence" docs/operations/setup/jenkins-controller.md scripts/jenkins-controller-setup.sh
! scripts/jenkins-controller-setup.sh --help | rg -n "generate-integration-key|generate-agent-key|configure-integration|configure-agent|validate-agent|prove-integration"
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/operations/setup/jenkins-controller.md scripts/jenkins-controller-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes" docs/operations/native/jenkins-controller.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, deferred integration credential
  boundaries, and secret-redaction expectations.
- Jenkins controller artifact bundles contain no SSH key material, public-key
  handoff files, or `authorized_keys`; Jenkins-to-Gerrit and Jenkins-to-agent
  keypair generation and public-key handoff remain later integration-step work.
- Jenkins controller validation covers startup, endpoint reachability, LDAP,
  plugins, JCasC, controller runtime configuration, artifact freshness, bounded
  logs, and role-local evidence.
- Gerrit SSH connectivity, Gerrit Trigger readiness, build-agent
  registration, agent scheduling, and Gerrit Trigger voting are deferred to
  the later integration step.
- Jenkins controller service commands pass the shared Docker harness role gate
  without dummy, placeholder, operation-plan-only, or modeled success.
- Jenkins controller role-local evidence follows the Evidence Contract and
  includes bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Jenkins controller native operations remain helper-free and consistent with
  the role manual's OS, Jenkins, plugin, JCasC, validation, backup, and
  recovery operations.

