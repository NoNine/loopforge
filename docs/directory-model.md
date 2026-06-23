# Directory Model

## Purpose And Authority

This document defines Loopforge's runtime directory model. It records the
canonical directories, owning environment, lifecycle owner, expected ownership
and permission model, sensitivity, evidence behavior, and simulation backing
rules for the v1 Gerrit/Jenkins setup package.

`docs/system-model.md` remains the system authority. This document is a topic
authority for runtime directory ownership and should stay aligned with
`docs/account-model.md`, `docs/artifact-bundle-contract.md`,
`docs/validation-and-evidence.md`, and the simulation docs.

This inventory covers modeled runtime directories. It does not inventory
ordinary source-tree directories such as `docs/`, `scripts/`, `templates/`,
`examples/`, or `tests/`.

## Directory Properties

Directory entries use these properties:

| Property | Meaning |
| --- | --- |
| Path | Canonical path visible to helpers, services, or operators. |
| Environment | Logical environment where the path exists. |
| Lifecycle owner | Utility, service, or operator boundary that creates, mutates, or cleans the path. |
| OS owner/group | Expected local account and group ownership when the path is service-owned. |
| Permission model | Required access posture, expressed as a mode when the code or contract depends on it. |
| Contents | Expected data class. |
| Sensitivity | Whether the path may contain secrets or review-sensitive data. |
| Evidence and cleanup | What may be recorded and what cleanup may remove. |
| Simulation backing | Docker or VM backing path notes when simulation realizes the path differently. |

## Helper-Owned Paths

Helper-owned paths are execution state, not Gerrit or Jenkins service homes.
Role helpers and the shared integration helper may create and mutate these
paths during reviewed lifecycle commands.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/var/lib/loopforge/` | Bundle factory and targets | Role helpers and shared integration helper | Helper execution account; Docker bundle factory uses `ci-operator:ci-operator` for helper state | Private where secrets or rendered inputs are present | Rendered inputs, staging handoff, helper state, evidence inputs, integration status | Mixed; child paths can contain secrets or sensitive reviewed inputs | Evidence may reference child paths, but must not include secret values |
| `/var/lib/loopforge/rendered/` | Bundle factory and targets | Docker simulation render flow and helpers | Helper execution account | Runtime input files are private, normally `0600` for env files | Reviewed and rendered runtime inputs | Sensitive because env files may include secret-bearing variables or paths | Evidence may record file names and redaction status |
| `/var/lib/loopforge/artifact-bundle-work/<role>/` | Bundle factory | Role helper `prepare-artifacts` | Helper execution account | Writable by helper only | Prepared role artifacts, manifests, checksums before packaging | Non-secret artifact workspace; must not contain private keys, passwords, tokens, or LDAP bind secrets | Source-boundary and checksum evidence may reference this path |
| `/var/lib/loopforge/staging/<role>/incoming/` | Targets | Docker/VM/target transfer surface and role helpers | Helper execution account | Writable only by reviewed staging flow | Incoming release archive and checksum pair | Non-secret handoff; must not become an OS dependency bundle | Missing or checksum-mismatched content blocks readiness |
| `/var/lib/loopforge/evidence/` | Bundle factory and targets | Role helpers, integration helper, evidence collector | Helper execution account | Writable by helper; readable by approved evidence reviewers | JSON summaries, status records, bounded references | Must be redacted; may include public key fingerprints and paths | Retained for audit; simulation cleanup preserves generated evidence |
| `/var/log/loopforge/` | Bundle factory and targets | Helpers and simulation harness | Helper execution account | Writable by helper; bounded reads only | Helper logs and command logs | Must not include private keys, passwords, tokens, LDAP bind secrets, or full secret-bearing env values | Evidence may include bounded log references |

Public internet fallback on target hosts is not a supported product behavior.
When simulation records public fallback for Ubuntu or OS dependencies, the
path, log, and evidence labels must say `simulation-only`.

## Artifact Extraction Paths

Artifact extraction paths are target-side staging roots. Role helpers consume
the helper-visible payload directories after archive and checksum validation.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/opt/gerrit-artifacts-bundle/` | Gerrit target | Artifact staging flow | Root or delegated installer account before role consumption | Readable by role helper after checksum verification | Extracted Gerrit bundle root | Non-secret application artifacts only | Checksum verification evidence must reference the staged payload |
| `/opt/gerrit-artifacts-bundle/gerrit/` | Gerrit target | Gerrit role helper | Root or delegated installer account before copy into `/srv/gerrit` | Readable by Gerrit helper | Gerrit WAR, plugins, templates, manifests, checksums | Must not include integration keys or secrets | Gerrit install consumes this path only |
| `/opt/jenkins-artifacts-bundle/` | Jenkins controller target | Artifact staging flow | Root or delegated installer account before role consumption | Readable by role helper after checksum verification | Extracted Jenkins bundle root | Non-secret application artifacts only | Checksum verification evidence must reference the staged payload |
| `/opt/jenkins-artifacts-bundle/jenkins/` | Jenkins controller target | Jenkins controller role helper | Root or delegated installer account before copy into Jenkins home | Readable by Jenkins helper | Jenkins WAR, plugin manager, plugins, templates, manifests, checksums | Must not include Jenkins credentials or keys | Jenkins install consumes this path only |
| `/opt/jenkins-agent-artifacts-bundle/` | Jenkins agent target | Artifact staging flow | Root or delegated installer account before role consumption | Readable by role helper after checksum verification | Extracted Jenkins agent bundle root | Non-secret bootstrap artifacts only | Checksum verification evidence must reference the staged payload |
| `/opt/jenkins-agent-artifacts-bundle/jenkins-agent/` | Jenkins agent target | Jenkins agent role helper | Root or delegated installer account before copy into agent state | Readable by agent helper | Agent bootstrap files, templates, manifests, checksums | Must not include authorized keys or private keys | Agent install consumes this path only |

