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

## Permission Classes

Loopforge permissions are classified by data sensitivity, not by whether a
path is produced by a harness. A harness does not inherently own secrets.
Harness-managed paths are secret-bearing only when they contain credentials,
private keys, full reviewed env inputs, or payloads that include those values.

| Class | Default mode | Use |
| --- | --- | --- |
| Secret/private directory | `0700` | Private key directories, SSH directories, operator input roots, Jenkins secret/JCasC directories, and validation key directories. |
| Secret/private file | `0600` | Private keys, full env inputs, Gerrit `secure.config`, Jenkins JCasC with secrets, cloud-init user-data with credentials, and secret-bearing payloads. |
| Review-sensitive directory | `0750` | Evidence, bounded logs, inventories, and status directories intended for operator or reviewer access but not public sharing. |
| Review-sensitive file | `0640` | Bounded logs, evidence records, inventories, status markers, and rendered non-secret config snapshots. |
| Public/read-only directory | `0755` | Non-secret helper trees, artifact review directories, and published bundle directories. |
| Public/read-only file | `0644` | Archives, checksums, public keys, manifest contracts, non-secret run/checkpoint markers, helper libraries, and templates. |
| Executable helper file | `0755` | Role helper scripts staged as non-secret control-plane input. |
| Shared setgid directory | `2775` | Jenkins controller/agent shared integration storage. |

Official source guidance informs these classes. Gerrit recommends a dedicated
Unix account for the Gerrit site and ownership of that site by that account:
<https://gerrit-review.googlesource.com/Documentation/install.html>.
Jenkins documents `$JENKINS_HOME/secrets` and the controller key as sensitive
credential material, and recommends `0600` for secret-bearing systemd
drop-ins when in doubt:
<https://www.jenkins.io/doc/book/system-administration/backing-up/> and
<https://www.jenkins.io/doc/book/system-administration/systemd-services/>.
Docker documents that bind mounts are writable by default and supports
read-only mounts when host mutation is not intended:
<https://docs.docker.com/engine/storage/bind-mounts/>. Libvirt documents
directory pools and volumes as libvirt-managed VM storage, so Loopforge uses
libvirt APIs and metadata instead of repairing VM disk ownership directly:
<https://libvirt.org/storage.html>.

## Product Homes

Product homes are service-owned runtime directories. They are separate from
helper-owned `/var/lib/loopforge/` state.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/srv/gerrit` | Gerrit target | Gerrit service and Gerrit role helper | `gerrit:gerrit` by default | Service-owned; helper verifies runtime account home and ownership | Gerrit site, repositories, config, plugins, indexes, logs, runtime markers | Sensitive because config can include LDAP/service authentication material | Backups and evidence may reference subpaths; secrets must be protected |
| `/srv/gerrit/etc` | Gerrit target | Gerrit role helper and Gerrit service | `gerrit:gerrit` | Protected configuration directory | `gerrit.config`, `secure.config`, manifests | Secret-bearing when `secure.config` exists | Evidence may record config status, not secret values |
| `/srv/gerrit/etc/secure.config` | Gerrit target | Gerrit role helper and Gerrit service | `gerrit:gerrit` | `0600` | Gerrit secure configuration such as LDAP bind password material | Secret | Never include file contents in evidence or logs |
| `/srv/gerrit/plugins` | Gerrit target | Gerrit service and operator-managed plugin operations | `gerrit:gerrit` | Service-readable | Operator-managed Gerrit plugin JARs | Non-secret artifacts | Loopforge evidence does not validate external Gerrit plugin state |
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
| `/data/jenkins-shared` | Jenkins agent target export and Jenkins controller target mount | Shared integration helper | Jenkins agent runtime owner on the export, group `JENKINS_SHARED_GROUP` on both hosts | NFS-backed setgid group-write storage, normally `2775` | Shared integration proof storage only | Review-sensitive; not a credential store | Evidence records group name, GID, path, export source, mount target, and read/write proof |
| `/tmp` transient files | Targets | Role helpers and integration helper | Creating process | Temporary only | REST payloads, public-key handoff files, generated Groovy scripts, transfer scratch | Potentially sensitive while present | Must not bypass reviewed helper inputs; do not retain as evidence |

## Operator Input Custody

Reviewed role env files are operator inputs, not helper-owned state. On the
bundle factory and role targets, their canonical execution paths derive from
the selected operator account:

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/home/<operator-account>/loopforge-inputs/` | Bundle factory and targets | Human operator, machine runner, or simulation transfer utility | Selected operator account and group | `0700` | Reviewed helper inputs transferred for execution | Private operator input custody | Evidence may record the path and transfer status, never file contents; cleanup follows the selected environment lifecycle |
| `/home/<operator-account>/loopforge-inputs/<role>.env` | Bundle factory and matching role target | Human operator, machine runner, or simulation transfer utility; role helper reads only | Selected operator account and group | `0600` | Full reviewed env input for `gerrit`, `jenkins-controller`, or `jenkins-agent` | Review-sensitive; execution-time secrets such as LDAP bind passwords remain excluded | Replace atomically before helper execution; never embed in bundles, helper state, service state, logs, or evidence |

