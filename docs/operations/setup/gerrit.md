# Gerrit Setup Manual

This manual owns the Gerrit reviewed-input helper workflow. The helper
`scripts/gerrit-setup.sh` is a repeatable accelerator for reviewed env files;
it does not replace operator review or the direct procedure in
`docs/operations/native/gerrit.md`.

`docs/contracts/lifecycle-contract.md` owns shared phase behavior, checkpoint semantics,
mutation boundaries, and resume/rerun rules. This manual owns only the
Gerrit-specific application of that contract.

The native reference is the procedural baseline for direct OS and Gerrit
operations. Keep this helper workflow aligned with that baseline and preserve
equivalent product state and validation outcomes. The native reference must
remain free of repository helper commands.

The v1 boundary is unchanged: application artifacts are prepared in the bundle
factory, staged to the Gerrit target, and verified by manifest and checksum
before target mutation. v1 does not support offline Ubuntu dependency bundle
workflows. Any public internet fallback for target-host Ubuntu/OS dependency
installation is simulation-only and must be labeled that way in logs and
evidence.

Gerrit application artifact bundles are key-free. They may contain reviewed
templates, manifests, checksums, and WAR files, but they must not contain SSH
private keys, public keys, `authorized_keys`, generated public-key handoff
files, or external Gerrit plugin jars. Jenkins-to-Gerrit keypair generation
and public-key handoff are later integration-step work. Use
`docs/contracts/artifact-bundle-contract.md` for the bundle workspace, archive, and
extraction-root contract.

Default baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21, and Gerrit
`3.13.6`. `docs/baselines/version-baseline.md` owns the package-wide baseline and
reviewed update rules.

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/gerrit.env.example` copied to a reviewed local env file.
- Gerrit host, HTTP port, SSH port, runtime account, and site path.
- LDAP URL, read-only bind DN, user base, group base, and admin group.
- Gerrit admin account or group.
- LDAP bind password supplied as execution-time `LDAP_BIND_PASSWORD`; do not
  store it in the reviewed env file or artifact bundle.
- Artifact output and staged artifact paths.
- Verification mode and evidence directory.
- Optional bundle-factory artifact source inputs: `GERRIT_WAR_SOURCE`,
  and `GERRIT_DOWNLOAD_ARTIFACTS`. For v1, `GERRIT_DOWNLOAD_ARTIFACTS=1`
  is simulation-only for the Gerrit WAR source.
- `GERRIT_OS_DEPENDENCIES`, whose baseline and layered package rationale are
  defined in `docs/baselines/package-requirements.md`.
- Gerrit `3.13.6`, Java `21`, and Ubuntu `24.04`/`noble` are internal helper
  constants for v1, not operator env overrides.

Produced outputs:

- Reviewed Gerrit env file.
- Sanitized input fingerprint in evidence.

Side effects:

- Local env-file review only. No Gerrit target mutation.

Helper:

```bash
scripts/gerrit-setup.sh print-env-template
```

Secret-redaction expectations:

- Do not put private keys, passwords, tokens, or LDAP bind secrets in evidence.
- Evidence may record public key fingerprints, account names, endpoints,
  manifest paths, checksum paths, and bounded log references.

## Phase 2: Prerequisite Readiness

Consumed inputs:

- Reviewed Gerrit env file.
- Target host baseline from `docs/baselines/version-baseline.md`, approved internal
  Ubuntu/OS package repositories, and reachable LDAP.
- Gerrit OS dependency expectations defined in
  `docs/baselines/package-requirements.md`.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline values,
  endpoint values, LDAP assumptions, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.
- Normal-mode disk-space, host-resolution, LDAP bind/search, and Gerrit
  runtime identity checks. Fully absent account/group/product-home state is
  accepted for creation by `install`; a fully matching identity with an empty
  product home is accepted for adoption. Other existing application state,
  partial state, or conflicting state blocks unless an exact input-bound
  completion record returns non-mutating `already-complete`.
- Jenkins Gerrit integration account, group, and public-key handoff values are
  not Step 7 prerequisites. They are reviewed and applied in the later
  integration step.

Side effects:

- None. Preflight is non-mutating.
- The helper does not provide offline Ubuntu dependency bundle commands. Target
  hosts may use approved internal Ubuntu/OS package repositories. Public
  internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only.
- Dry-run preflight validates reviewed values and reports planned checks
  without requiring operator-workstation DNS, LDAP, or disk state to match the
  target. Runtime identity state is still inspected because absent, partial,
  and matching target state produce different installation outcomes.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> preflight
```

For dry-run review:

```bash
scripts/gerrit-setup.sh --env examples/gerrit.env.example --dry-run preflight
```

## Phase 3: Curated Gerrit Artifact Preparation

Artifact preparation runs in the bundle factory environment, not on the Gerrit
target. The shared Docker harness runs this phase in the bundle factory
container for Step 7 validation.

Consumed inputs:

- Reviewed Gerrit env values.
- Version baseline: Gerrit 3.13.6, OpenJDK 21, Ubuntu release `24.04`,
  codename `noble`.
