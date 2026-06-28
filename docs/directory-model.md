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
| `/tmp` transient files | Targets | Role helpers and integration helper | Creating process | Temporary only | REST payloads, public-key handoff files, generated Groovy scripts, transfer scratch | Potentially sensitive while present | Must not bypass reviewed helper inputs; do not retain as evidence |

## Helper-Owned Paths

Helper-owned paths are execution state, not Gerrit or Jenkins service homes.
`/var/lib/loopforge` is the Loopforge helper state root, and
`/var/log/loopforge` is the Loopforge helper log root. Role helpers create
these roots and practical child paths during reviewed lifecycle commands,
including bundle-factory `prepare-artifacts` and target workspace
preparation. Simulation harnesses do not pre-create, bind-mount, or
recursively repair container-visible Loopforge roots for role helpers. The
general utility boundary is defined in `docs/system-model.md`: helpers are
self-contained where practical, and harnesses do only the environment work
they must do.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/var/lib/loopforge/` | Bundle factory and targets | Role helpers | Operator account and group; default example `ci-operator:ci-operator` | Private where sensitive child state is present | Loopforge helper state root: staging handoff, helper state, evidence, and bundle preparation state | Mixed; child paths can contain sensitive operational metadata | Evidence may reference child paths, but must not include secret values |
| `/var/lib/loopforge/preparing/` | Bundle factory | Role helper `prepare-artifacts` | Operator account and group; default example `ci-operator:ci-operator` | Writable by helper only | Prepared role bundle trees, release archives, manifests, and checksums | Non-secret artifact workspace; must not contain private keys, passwords, tokens, or LDAP bind secrets | Role helpers create this path when practical, then create and clean their own bundle trees |
| `/var/lib/loopforge/staging/` | Targets | Role helpers; transfer utilities may copy archive pairs into the existing helper-created root through an explicit waiver | Operator account and group; default example `ci-operator:ci-operator` | Writable by helper and reviewed transfer flow | Incoming release archive pairs and extracted one-time bundle trees | Non-secret handoff; must not become an OS dependency bundle | Missing or checksum-mismatched content blocks readiness; extracted bundle trees are disposable staging state |
| `/var/lib/loopforge/evidence/` | Bundle factory and targets | Role helpers and evidence collector | Operator account and group; default example `ci-operator:ci-operator` | Writable by helper; readable by approved evidence reviewers | JSON summaries, status records, bounded references | Must be redacted; may include public key fingerprints and paths | Retained for audit; simulation cleanup preserves generated evidence copies |
| `/var/log/loopforge/` | Bundle factory and targets | Helpers | Operator account and group; default example `ci-operator:ci-operator` | Writable by helper; bounded reads only | Loopforge helper log root: helper logs and command logs | Must not include private keys, passwords, tokens, LDAP bind secrets, or full secret-bearing env values | Evidence may include bounded log references |

Public internet fallback on target hosts is not a supported product behavior.
When simulation records public fallback for Ubuntu or OS dependencies, the
path, log, and evidence labels must say `simulation-only`.

## Artifact Extraction Paths

Artifact extraction paths are target-side staging roots. Role helpers consume
the helper-visible payload directories after archive and checksum validation.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/var/lib/loopforge/staging/gerrit-artifacts-bundle/` | Gerrit target | Artifact staging flow | Operator account and group; default example `ci-operator:ci-operator` | Readable by role helper after checksum verification | Extracted Gerrit bundle root | Non-secret application artifacts only | Checksum verification evidence must reference the staged payload |
| `/var/lib/loopforge/staging/gerrit-artifacts-bundle/gerrit/` | Gerrit target | Gerrit role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by Gerrit helper | Gerrit WAR, plugins, templates, manifests, checksums | Must not include integration keys or secrets | Gerrit install consumes this path only |
| `/var/lib/loopforge/staging/jenkins-artifacts-bundle/` | Jenkins controller target | Artifact staging flow | Operator account and group; default example `ci-operator:ci-operator` | Readable by role helper after checksum verification | Extracted Jenkins bundle root | Non-secret application artifacts only | Checksum verification evidence must reference the staged payload |
| `/var/lib/loopforge/staging/jenkins-artifacts-bundle/jenkins/` | Jenkins controller target | Jenkins controller role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by Jenkins helper | Jenkins WAR, plugin manager, plugins, templates, manifests, checksums | Must not include Jenkins credentials or keys | Jenkins install consumes this path only |
| `/var/lib/loopforge/staging/jenkins-agent-artifacts-bundle/` | Jenkins agent target | Artifact staging flow | Operator account and group; default example `ci-operator:ci-operator` | Readable by role helper after checksum verification | Extracted Jenkins agent bundle root | Non-secret bootstrap artifacts only | Checksum verification evidence must reference the staged payload |
| `/var/lib/loopforge/staging/jenkins-agent-artifacts-bundle/jenkins-agent/` | Jenkins agent target | Jenkins agent role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by agent helper | Agent bootstrap files, templates, manifests, checksums | Must not include authorized keys or private keys | Agent install consumes this path only |