The default example operator account resolves these paths to
`/home/ci-operator/loopforge-inputs/<role>.env`. Bundle-factory and target
execution use the same flat role filenames; environment names, run IDs, and a
`bundle-factory/` directory are not part of the canonical path.

## Role Helper Custody

Role helpers execute from one operator-owned tree on the bundle factory and
role targets. The selected environment stages the complete tree before helper
execution and retains it until environment cleanup:

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/home/<operator-account>/loopforge/` | Bundle factory and targets | Human operator, machine runner, or simulation transfer utility | Selected operator account and group | Root and directories `0755`; regular files `0644`; role helper scripts `0755` | `scripts/common.sh`, all three role helper scripts, and all three role template trees | Executable control-plane input; no secrets | Stage as a complete tree before execution; retain across lifecycle commands until environment teardown; remove directly during cleanup without delegated privilege or permission repair |

The default operator account resolves the root to
`/home/ci-operator/loopforge/`. Role helpers execute from its `scripts/`
directory. Run IDs and role-specific package directories are not part of the
canonical path. `scripts/integration-setup.sh` is a separate shared
integration helper and is outside this role-helper path contract.

## Helper-Owned Paths

Helper-owned paths are execution state, not Gerrit or Jenkins service homes.
`/var/lib/loopforge` is the Loopforge helper state root, and
`/var/log/loopforge` is the Loopforge helper log root. Role helpers create
these roots and practical child paths during reviewed lifecycle commands,
including bundle-factory `prepare-artifacts` and target workspace
preparation. Simulation harnesses do not pre-create, bind-mount, or
recursively repair helper-visible Loopforge roots for role helpers. The
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

## Retained Simulation Output

Simulation cleanup preserves review output: exported artifact archives,
evidence, and bounded logs. When a cleanup command clears active retained
output directories for later run reuse, it first backs those outputs up to a
host-owned retained-output snapshot such as
`host/retained-output-backups/<timestamp>/` inside the selected generated run
root.

Backup snapshots are review artifacts. Cleanup must not convert active
target-dominated outputs into host-owned outputs in place; it may copy them
into retained host-owned review locations before clearing active runtime
directories. Layer-specific lifecycle commands may remove mutable generated
state, stop containers, restore VM snapshots, or delete selected-run scratch,
but they must not silently discard retained evidence, logs, or exported
artifacts.

## Artifact Extraction Paths

Artifact extraction paths are target-side staging roots. Role helpers consume
the helper-visible payload directories after archive and checksum validation.

| Path | Environment | Lifecycle owner | OS owner/group | Permission model | Contents | Sensitivity | Evidence and cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/var/lib/loopforge/staging/gerrit/` | Gerrit target | Artifact staging flow and Gerrit role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by Gerrit helper after checksum verification | Gerrit WAR, templates, manifest, checksums | Must not include integration keys, secrets, or external Gerrit plugins | Gerrit install consumes this path only |
| `/var/lib/loopforge/staging/jenkins/` | Jenkins controller target | Artifact staging flow and Jenkins controller role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by Jenkins helper after checksum verification | Jenkins WAR, plugin manager, plugins, templates, manifest, checksums | Must not include Jenkins credentials or keys | Jenkins install consumes this path only |
| `/var/lib/loopforge/staging/jenkins-agent/` | Jenkins agent target | Artifact staging flow and Jenkins agent role helper | Operator account and group; default example `ci-operator:ci-operator` | Readable by agent helper after checksum verification | Agent bootstrap files, templates, manifest, checksums | Must not include authorized keys or private keys | Agent install consumes this path only |