- Gerrit templates under `templates/gerrit/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Real Gerrit WAR artifact, normally `gerrit-3.13.6.war`.
- Gerrit config and secure config templates for this role.
- No external Gerrit plugin jars or plugin proof files. External Gerrit
  plugins are operator-managed manual operations outside the Loopforge bundle.
- No `Verified` label or Jenkins integration access templates. Those are
  cross-role integration artifacts and are not staged by the Gerrit role
  helper.
- No Jenkins-to-Gerrit public key handoff. Jenkins key generation and Gerrit
  public-key installation are deferred to the later integration step.
- The reviewed Gerrit ACL workflow later uses the shared integration
  implementation with an explicit target project and REST-created reviewable
  config change. This role helper still does not perform that cross-role
  mutation.
- `manifest.txt` records only compact artifact identity and inventory fields.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `GERRIT_ARTIFACT_OUTPUT_DIR` |
| Bundle-factory workspace | `/var/lib/loopforge/preparing/gerrit-artifacts-bundle/gerrit`; see `docs/contracts/artifact-bundle-contract.md` |
| Docker harness exported output | `generated/simulation/docker/<run-id>/target/artifacts/exported/gerrit-artifacts-bundle.tar.gz` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- In Docker simulation, successful preparation exports the bundle to the
  `target/artifacts/exported/gerrit-artifacts-bundle.tar.gz` handoff path.
- Does not install, configure, or start Gerrit.
- Does not write SSH private keys, public keys, `authorized_keys`, or
  generated key handoff files into the artifact bundle. Artifact preparation
  fails if key material is detected.
- Does not prepare Ubuntu dependency bundles. Target hosts use approved
  internal Ubuntu/OS repositories for OS dependencies.
- Public artifact downloads are allowed only in the bundle factory or staging
  context. In Docker simulation, helper output labels that public internet use
  as `simulation-only`.
- If the real Gerrit WAR is unavailable or invalid, `prepare-artifacts` exits
  nonzero with a blocked reason instead of writing placeholder files.
- External Gerrit plugins are not downloaded, bundled, installed, checksummed,
  or validated by the Gerrit role helper.
- Because it writes new bundle-factory artifacts, `prepare-artifacts` is a
  mutating helper command and requires `--yes` after reviewed env
  confirmation.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes prepare-artifacts
```

Harness:

```bash
simulation/docker/simulate.sh prepare-artifacts --role gerrit
```

## Phase 4: Gerrit Installation

Installation consumes only staged artifacts from the bundle factory output.
The target verifies `manifest.txt` and `checksums.sha256` before any target
mutation.

Consumed inputs:

- Reviewed Gerrit env file.
- Extracted artifact payload root, normally `/var/lib/loopforge/staging/gerrit`
  in Docker simulation and target deployment. See
  `docs/contracts/artifact-bundle-contract.md`.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Gerrit site tree under `GERRIT_SITE_PATH`.
- `bin/gerrit.war`.
- An empty `/srv/gerrit/plugins` directory for later operator-managed use.
- Install readiness marker under `state/install.status`.

Mutation side effects:

- Creates the reviewed Gerrit primary group, runtime account, and
  `/srv/gerrit` product home when all three are absent, or adopts a fully
  matching identity with an empty home. It does not repair partial,
  mismatched, or existing application state.
- Creates Gerrit role-local site files during initial setup.
- Does not download application artifacts on the target.
- Fails before mutation if the staged Gerrit WAR is not a valid archive.
- Does not install, remove, or validate external Gerrit plugin jars.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes install
```

Without `--yes`, the helper blocks mutating commands after env review.

## Phase 5: Gerrit Configuration

Consumed inputs:

- Reviewed Gerrit env file.
- Staged config templates.
- LDAP URL, bind DN, user base, group base, and Gerrit admin group.

Produced outputs:

- `etc/gerrit.config`.
- `etc/secure.config` written from reviewed LDAP bind secret input.
- Real Gerrit site runtime configuration ready to start from the staged Gerrit
  WAR, rendered config, and reviewed HTTP/SSH ports.

Mutation side effects:

- Creates Gerrit role-local config files during initial setup.
- Records non-secret LDAP metadata and writes `secure.config` from reviewed
  secret input without committing the secret to evidence.
- Establishes the real Gerrit runtime after configuration is complete. In VM
  simulation and target deployment, that means the guest systemd service;
  Docker retains its existing direct-process model.
- Does not use a local responder or any synthetic substitute for Gerrit.

Validation is observational: it checks an already-running Gerrit runtime and
must fail rather than start or repair it. The operator-interface parity rules
are defined in `docs/contracts/operator-execution-contract.md`.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes configure
```

## Phase 6: LDAP Authentication Assumptions

Gerrit uses LDAP-backed human accounts and groups for admin and test access.
The Gerrit runtime account remains a local OS account and is not a Gerrit
admin account.

Consumed inputs:

