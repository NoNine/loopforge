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
  letters, digits, underscore, dot, and dash.
- Optional bundle-factory artifact source inputs: `GERRIT_WAR_SOURCE`,
  `GERRIT_PLUGIN_SOURCE_DIR`, and `GERRIT_DOWNLOAD_ARTIFACTS`.
- `GERRIT_OS_DEPENDENCIES`, which defaults to the Gerrit target OS package
  expectations from the reviewed Gerrit reference: `ca-certificates`, `curl`,
  `git`, `ldap-utils`, `openssh-client`, `openjdk-21-jre-headless`, `rsync`,
  `tar`, `unzip`, and `wget`.

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
- Gerrit templates under `templates/gerrit/`.

Produced outputs:

- `manifest.txt`.
- `checksums.sha256`.
- Real Gerrit WAR artifact, normally `gerrit-3.13.6.war`.
- Selected Gerrit plugin jar artifacts matching the Gerrit 3.13 line.
- Plugin seed and artifact manifests proving the selected plugin set.
- Gerrit config and secure config templates for this role.
- `Verified` label and integration access templates for the later integration
  step. Step 7 stages them as reviewed artifacts but does not apply them to
  Gerrit project or account state.
- No Jenkins-to-Gerrit public key handoff. Jenkins key generation and Gerrit
  public-key installation are deferred to the later integration step.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `GERRIT_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/gerrit` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/harness/<run-id>/bundle-factory/artifacts/gerrit/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- Does not install, configure, or start Gerrit.
- Does not prepare Ubuntu dependency bundles. Target hosts use approved
  internal Ubuntu/OS repositories for OS dependencies.
- Public artifact downloads are allowed only in the bundle factory or staging
  context. In Docker simulation, helper output labels that public internet use
  as `simulation-only`.
- If the real Gerrit WAR or selected plugin jars are unavailable or invalid,
  `prepare-artifacts` exits nonzero with a blocked reason instead of writing
  placeholder files.
- Because it writes new bundle-factory artifacts, `prepare-artifacts` is a
  mutating helper command and requires `--yes` after reviewed env
  confirmation.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes prepare-artifacts
```

Harness:

```bash
simulation/docker/docker-harness.sh prepare-artifacts --role gerrit
```

## Phase 4: Gerrit Installation

Installation consumes only staged artifacts from the bundle factory output.
The target verifies `manifest.txt` and `checksums.sha256` before any target
mutation.

Consumed inputs:

- Reviewed Gerrit env file.
- Staged artifact directory, normally `/harness/staged` in the Docker role
  gate.
- `manifest.txt` and `checksums.sha256`.

Produced outputs:

- Gerrit site tree under `GERRIT_SITE_PATH`.
- `bin/gerrit.war`.
- `plugins/*.jar`.
- `etc/artifact-manifest.txt`.
- `etc/artifact-checksums.sha256`.
- Install readiness marker under `state/install.status`.

Mutation side effects:

- Creates or updates Gerrit role-local site files.
- Does not download application artifacts on the target.
- Fails before mutation if the staged Gerrit WAR is not a valid archive.

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

## Phase 7: Deferred Jenkins Integration Prerequisites

Jenkins integration prerequisites are intentionally deferred to the later
integration step. Step 7 remains a Gerrit-only runtime proof and must not
configure Gerrit-side Jenkins integration access or state.

Consumed inputs:

- Jenkins Gerrit integration account.
- Jenkins Gerrit integration group.
- Jenkins-to-Gerrit public key file.
- LDAP bind password file or reviewed LDAP bind password value for Gerrit
  local secret handling and LDAP bind/search proof.
- Integration configuration mode, normally `site-git` in the Docker harness or
  another reviewed Gerrit-native admin path in production.
- Gerrit integration account id when site-Git bootstrap is used.
- `Verified` label template.
- Gerrit integration access template.
- Verification ref pattern.

Deferred outputs:

- Gerrit-held Jenkins public key.
- `etc/verified-label.config`.
- `etc/jenkins-integration-access.config`.
- Real Gerrit site Git state under `All-Projects.git` and `All-Users.git` when
  `GERRIT_INTEGRATION_CONFIG_MODE=site-git`.
- Integration applied status recording the account, group, and configuration
  mode.

Mutation side effects:

- None in Step 7. The helper command is retained as an explicit blocked entry
  point so Step 7 role gates cannot mutate `All-Projects.git`, `All-Users.git`,
  Gerrit labels, Jenkins service groups, public keys, stream-events grants, or
  vote permissions.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes configure-integration
```

Expected Step 7 result: `BLOCKED: Step 7 defers Jenkins integration
prerequisites to the later integration step`. Gerrit receives only the public
key when that later step is implemented. Jenkins owns the matching private key.
LDAP bind secrets are still read from reviewed secret input and written to
`etc/secure.config` during Gerrit configuration; they are not recorded in
evidence.

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
  and plugin-set digest to the staged manifest and checksum inputs.
- LDAP access: the Gerrit target binds and searches the reviewed LDAP user and
  group bases using reviewed bind secret input that is also written to
  `etc/secure.config`.
- SSH access: a TCP connection to the reviewed SSH port returns a Gerrit SSH
  response from the running Gerrit service.
- Plugin readiness: at least one staged Gerrit plugin is installed.
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
simulation/docker/docker-harness.sh run-role-gate --role gerrit
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
  `simulation/evidence/docker/harness/<run-id>/`.
- For Step 7 compatibility, the harness also mirrors evidence to ignored
  `simulation/docker/state/evidence/`.

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

`collect-evidence` is fail-closed. It verifies staged artifacts and checksums,
the real Gerrit daemon process, HTTP endpoint, SSH banner, LDAP bind/search
access, and plugin files before it writes passing evidence. Passing evidence
references concrete bounded log files that exist and records that Jenkins
integration prerequisites are deferred. Because it can start Gerrit and writes
new evidence files, it is a mutating helper command and requires `--yes`
after reviewed env confirmation.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Gerrit, Docker, package-manager,
SSH, or verification logs must be referenced as bounded log files rather than
streamed.
