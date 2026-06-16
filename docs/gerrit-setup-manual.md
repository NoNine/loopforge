# Gerrit Setup Manual

This manual is the authority for the Gerrit role. The helper
`scripts/gerrit-setup.sh` is a repeatable accelerator for reviewed env files;
it does not replace operator review.

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
- Jenkins Gerrit integration account and group.
- Jenkins-to-Gerrit public key file. Gerrit consumes only the public key.
- Artifact output and staged artifact paths.
- Verification mode and evidence directory.
- `GERRIT_PLUGIN_LIST` with comma-separated plugin identifiers using only
  letters, digits, underscore, dot, and dash.
- `GERRIT_OS_DEPENDENCIES`, which defaults to the Gerrit target OS package
  expectations from the reviewed Gerrit reference: `ca-certificates`, `curl`,
  `git`, `openssh-client`, `openjdk-21-jre-headless`, `rsync`, `tar`,
  `unzip`, and `wget`.

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

Side effects:

- None. Preflight is non-mutating.
- The helper does not provide offline Ubuntu dependency bundle commands. Target
  hosts may use approved internal Ubuntu/OS package repositories. Public
  internet fallback for target-host Ubuntu/OS dependency installation is
  simulation-only.

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
- Curated Gerrit WAR marker for the Docker harness role gate.
- Curated Gerrit plugin markers.
- Gerrit config, secure config, `Verified` label, and integration access
  templates.
- Jenkins-to-Gerrit public key handoff file for the Docker harness role gate.
  The handoff file must be a syntactically valid SSH public key accepted by
  `ssh-keygen -l -f`.

Staged artifact paths:

| Location | Path |
| --- | --- |
| Bundle factory output | `GERRIT_ARTIFACT_OUTPUT_DIR` |
| Docker harness bundle output | `/harness/state/artifacts/gerrit` inside the bundle factory |
| Docker harness host state | `simulation/state/docker/harness/<run-id>/bundle-factory/artifacts/gerrit/` |

Side effects:

- Writes artifact files only in the bundle factory output path.
- Does not install, configure, or start Gerrit.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> prepare-artifacts
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
- `etc/secure.config` with redacted placeholder secret metadata only.
- A Docker-harness simulation target-local observable service tied to the
  installed WAR, rendered config, plugin set, and reviewed HTTP/SSH ports.

Mutation side effects:

- Creates or updates Gerrit role-local config files.
- Records non-secret LDAP metadata. Operators must provide real bind secrets
  through reviewed secret handling outside evidence.

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
- User and group bases.
- Gerrit admin group.
- Test-user account assumptions from `docs/account-model.md`.

Produced outputs:

- LDAP configuration in Gerrit config.
- LDAP readiness evidence from a target-local TCP connection to the reviewed
  LDAP endpoint.

Validation evidence:

- LDAP config exists.
- The Gerrit target container can open a TCP connection to the LDAP endpoint.
- Evidence records LDAP endpoint and input fingerprint, not bind secrets.

## Phase 7: Jenkins Integration Prerequisites

Gerrit must be ready for Jenkins before the Jenkins controller configures
Gerrit Trigger.

Consumed inputs:

- Jenkins Gerrit integration account.
- Jenkins Gerrit integration group.
- Jenkins-to-Gerrit public key file.
- `Verified` label template.
- Gerrit integration access template.
- Verification ref pattern.

Produced outputs:

- Gerrit-held Jenkins public key.
- `etc/verified-label.config`.
- `etc/jenkins-integration-access.config`.
- Integration readiness marker with account, group, `stream-events`, and
  `Verified -1..+1` readiness.

Mutation side effects:

- Registers or updates the Gerrit-side public key handoff.
- Renders access and label configuration for reviewed Gerrit application.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> --yes configure-integration
```

Gerrit receives only the public key. Jenkins owns the matching private key.
The helper rejects private-key or PEM material before copying and then requires
`ssh-keygen -l -f` to fingerprint the OpenSSH public key.

## Phase 8: Validation

Validation must prove observable Gerrit behavior in the target environment.
For Step 7 Docker-harness role gates, this is a simulation-only target-local
observable service tied to the installed Gerrit artifact, rendered config,
plugin set, and reviewed endpoints. It is not production-like Gerrit daemon
readiness. Production-like modes must not pass through this Step 7 service.
Validation must not report operation-plan-only, planned-checks-only, modeled,
or dummy success.

Consumed inputs:

- Reviewed Gerrit env file.
- Staged artifact manifest and checksums.
- Gerrit site files and rendered config.

Validation evidence covers:

- Startup readiness: installed WAR exists and the Docker-harness target-local
  observable service process is running in Docker harness simulation mode.
- Endpoint reachability: a TCP HTTP request to the reviewed Gerrit endpoint
  returns Gerrit 3.13.6 readiness derived from the installed artifact.
- Artifact freshness: the Docker-harness target-local service reports the WAR
  hash, Gerrit config hash, and a deterministic plugin-set digest based on
  sorted plugin filenames and file hashes. Validation compares those values to
  the currently installed files.
- LDAP access: the Gerrit target container opens a TCP connection to the
  reviewed LDAP endpoint.
- SSH access: a TCP connection to the reviewed SSH port returns a Gerrit SSH
  banner.
- Plugin readiness: at least one staged Gerrit plugin is installed.
- Integration account readiness: public key, `Verified` label, access config,
  `stream-events`, and vote readiness marker exist.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> validate
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
- Public key file for fingerprinting.
- Bounded log directory.

Produced outputs:

- Role-local Gerrit evidence JSON under `GERRIT_EVIDENCE_DIR`.
- A helper bounded log file under `GERRIT_LOG_DIR`.
- The observable service bounded log under `GERRIT_SITE_PATH/logs/`.
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
the target-local service process, HTTP endpoint, SSH banner, LDAP TCP access,
plugin files, integration permissions, and the SSH public-key fingerprint
before it writes passing evidence. Passing evidence references concrete
bounded log files that exist.

Helper:

```bash
scripts/gerrit-setup.sh --env <reviewed-gerrit.env> collect-evidence
```

Evidence must not expose private keys, passwords, tokens, LDAP bind secrets,
or full secret-bearing env values. Verbose Gerrit, Docker, package-manager,
SSH, or verification logs must be referenced as bounded log files rather than
streamed.