## Docker Simulation Backing

Docker simulation realizes canonical paths under one generated run root:

```text
generated/simulation/docker/<run-id>/
```

| Docker run path | Canonical or container-visible path | Content dominance | Purpose |
| --- | --- | --- | --- |
| `host/rendered/` | Operator-facing rendered harness config | Host-dominated | Rendered harness env, run markers, and public manifest contract; rendered env files are review-sensitive, manifest contracts and non-secret markers are public/read-only |
| `host/runtime-inputs/` | Operator-facing rendered input copies | Host-dominated | Private runtime input files, written with mode `0600` |
| `host/bundle-factory/rendered/` | Host-side reviewed bundle-factory input copies | Host-dominated | Operator review copy before Docker `cp` input transfer |
| `host/bundle-factory/validation-public/` | Host-to-bundle-factory validation handoff | Host-dominated | Simulation validation public material only |
| `host/target-ssh/` | Host-side target SSH material | Host-dominated | Host-generated target SSH identity, public key, and known hosts; Docker simulation copies only the public key into targets through `/home/ci-operator/loopforge-inputs` as control-plane input |
| `host/validation-secrets/gerrit/` | Host-side Docker simulation validation key material | Host-dominated | Docker simulation-only SSH validation key material; not used for LDAP bind secrets; host directory is `0700` |
| `host/evidence/harness/` | Harness evidence output | Host-dominated | Harness checkpoint evidence, review-sensitive and redacted |
| `host/logs/harness/` | Harness bounded log output | Host-dominated | Harness command logs, review-sensitive and bounded |
| `host/evidence/integration/` | Integration helper evidence output | Host-dominated | Host-orchestrated integration evidence, review-sensitive and redacted |
| `host/logs/integration/` | Integration helper bounded log output | Host-dominated | Host-orchestrated integration logs, review-sensitive and bounded |
| `host/retained-output-backups/<timestamp>/` | Operator-facing clean backup snapshot | Host-dominated | Host-owned backups of retained outputs before active dirs are cleared |
| `target/helper-state/integration/` | Shared integration helper state | Target-dominated | Cross-role integration status and helper state for the host-orchestrated integration utility |
| `target/shared-jenkins-storage/` | `JENKINS_SHARED_STORAGE_PATH`, normally `/data/jenkins-shared` | Target-dominated | Shared Jenkins controller/agent integration storage |
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

## VM Simulation Backing

VM simulation separates reusable VM-set state from run-scoped output:

```text
generated/simulation/vm/vm-sets/<vm-set-id>/
generated/simulation/vm/<run-id>/
```

