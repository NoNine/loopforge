# Gerrit Setup Manual

This manual is the authority for the Gerrit role. The helper
`scripts/gerrit-setup.sh` is a repeatable accelerator for reviewed env files;
it does not replace operator review.

Maintain this manual with `docs/gerrit-native-operations-reference.md`. The
native reference is the strong reference for direct OS and Gerrit operations
and must remain free of repository helper commands.

The v1 boundary is unchanged: application artifacts are prepared in the bundle
factory, staged to the Gerrit target, and verified by manifest and checksum
before target mutation. v1 does not support offline Ubuntu dependency bundle
workflows. Any public internet fallback for target-host Ubuntu/OS dependency
installation is simulation-only and must be labeled that way in logs and
evidence.

Gerrit application artifact bundles are key-free. They may contain reviewed
templates, manifests, checksums, WAR files, and plugin jars, but they must not
contain SSH private keys, public keys, `authorized_keys`, or generated
public-key handoff files. Jenkins-to-Gerrit keypair generation and public-key
handoff are later integration-step work.

Default baseline:

| Item | Default |
| --- | --- |
| Ubuntu target | 24.04.4 LTS, release `24.04`, codename `noble` |
| Java | OpenJDK 21 |
| Gerrit | 3.13.6 |

Gerrit 3.14.0 is not the default. Use it only after a reviewed baseline update
across the package.

## Phase 1: Operator Inputs

Consumed inputs:

- `examples/gerrit.env.example` copied to a reviewed local env file.
- Gerrit host, HTTP port, SSH port, runtime account, and site path.
- LDAP URL, read-only bind DN, user base, group base, and admin group.
- Gerrit admin account or group.
- LDAP bind password file or reviewed LDAP bind password value.
- Artifact output and staged artifact paths.
- Verification mode and evidence directory.
- `GERRIT_PLUGIN_LIST` with comma-separated plugin identifiers using only
  letters, digits, underscore, dot, and dash. This is operator-owned plugin
  intent; unknown plugin names fail closed until a reviewed source catalog
  entry exists in the helper.
- Optional bundle-factory artifact source inputs: `GERRIT_WAR_SOURCE`,
  `GERRIT_PLUGIN_SOURCE_DIR`, and `GERRIT_DOWNLOAD_ARTIFACTS`. For v1,
  `GERRIT_DOWNLOAD_ARTIFACTS=1` is the preferred bundle-factory path.
  `GERRIT_PLUGIN_SOURCE_DIR` is only an optional reviewed local-jar override.
- `GERRIT_OS_DEPENDENCIES`, which defaults to the Gerrit target OS package
  expectations from the reviewed Gerrit reference: `ca-certificates`, `curl`,
  `git`, `ldap-utils`, `openssh-client`, `openjdk-21-jre-headless`, `rsync`,
  `tar`, `unzip`, and `wget`.
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
- Target host baseline: Ubuntu 24.04.4 LTS `noble`, OpenJDK 21 expectation,
  approved internal Ubuntu/OS package repositories, and reachable LDAP.
- Gerrit OS dependency expectations: CA trust store tooling, HTTP download
  client, Git client, OpenSSH client, OpenJDK 21 headless runtime, rsync, tar,
  unzip, and wget.

Produced outputs:

- Readiness result showing required commands, reviewed values, baseline values,
  endpoint values, LDAP assumptions, and artifact paths.
- OS dependency expectation checks for the package/tooling names above.
- Normal-mode disk-space, host-resolution, LDAP bind/search, and Gerrit
  runtime account/group readiness checks.
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
  without requiring operator-workstation DNS, LDAP, disk, or account state to
  match the target.

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
- Gerrit plugin list.
- Internal approved Gerrit plugin source catalog entries for every selected
  plugin. The default v1 catalog covers `events-log`,
  `metrics-reporter-prometheus`, and `healthcheck`, with jar filename, mutable
  upstream source URL, expected SHA256, and Gerrit API line `3.13`.