## Product Homes

Product homes are service-owned runtime directories. They are separate from
helper-owned `/var/lib/loopforge/` state.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/srv/gerrit` | Gerrit target | Gerrit service and Gerrit role helper | `gerrit:gerrit` by default | Service-owned; helper verifies runtime account home and ownership | Gerrit site, repositories, config, plugins, indexes, logs, runtime markers | Sensitive because config can include LDAP/service authentication material | Backups and evidence may reference subpaths; secrets must be protected |
| `/srv/gerrit/etc` | Gerrit target | Gerrit role helper and Gerrit service | `gerrit:gerrit` | Protected configuration directory | `gerrit.config`, `secure.config`, manifests, plugin metadata | Secret-bearing when `secure.config` exists | Evidence may record config status, not secret values |
| `/srv/gerrit/etc/secure.config` | Gerrit target | Gerrit role helper and Gerrit service | `gerrit:gerrit` | `0600` | Gerrit secure configuration such as LDAP bind password material | Secret | Never include file contents in evidence or logs |
| `/srv/gerrit/plugins` | Gerrit target | Gerrit role helper and Gerrit service | `gerrit:gerrit` | Service-readable | Gerrit plugin JARs | Non-secret artifacts | Plugin checksum and digest evidence may reference this path |
| `/srv/gerrit/logs` | Gerrit target | Gerrit service | `gerrit:gerrit` | Service-writable | Gerrit runtime logs and helper startup logs | Review-sensitive; must be bounded when inspected | Evidence records bounded references only |
| `/srv/gerrit/run` and `/srv/gerrit/state` | Gerrit target | Gerrit helper and service | `gerrit:gerrit` | Service-writable | Runtime pid/status markers and helper state | Low to sensitive depending on content | Evidence may reference marker paths |
| `/var/lib/jenkins` | Jenkins controller target | Jenkins service, Jenkins controller role helper, integration helper | `jenkins:jenkins` by default | Service-owned; helper verifies runtime account home and ownership | Jenkins home, jobs, plugins, credentials, secrets, JCasC, logs | Secret-bearing | Backups and evidence may reference subpaths; secrets must be protected |
| `/var/lib/jenkins/plugins` | Jenkins controller target | Jenkins role helper and Jenkins service | `jenkins:jenkins` | Service-readable | Jenkins `.jpi` and `.hpi` plugins | Non-secret artifacts | Plugin digest evidence may reference this path |
| `/var/lib/jenkins/jcasc` | Jenkins controller target | Jenkins role helper and Jenkins service | `jenkins:jenkins` | `0700`; `jenkins.yaml` is `0600` | Jenkins Configuration as Code | Secret-bearing when it references credentials or manager password secrets | Evidence may record configured status, not secret values |
| `/var/lib/jenkins/secrets` and `/var/lib/jenkins/credentials.xml` | Jenkins controller target | Jenkins service | `jenkins:jenkins` | Service-private | Jenkins credential encryption material and credential metadata | Secret | Never include contents in evidence or logs |
| `/var/lib/jenkins/integration-ops` | Jenkins controller target | Shared integration helper; custody belongs to Jenkins controller runtime | `jenkins:jenkins` | `0700` | Integration operation workspace | Sensitive | Evidence may record public metadata and status only |
| `/var/lib/jenkins/integration-ops/keys` | Jenkins controller target | Shared integration helper; private keys owned by Jenkins controller | `jenkins:jenkins` | `0700`; key files are `0600` | Jenkins-to-Gerrit and Jenkins-to-agent private keys, public keys, known hosts | Secret-bearing | Evidence may record public key fingerprints and paths, never private keys |
| `/var/lib/jenkins/integration-ops/payloads` and `/var/lib/jenkins/integration-ops/tmp` | Jenkins controller target | Shared integration helper | `jenkins:jenkins` | `0700` | Temporary reviewed integration payloads and generated scripts | Sensitive until reviewed or removed | Logs must stay bounded and redacted |
| `/var/lib/jenkins/.ssh` | Jenkins controller target | Shared integration helper and Jenkins runtime | `jenkins:jenkins` | `0700`; `known_hosts` is `0600` | Jenkins SSH known-hosts material for agent access | Sensitive operational metadata | Evidence may record path and fingerprint status only |
| `/var/lib/jenkins/logs`, `/var/lib/jenkins/run`, and `/var/lib/jenkins/state` | Jenkins controller target | Jenkins helper and service | `jenkins:jenkins` | Service-writable | Runtime logs, pid files, readiness markers | Review-sensitive; bounded inspection only | Evidence records bounded references only |
| `/var/lib/jenkins-agent` | Jenkins agent target | Jenkins agent role helper, Jenkins agent runtime account, Jenkins controller scheduling | `jenkins-agent:jenkins-agent` by default | Service-owned; helper verifies runtime account home and ownership | Agent remote filesystem, bootstrap files, workspace, runtime config, logs | Sensitive because build workspaces and SSH state may exist | Evidence may reference status paths and remote FS value |
| `/var/lib/jenkins-agent/.ssh` | Jenkins agent target | Shared integration helper and Jenkins agent runtime | `jenkins-agent:jenkins-agent` | `0700`; `authorized_keys` is `0600` | Jenkins controller public key for SSH agent access | Sensitive access-control data | Evidence may record public key fingerprint only |
| `/var/lib/jenkins-agent/etc`, `/var/lib/jenkins-agent/run`, `/var/lib/jenkins-agent/logs`, and `/var/lib/jenkins-agent/state` | Jenkins agent target | Jenkins agent role helper | `jenkins-agent:jenkins-agent` | Runtime-account writable where needed | SSH daemon config, pid file, agent logs, readiness markers | Review-sensitive; bounded inspection only | Evidence records bounded references only |

## Shared And Transient Paths

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/mnt/jenkins-shared` | Jenkins controller target and Jenkins agent target | Shared integration helper | Runtime owner for each host, group `JENKINS_SHARED_GROUP` | Setgid group-write storage, normally `2775` | Shared integration proof storage only | Review-sensitive; not a credential store | Evidence records group name, GID, path, and read/write proof |
| `/run/sshd` and `/var/run/sshd` | Jenkins agent target | Jenkins agent role helper and SSH daemon | Root/system-owned runtime path | SSH daemon runtime prerequisite | SSH daemon runtime state | Low sensitivity | Recreated as needed; not audit evidence |
| `/tmp` transient files | Targets | Role helpers and integration helper | Creating process | Temporary only | REST payloads, public-key handoff files, generated Groovy scripts, transfer scratch | Potentially sensitive while present | Must not bypass reviewed helper inputs; do not retain as evidence |