| VM path | Canonical or VM-visible path | Content dominance | Purpose |
| --- | --- | --- | --- |
| `vm-sets/<vm-set-id>/` | VM-set registry root | Host-dominated | Ownership marker, selected VM set identity, and reusable resource records |
| `vm-sets/<vm-set-id>/libvirt/` | Libvirt resource metadata | Host-dominated | Operator-owned domain, network, pool, volume, seed media, and baseline snapshot descriptors |
| `vm-sets/<vm-set-id>/libvirt/disks/` | Libvirt directory-pool target | Libvirt-dominated | VM-set-local base image and mutable qcow2 machine volumes managed and inspected through libvirt after adoption; the host operator does not repair or depend on their POSIX ownership |
| `vm-sets/<vm-set-id>/seeds/` | Cloud-init or seed media records | Host-dominated | Simulation-owned VM bootstrap inputs and rendered seed metadata, including LDAP VM bootstrap or LDIF seed material when represented as seed media |
| `vm-sets/<vm-set-id>/snapshots/` | Baseline snapshot records | Host-dominated | Clean baseline snapshot names, fingerprints, and capture evidence |
| Jenkins agent VM disk content | NFS export backing `JENKINS_SHARED_STORAGE_PATH`, normally `/data/jenkins-shared` | Target-dominated | Jenkins-agent-hosted shared storage exported to the controller VM |
| `host/rendered/` | Operator-facing rendered harness config | Host-dominated | Rendered harness env, VM inventory, run markers, and manifest contract; rendered env and inventory files are review-sensitive, manifest contracts and non-secret markers are public/read-only |
| `host/runtime-inputs/` | Operator-facing rendered input copies | Host-dominated | Private runtime input files, written with mode `0600` |
| `host/target-ssh/` | Host-side target SSH material | Host-dominated | Target OS SSH identity and known-hosts material for VM control-plane access |
| `host/evidence/harness/` | Harness evidence output | Host-dominated | VM harness checkpoint evidence, review-sensitive and redacted |
| `host/logs/harness/` | Harness bounded log output | Host-dominated | VM harness command logs, review-sensitive and bounded |
| `host/evidence/integration/` | Integration helper evidence output | Host-dominated | Host-orchestrated integration evidence, review-sensitive and redacted |
| `host/logs/integration/` | Integration helper bounded log output | Host-dominated | Host-orchestrated integration logs, review-sensitive and bounded |
| `host/artifacts/exported/` | Operator-facing artifact review copies | Host-dominated | Exported bundle archives and checksums copied back for review; not a target transfer path |
| `host/retained-output-backups/<timestamp>/` | Operator-facing clean backup snapshot | Host-dominated | Backups of retained outputs before active dirs are cleared |
| `target/evidence/<role>/` | `/var/lib/loopforge/evidence` on one target VM | Target-dominated | Retained role-local VM simulation evidence |
| `target/logs/<role>/` | `/var/log/loopforge` on one target VM | Target-dominated | Retained role-local bounded VM simulation logs |

VM artifact staging uses target OS SSH to copy reviewed bundle archives into
the guest-local canonical staging path `/var/lib/loopforge/staging/<role>/`.
The VM generated run tree may keep host-owned artifact review copies, but it
must not model transfer with a generated `target/artifacts/staging/` sideband.

VM-set state persists across runs until `destroy`. Run-scoped output belongs
to one `HARNESS_RUN_ID` and may be cleaned independently. `clean` rolls the
selected VM set back to the clean baseline snapshot and removes mutable
selected-run state, while preserving exported artifacts, evidence, bounded
logs, and retained-output backups. `destroy` is the only command that removes
simulation-owned VM domains, the VM-set-local base image, machine disks,
snapshots, seed media, or networks after ownership validation or exact selected
resource recovery. VM shared Jenkins storage is not VM-host state; it is
guest-local data on the Jenkins agent VM and is removed only as part of owned
VM disk destruction.

The host operator owns VM control metadata but does not own adopted qcow2
content. Libvirt volume APIs provide format, capacity, backing-store, hashing,
and deletion operations without requiring direct host reads or ownership
repair. Domains attach libvirt-reported mutable volume paths as file-backed
disks so the host security driver manages runtime access without a hard-coded
account. Read-only backing volumes are validated independently of their
incidental owner. Harness behavior must not depend on ownership restoration
after shutdown.

Evidence produced from Docker or VM simulation must be labeled as simulation
evidence and must not imply `target-deployment` acceptance.