- LDAP URL.
- Read-only LDAP bind DN.
- LDAP bind password supplied as execution-time `LDAP_BIND_PASSWORD`; product
  runtime config may persist it in Gerrit `secure.config`.
- User and group bases.
- Gerrit admin group.
- Test-user account assumptions from `docs/contracts/account-model.md`.

Produced outputs:

- LDAP configuration in Gerrit config.
- LDAP readiness evidence from an LDAP bind/search against the reviewed user
  and group bases.

Validation evidence:

- LDAP config exists.
- The Gerrit target can bind and search the configured LDAP user and group
  bases with `ldapsearch`.
- Evidence records LDAP endpoint and input fingerprint, not bind secrets.
- If `ldapsearch` or reviewed LDAP bind/search credentials are unavailable,
  validation blocks. TCP reachability alone is not LDAP access proof.

## Phase 7: Shared Integration Handoff

Jenkins integration prerequisites are intentionally deferred to the shared
integration step. Step 7 remains a Gerrit-only runtime proof and must not
configure Gerrit-side Jenkins integration access or state. Cross-role SSH,
Gerrit permissions, global `Verified` label setup, trigger setup, validation,
and integration evidence belong to `scripts/integration-setup.sh`.

After Gerrit, Jenkins controller, and Jenkins agent role manuals are complete,
use `docs/operations/native/integration.md` for manual
target-deployment integration operations. Use
`docs/operations/setup/integration.md` only for the shared helper workflow.

Gerrit role-local setup must not mutate `All-Projects.git`, `All-Users.git`,
Gerrit labels, Jenkins service groups, public keys, `stream-events` grants, or
vote permissions as a role-local phase. `target-deployment` integration defaults to a
global `Verified` label in reviewed `All-Projects` configuration; Jenkins read
and `label-Verified -1..+1` grants remain scoped to the reviewed project/ref
pattern; `stream-events` remains a global capability grant; and REST review is
the default vote posting path.

## Phase 8: Validation

Validation must pass real Gerrit runtime checks in the target environment.
For Step 7 Docker-harness role gates, Gerrit must be initialized and started
from the staged Gerrit artifact in the Gerrit target container. Validation must
not report operation-plan-only, planned-checks-only, modeled, local-responder,
or dummy success.

Consumed inputs:

- Reviewed Gerrit env file.
- Staged artifact manifest and checksums.
- Gerrit site files and rendered config.

Validation evidence covers:

- Startup readiness: Gerrit is running from the installed WAR and writes real
  Gerrit startup logs under the configured site log path.
- Endpoint reachability: a request to the reviewed Gerrit HTTP endpoint reaches
  the running Gerrit service.
- Artifact freshness: validation compares the installed WAR, rendered config,
  staged manifest, and checksum inputs.
- LDAP access: the Gerrit target binds and searches the reviewed LDAP user and
  group bases using reviewed bind secret input that is also written to
  `etc/secure.config`.
- SSH access: a TCP connection to the reviewed SSH port returns a Gerrit SSH
  response from the running Gerrit service.
- Jenkins integration prerequisites: explicitly deferred. Validation must not
  require or apply Gerrit-owned `All-Projects.git`/`All-Users.git` Jenkins
  access state, `Verified` voting grants, or stream-events grants.

If Gerrit cannot be initialized or started from the staged WAR and rendered
site configuration, validation fails or reports `BLOCKED:` in the bounded log.
It must not stand up a local TCP responder, synthetic HTTP service, or marker
process to satisfy readiness.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes validate
```

Harness gate:

```bash
simulation/docker/simulate.sh configure-role --role gerrit
simulation/docker/simulate.sh validate-role --role gerrit
```

## Phase 9: Evidence Collection

Consumed inputs:

- Reviewed Gerrit env values.
- Staged artifact manifest and checksums.
- Gerrit site readiness markers.
- Bounded log directory.

Produced outputs:

- Role-local Gerrit evidence JSON under `GERRIT_EVIDENCE_DIR`.
- A helper bounded log file under `GERRIT_LOG_DIR`.
- Gerrit daemon startup and runtime logs under `GERRIT_SITE_PATH/logs/`.
- In the shared Docker harness, canonical evidence under
  `generated/simulation/docker/<run-id>/target/evidence/gerrit/`.

Evidence Contract fields:

- Verification mode.
- Timestamp.
- Role or environment name.
- Checkpoint name.
- Command name.
- Status.
- Reviewed input fingerprint.
- Artifact manifest references.
- Checksum references and verification result.
- Observed checks.
- Bounded log references.
- Redaction status.

`collect-evidence` is fail-closed. It verifies staged artifacts, checksums,
the real Gerrit daemon process, HTTP endpoint, SSH banner, and LDAP
bind/search access before it writes passing evidence. Passing evidence
references concrete bounded log files that exist and records that Jenkins
integration prerequisites are deferred. Because it can start Gerrit and writes
new evidence files, it is a mutating helper command and requires `--yes` after
reviewed env confirmation.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Gerrit, Docker, package-manager,
SSH, or verification logs must be referenced as bounded log files rather than
streamed.