## Docker Simulation Backing

Docker simulation realizes canonical paths under one generated run root:

```text
generated/simulation/docker/<run-id>/
```

| Docker run path | Canonical or container-visible path | Purpose |
| --- | --- | --- |
| `state/` | Harness-owned sideband state | Container state, rendered inputs, LDAP data, helper backing directories |
| `state/rendered/runtime-inputs/` | Operator-facing rendered input copies | Private runtime input files, normally written with mode `0600` |
| `state/bundle-factory/rendered/` | `/var/lib/loopforge/rendered` in bundle factory | Bundle-factory rendered inputs |
| `state/bundle-factory/evidence/` | `/var/lib/loopforge/evidence` in bundle factory | Bundle-factory evidence |
| `state/bundle-factory/artifact-bundle-work/` | `/var/lib/loopforge/artifact-bundle-work` in bundle factory | Bundle-factory workspaces |
| `state/gerrit/` | `/var/lib/loopforge` in Gerrit target | Gerrit helper state |
| `state/jenkins-controller/` | `/var/lib/loopforge` in Jenkins controller target | Jenkins controller helper state |
| `state/jenkins-agent/` | `/var/lib/loopforge` in Jenkins agent target | Jenkins agent helper state |
| `state/gerrit-validation-secrets/` | `/var/lib/loopforge/validation-secrets` in Gerrit target | Docker simulation-only validation secrets; host directory is `0700` |
| `state/shared-jenkins-storage/` | `JENKINS_SHARED_STORAGE_PATH`, normally `/mnt/jenkins-shared` | Shared Jenkins controller/agent integration storage |
| `state/ldap/data/` | `/var/lib/ldap` in LDAP container | Simulation-owned LDAP data |
| `state/ldap/config/` | `/etc/ldap/slapd.d` in LDAP container | Simulation-owned LDAP configuration |
| `product-homes/gerrit/` | `/srv/gerrit` in Gerrit target | Docker-backed Gerrit product home |
| `product-homes/jenkins-controller/` | `/var/lib/jenkins` in Jenkins controller target | Docker-backed Jenkins controller home |
| `product-homes/jenkins-agent/` | `/var/lib/jenkins-agent` in Jenkins agent target | Docker-backed Jenkins agent home |
| `staging/<role>/` | Host-side transfer scratch | Docker simulation staging scratch, not a product API |
| `exported-artifacts/` | Operator-facing artifact export | Exported archive handoff files and checksums |
| `evidence/` | `/var/lib/loopforge/evidence` in target containers | Retained Docker simulation evidence |
| `logs/` | `/var/log/loopforge` in target containers | Retained bounded Docker simulation logs |

Docker simulation host directories exist for operator review, debugging,
evidence collection, and cleanup. They are not target payload transfer
mechanisms unless a simulation doc explicitly labels the mechanism as a
simulation-only waiver, such as Docker `cp` during artifact staging.

Docker `clean` removes mutable generated runtime data under `state/`,
`product-homes/`, and `staging/` for the selected run root. It preserves
`exported-artifacts/`, `evidence/`, and `logs/`.

Evidence produced from Docker or VM simulation must be labeled as simulation
evidence and must not imply `target-deployment` acceptance.