## Docker Simulation Backing

Docker simulation realizes canonical paths under one generated run root:

```text
generated/simulation/docker/<run-id>/
```

| Docker run path | Canonical or container-visible path | Content dominance | Purpose |
| --- | --- | --- | --- |
| `host/rendered/` | Operator-facing rendered harness config | Host-dominated | Rendered harness env and manifest contract |
| `host/runtime-inputs/` | Operator-facing rendered input copies | Host-dominated | Private runtime input files, normally written with mode `0600` |
| `host/bundle-factory/rendered/` | Host-side reviewed bundle-factory input copies | Host-dominated | Operator review copy before Docker `cp` input transfer |
| `host/bundle-factory/validation-public/` | Host-to-bundle-factory validation handoff | Host-dominated | Simulation validation public material only |
| `host/target-ssh/` | Host-side target SSH material | Host-dominated | Host-generated target SSH identity, public key, and known hosts; Docker simulation copies only the public key into targets through `/home/ci-operator/loopforge-inputs` as control-plane input |
| `host/validation-secrets/gerrit/` | Host-side Docker simulation validation key material | Host-dominated | Docker simulation-only SSH validation key material; not used for LDAP bind secrets; host directory is `0700` |
| `host/evidence/harness/` | Harness evidence output | Host-dominated | Harness checkpoint evidence |
| `host/logs/harness/` | Harness bounded log output | Host-dominated | Harness command logs |
| `host/evidence/integration/` | Integration helper evidence output | Host-dominated | Host-orchestrated integration evidence |
| `host/logs/integration/` | Integration helper bounded log output | Host-dominated | Host-orchestrated integration logs |
| `host/retained-output-backups/<timestamp>/` | Operator-facing clean backup snapshot | Host-dominated | Host-owned backups of retained outputs before active dirs are cleared |
| `target/helper-state/integration/` | Shared integration helper state | Target-dominated | Cross-role integration status and helper state for the host-orchestrated integration utility |
| `target/shared-jenkins-storage/` | `JENKINS_SHARED_STORAGE_PATH`, normally `/mnt/jenkins-shared` | Target-dominated | Shared Jenkins controller/agent integration storage |
| `target/ldap/data/` | `/var/lib/ldap` in LDAP container | Target-dominated | Simulation-owned LDAP data |
| `target/ldap/config/` | `/etc/ldap/slapd.d` in LDAP container | Target-dominated | Simulation-owned LDAP configuration |
| `target/product-homes/gerrit/` | `/srv/gerrit` in Gerrit target | Target-dominated | Docker-backed Gerrit product home |
| `target/product-homes/jenkins-controller/` | `/var/lib/jenkins` in Jenkins controller target | Target-dominated | Docker-backed Jenkins controller home |
| `target/product-homes/jenkins-agent/` | `/var/lib/jenkins-agent` in Jenkins agent target | Target-dominated | Docker-backed Jenkins agent home |
| `target/artifacts/staging/<role>/` | Host-to-target transfer scratch | Target-dominated | Docker simulation staging scratch, not a product API |
| `target/artifacts/exported/` | Operator-facing artifact export | Target-dominated | Exported archive handoff files and checksums |
| `target/evidence/<role>/` | `/var/lib/loopforge/evidence` in one target container | Target-dominated | Retained role-local Docker simulation evidence, recursively helper-owned while active |
| `target/logs/<role>/` | `/var/log/loopforge` in one target container | Target-dominated | Retained role-local bounded Docker simulation logs, recursively helper-owned while active |

Docker simulation host directories exist for operator review, debugging,
evidence collection, cleanup, and explicit Docker `cp` waivers. They are not
target payload transfer mechanisms unless a simulation doc explicitly labels
the mechanism as a simulation-only waiver, such as Docker `cp` during artifact
staging or operator input transfer. Container-visible role helper paths under
`/var/lib/loopforge` and `/var/log/loopforge` are created by the helpers with
the target or bundle-factory operator account, default example
`ci-operator:ci-operator`. Content dominance describes who contributes the
durable meaningful content, not POSIX ownership of host review copies.
Host-side generated paths use the local host account that runs the simulation
harness; this host account is not required to be named `ci-operator`.

Docker `clean` backs up retained outputs to
`host/retained-output-backups/<timestamp>/`, whose copied contents are
host-owned review artifacts. It clears active retained output directories and
removes mutable generated runtime data under `host/` and `target/` for the
selected run root. `clean` must not convert active target-owned outputs into
host-owned outputs in place.

Evidence produced from Docker or VM simulation must be labeled as simulation
evidence and must not imply `target-deployment` acceptance.