- Gerrit templates under `templates/gerrit/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Real Gerrit WAR artifact, normally `gerrit-3.13.6.war`.
- Selected Gerrit plugin jar artifacts matching the Gerrit 3.13 line.
- `plugin-artifacts.manifest`, `plugin-metadata.report`, and
  `plugin-checksums.sha256` proving the selected plugin set, plugin metadata,
  and checksums.
- Gerrit config and secure config templates for this role.
- No `Verified` label or Jenkins integration access templates. Those are
  cross-role integration artifacts and are not staged by the Gerrit role
  helper.
- No Jenkins-to-Gerrit public key handoff. Jenkins key generation and Gerrit
  public-key installation are deferred to the later integration step.
- The reviewed Gerrit ACL workflow later uses the shared integration
  implementation with an explicit target project and REST-created reviewable
  config change. This role helper still does not perform that cross-role
  mutation.
- `manifest.txt` records `artifact_source=curated-bundle-factory`,
  `os_dependency_source=approved-internal-os-repos`,
  `public_internet_fallback=simulation-only`, and `bundle_contains_keys=no`.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `GERRIT_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/gerrit` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/<run-id>/bundle-factory/artifacts/gerrit/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- Does not install, configure, or start Gerrit.
- Does not write SSH private keys, public keys, `authorized_keys`, or
  generated key handoff files into the artifact bundle. Artifact preparation
  fails if key material is detected.
- Does not prepare Ubuntu dependency bundles. Target hosts use approved
  internal Ubuntu/OS repositories for OS dependencies.
- Public artifact downloads are allowed only in the bundle factory or staging
  context. In Docker simulation, helper output labels that public internet use
  as `simulation-only`.
- If the real Gerrit WAR or selected plugin jars are unavailable or invalid,
  `prepare-artifacts` exits nonzero with a blocked reason instead of writing
  placeholder files.
- Mutable upstream plugin URLs are allowed only when the helper verifies the
  expected SHA256, `Gerrit-PluginName`, and `Gerrit-ApiVersion` metadata from
  the reviewed source catalog. The prepared plugin jar set must exactly match
  `GERRIT_PLUGIN_LIST`; missing expected jars and unexpected extra jars are
  rejected.
- To add a Gerrit plugin in v1, update `GERRIT_PLUGIN_LIST`, add a reviewed
  helper source catalog entry with jar name, URL, SHA256, and Gerrit API line,
  then run the normal `prepare-artifacts` phase. There is no separate
  propose-plugin-versions command or runtime plugin install command.
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
- Staged artifact directory, normally `/harness/staged` in the Docker role
  gate.
- `manifest.txt`, `checksums.sha256`, `plugin-artifacts.manifest`,
  `plugin-metadata.report`, and `plugin-checksums.sha256`.

Produced outputs:

- Gerrit site tree under `GERRIT_SITE_PATH`.
- `bin/gerrit.war`.
- `plugins/*.jar`.
- `etc/artifact-manifest.txt`.
- `etc/artifact-checksums.sha256`.
- `etc/plugin-artifacts.manifest`.
- `etc/plugin-metadata.report`.
- `etc/plugin-checksums.sha256`.
- Install readiness marker under `state/install.status`.

Mutation side effects:

- Creates or updates Gerrit role-local site files.
- Does not download application artifacts on the target.
- Fails before mutation if the staged Gerrit WAR is not a valid archive.
- Fails before mutation if staged plugin metadata/checksums are missing or the
  staged plugin jar set does not exactly match `GERRIT_PLUGIN_LIST`.

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
  WAR, rendered config, plugin set, and reviewed HTTP/SSH ports.

Mutation side effects:

- Creates or updates Gerrit role-local config files.
- Records non-secret LDAP metadata and writes `secure.config` from reviewed
  secret input without committing the secret to evidence.
- Does not start a local responder or any synthetic substitute for Gerrit.
  Real daemon startup is part of validation.

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
- LDAP bind password file or reviewed LDAP bind password value.
- User and group bases.
- Gerrit admin group.
- Test-user account assumptions from `docs/account-model.md`.

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
use `docs/integration-setup-manual.md` for the shared helper workflow. That
manual is the command authority for `configure-gerrit-ssh`,
`configure-agent-ssh`, `configure-trigger`, `validate-integration`,
`verify-trigger`, and `collect-evidence`.

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
  plugin metadata report, plugin checksums, and plugin-set digest to the
  staged manifest and checksum inputs.
- LDAP access: the Gerrit target binds and searches the reviewed LDAP user and
  group bases using reviewed bind secret input that is also written to
  `etc/secure.config`.
- SSH access: a TCP connection to the reviewed SSH port returns a Gerrit SSH
  response from the running Gerrit service.
- Plugin readiness: the installed plugin jar set exactly matches the staged
  set and the expected plugins are loaded by the running Gerrit daemon.
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
simulation/docker/simulate.sh run-role-gate --role gerrit
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
  `simulation/evidence/docker/<run-id>/`.

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

`collect-evidence` is fail-closed. It verifies staged artifacts, plugin
metadata, checksums, the real Gerrit daemon process, HTTP endpoint, SSH
banner, LDAP bind/search access, exact plugin files, and runtime plugin loads
before it writes passing evidence. Passing evidence references concrete
bounded log files that exist and records that Jenkins integration
prerequisites are deferred. Because it can start Gerrit and writes new
evidence files, it is a mutating helper command and requires `--yes` after
reviewed env confirmation.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Gerrit, Docker, package-manager,
SSH, or verification logs must be referenced as bounded log files rather than
streamed.
