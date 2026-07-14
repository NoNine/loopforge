## Step 7: Create The Gerrit Manual And Helper

Use the Gerrit helper and integration behavior summarized in
`docs/references/reference-digest.md`.

Create:

- `docs/operations/setup/gerrit.md`
- `docs/operations/native/gerrit.md`
- `scripts/gerrit-setup.sh`
- `examples/gerrit.env.example`
- Gerrit templates under `templates/gerrit/`

Manual phases:

1. Operator inputs.
2. Prerequisite readiness.
3. Curated Gerrit artifact preparation.
4. Gerrit installation.
5. Gerrit configuration.
6. LDAP authentication assumptions.
7. Deferred Jenkins integration prerequisites.
8. Validation.
9. Evidence collection.

Helper command surface:

```text
print-env-template
preflight
prepare-artifacts
install
configure
validate
collect-evidence
```

Implementation notes:

- `prepare-artifacts` prepares version-pinned Gerrit artifacts, plugins,
  manifests, and checksums, and the readiness gate must run it in the shared
  Docker harness bundle factory environment.
- Gerrit artifact bundles must be key-free. `prepare-artifacts` must not write
  Jenkins-to-Gerrit public keys, private keys, `authorized_keys`, or generated
  key handoff files, and staged artifact verification must reject them before
  target mutation. `Verified` label and Jenkins integration access templates
  are cross-role integration artifacts and must not be staged by the Gerrit
  role helper.
- Gerrit manifests must record compact artifact identity and inventory fields
  only; policy and source-boundary facts belong in docs, logs, and evidence.
- Gerrit defaults to `docs/baselines/version-baseline.md`. Non-default Gerrit versions
  may be used only after a reviewed baseline update.
- Gerrit target commands consume only staged artifacts from the bundle factory
  output and must verify target-side manifests and checksums before install or
  configuration.
- `install`, `configure`, and `validate` must be functional against the Gerrit
  target container in the shared Docker harness. Gerrit cross-role integration
  must not be exposed as a role-helper command.
- `validate` must pass real Gerrit runtime checks in the target container,
  including daemon startup and protocol checks, not local responder output,
  operation-plan-only output, or `planned-checks-only` output.
- `collect-evidence` must emit role-local Gerrit checkpoint evidence using the
  Evidence Contract defined above.
- The helper must not expose `prepare-offline-deps-bundle`,
  `install-offline-deps`, or other supported offline Ubuntu dependency bundle
  commands.
- The manual remains the authority; helper commands are repeatable
  accelerators for reviewed env files.
- `docs/operations/native/gerrit.md` is the strong reference for
  direct OS and Gerrit operations. Keep it consistent with the Gerrit manual
  and helper behavior, but never add repository helper commands to it.
- Mutating helper commands should require explicit confirmation unless a
  reviewed `--yes` flag is provided.

Verification:

```bash
bash -n scripts/gerrit-setup.sh
scripts/gerrit-setup.sh --help
scripts/gerrit-setup.sh print-env-template
scripts/gerrit-setup.sh --env examples/gerrit.env.example --dry-run preflight
simulation/docker/simulate.sh prepare-artifacts --role gerrit
simulation/docker/simulate.sh stage-artifacts --role gerrit
simulation/docker/simulate.sh configure-role --role gerrit
simulation/docker/simulate.sh validate-role --role gerrit
find generated/simulation/docker/<run-id>/target/evidence/gerrit -type f -name '*gerrit*' -print -quit | rg .
! rg -n "dummy|operation-plan-only|planned-checks-only|modeled" $(find generated/simulation/docker/<run-id>/target/evidence/gerrit -type f -name '*gerrit*')
rg -n "bundle_name=gerrit-artifacts-bundle|war=gerrit-3.13.6.war" generated/simulation/docker/<run-id>/target/artifacts/exported/gerrit/manifest.txt generated/simulation/docker/<run-id>/target/artifacts/staging/gerrit/manifest.txt
! find generated/simulation/docker/<run-id>/target/artifacts/exported/gerrit generated/simulation/docker/<run-id>/target/artifacts/staging/gerrit -type f \( -name '*.pub' -o -name 'authorized_keys' -o -name '*_ed25519' -o -name '*_rsa' -o -name 'id_ed25519' -o -name 'id_rsa' \) -print | rg .
rg -n "prepare-artifacts|collect-evidence" docs/operations/setup/gerrit.md scripts/gerrit-setup.sh
! scripts/gerrit-setup.sh --help | rg -n "configure-integration|prove-integration|configure-agent"
rg -n "offline-deps|offline Ubuntu dependency|strict air-gapped" docs/operations/setup/gerrit.md scripts/gerrit-setup.sh
! rg -n "helper|scripts/|print-env-template|prepare-artifacts|install-offline|--env|--yes" docs/operations/native/gerrit.md
```

Acceptance criteria:

- Every helper command has a matching manual phase.
- The manual lists consumed inputs, produced outputs, staged artifact paths,
  mutation side effects, validation evidence, and secret-redaction
  expectations.
- Gerrit artifact checksums and manifests are produced by the helper in the
  bundle factory environment and verified after staging to the Gerrit target.
- Gerrit artifact bundles contain no SSH key material, public-key handoff
  files, or `authorized_keys`; keypair generation and Gerrit public-key
  installation remain later integration-step work.
- Gerrit validation covers startup, endpoint reachability, LDAP access, SSH
  access, and plugin readiness. Jenkins integration account readiness,
  `Verified` grants, stream-events grants, and Gerrit-owned
  `All-Projects.git`/`All-Users.git` integration state are deferred to the
  later integration step.
- Gerrit service commands pass the shared Docker harness role gate without
  dummy, placeholder, operation-plan-only, or modeled success.
- Gerrit role-local evidence follows the Evidence Contract and includes
  bounded log references without exposing secrets.
- Unsupported offline dependency bundle commands are absent from helper command
  dispatch and documented only as unsupported v1 behavior if mentioned.
- Gerrit native operations remain helper-free and consistent with the role
  manual's OS, Gerrit, validation, backup, and recovery operations.

