# Shared Integration Setup Manual

## Purpose And Scope

This manual is the operator guide for `scripts/integration-setup.sh`. Use it
after the Gerrit, Jenkins controller, and Jenkins agent role setup manuals have
completed and each role has passing role-local readiness evidence.

This manual owns the shared integration helper workflow for mode-appropriate
bound inputs. The native reference at
`docs/operations/native/integration.md` is the procedural baseline for direct
integration operations. Keep this helper workflow aligned with that baseline
and preserve equivalent product state and validation outcomes.

The Standard Interfaces contract in `docs/architecture/system-model.md` is authoritative
for this helper. `scripts/integration-setup.sh` must use SSH as the common
OS/control-plane interface for Gerrit, Jenkins controller, and Jenkins agent
targets across Docker simulation, VM simulation, and `target-deployment`.
Docker APIs are simulation lifecycle internals and are not the shared
integration communication surface.

`docs/contracts/lifecycle-contract.md` owns shared phase behavior, product
checkpoint semantics, mutation boundaries, and resume/rerun rules. This manual
applies that contract only to the shared integration helper workflow.

The shared integration helper owns cross-role work only: Jenkins-to-Gerrit SSH,
Jenkins-to-agent SSH, Gerrit Trigger configuration, Jenkins node readiness,
trigger verification, `Verified` voting, Jenkins shared storage, and
integration evidence. It does not replace the role setup manuals and it does
not provide native OS operation instructions.

`target-deployment` workflow creates two reviewed Gerrit changes. The
`All-Projects` change contains the global `Verified` CI label and
`stream-events` capability. The target-project change contains Jenkins read
access and `label-Verified -1..+1` grants on the reviewed ref pattern.
Docker and VM simulation do not create those reviews. Their
`configure-integration` phase uses the selected `apply-direct` mode, labeled
`simulation-only direct Gerrit REST apply`, and validates the same effective
permissions.
Jenkins Gerrit Trigger uses SSH for authentication and event streaming, while
the Gerrit REST review API is the default path for posting `Verified` votes.
For the REST path, the helper generates a Gerrit HTTP auth token for the
`jenkins-gerrit` service account during `configure-integration` and stores it
only in Jenkins Gerrit Trigger configuration. Operators do not provide the
service-account REST token as a normal env input. Normal configuration must not
delete or rotate an existing token. Existing credential state that is not part
of the exact input-bound completed integration state blocks setup; credential
rotation is site-owned administration outside Loopforge v1.

Helper-generated shared state and helper logs on target environments live
under `/var/lib/loopforge/` and `/var/log/loopforge/`.

Legacy SSH review commands and flags are not part of the default workflow. Use
them only with explicit operator justification and runtime compatibility
evidence for the installed Gerrit and Gerrit Trigger versions.

## Prerequisites

Before running the shared helper:

- Gerrit role setup is complete and `scripts/gerrit-setup.sh validate` has
  produced role-local readiness evidence.
- Jenkins controller role setup is complete and
  `scripts/jenkins-controller-setup.sh validate` has produced controller-only
  readiness evidence.
- Jenkins agent role setup is complete and `scripts/jenkins-agent-setup.sh
  validate` has produced agent-host readiness evidence.
- Reviewed target-deployment env files or published effective simulation env
  files exist for Gerrit, Jenkins controller, Jenkins agent, and shared
  integration values.
- Target-deployment env files have been reviewed, while simulation effective
  files have been rendered and validated by the harness, for role/account
  separation, endpoints, ref patterns, labels, credential IDs, evidence paths,
  and verification mode labels.
- The mode-appropriate env files set `LOOPFORGE_OPERATOR_ACCOUNT` and
  `LOOPFORGE_OPERATOR_GROUP` when the deployment uses an operator account or
  group other than the default example `ci-operator:ci-operator`.
- Target deployment defines complete OS SSH access in the reviewed integration
  env. Simulation supplies current backend-assigned target SSH hosts through
  the private invocation adapter while stable access values remain in the
  published effective integration env.
- The Jenkins agent host can run the NFS server for
  `JENKINS_SHARED_STORAGE_PATH`, normally `/data/jenkins-shared`, and the
  Jenkins controller host can mount that agent export at the same path.
- Shared application and credential state is fresh. The only permitted
  existing state is a target-deployment review wait bound to the same two
  Gerrit changes, or exact input-bound completed state that returns
  `already-complete` without mutation. Simulation has no review wait.
- Operators have confirmed that any public internet fallback on target hosts is
  simulation-only and will be labeled that way in docs, logs, and evidence.

## Operator Inputs And Custody

Required target-deployment operator inputs include:

- Reviewed Gerrit env file.
- Reviewed Jenkins controller env file.
- Reviewed Jenkins agent env file.
- Reviewed shared integration env file, normally copied from
  `examples/integration.env.example`.
- Gerrit admin credential or approved automation credential for creating the
  reviewed `All-Projects` label/capability change, target-project access
  change, and Jenkins Gerrit integration auth token.
- Jenkins admin credential or approved automation credential for credential,
  Gerrit Trigger, node, and job configuration.
- Jenkins Gerrit integration account or group.
- Gerrit integration auth token ID, defaulting to `jenkins-trigger`.
- Gerrit project and ref scope for Jenkins read and `label-Verified -1..+1`
  grants.
- Jenkins agent node name, scheduling label, executor policy, and remote
  filesystem values.
- Jenkins shared storage group, GID, and path. The v1 default path is
  `/data/jenkins-shared`; the Jenkins agent host exports it over NFS and the
  Jenkins controller mounts the export at the same path.
- Disposable verification project, branch, job, and run ID values.
- Target OS SSH inventory for Gerrit, Jenkins controller, and Jenkins agent:
  host, port, user, identity file, and known-hosts file.

For simulation, the harness selects source templates, publishes stable
effective role and integration env files after `start`, verifies current target
access, and supplies only ephemeral target SSH hosts through its private helper
invocation adapter. Operators do not review or maintain DHCP addresses as env
input.

The Gerrit admin and test accounts must already be provisioned in Gerrit before
target deployment integration begins. LDAP directory entries alone are not
enough for Gerrit REST Basic Auth under the `HTTP_LDAP` policy; these users
must sign in to Gerrit once, or the site must provision the accounts through an
approved equivalent. Docker and VM simulation may perform this initial login
automatically with simulation-owned credentials. The Jenkins Gerrit integration
account is different: the integration helper creates or validates it as a
Gerrit service account and then generates its Gerrit auth token.

Custody and redaction rules:

- Jenkins controller owns the Jenkins-to-Gerrit private key and the
  Jenkins-to-agent private key.
- Gerrit receives only the Jenkins-to-Gerrit public key.
- Jenkins agent receives only the Jenkins-to-agent public key.
- Evidence may record public key fingerprints, credential IDs that do not
  encode secrets, account names, endpoints, change numbers, build URLs, mode
  labels, and bounded log paths.
- Evidence must not include private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing env values.
- Verbose Gerrit, Jenkins, Docker, SSH, package-manager, VM, or verification
  logs must be written to bounded log files and referenced, not streamed.

## Standard Interfaces

The helper separates target OS access from service endpoints.

OS/control-plane access:

- Gerrit target OS access uses the Gerrit target SSH inventory.
- Jenkins controller target OS access uses the Jenkins controller target SSH
  inventory.
- Jenkins agent target OS access uses the Jenkins agent target SSH inventory.
- SSH-based file transfer, such as `scp` or `rsync`, is the standard path for
  public-key handoff, bounded payload upload, bounded log retrieval, and
  helper-generated state retrieval.

Service endpoints:

- Gerrit HTTP REST comes from the reviewed target-deployment or published
  effective simulation Gerrit role env and is used for
  service-account token generation, account/key registration, config-review
  workflow, review state checks, and Gerrit Trigger vote posting.
- Gerrit SSH comes from the mode-appropriate bound Gerrit role env and is used
  for Jenkins-to-Gerrit authentication and `stream-events` proof.
- Jenkins HTTP/API/script access comes from the mode-appropriate bound Jenkins
  controller role env and is used for credentials, nodes, trigger server, jobs,
  builds, and readiness operations.
- Jenkins controller-to-agent SSH comes from the mode-appropriate bound Jenkins
  agent role env and is the runtime build-agent connection, not the operator
  control-plane SSH channel.

The implementation should expose neutral primitives equivalent to:

```text
target_exec <gerrit|jenkins-controller|jenkins-agent> <command>
target_copy_to <gerrit|jenkins-controller|jenkins-agent> <local> <remote>
target_copy_from <gerrit|jenkins-controller|jenkins-agent> <remote> <local>
target_run_as <gerrit|jenkins-controller|jenkins-agent> <account> <command>
```

Those primitives must use SSH plus `scp` or `rsync`. The integration helper
must not call Docker APIs, derive container names, or require
the derived Compose project name. Docker simulation may use Docker APIs only
to create, start, stop, inspect, and wire the simulation; it must expose
logical targets through the same SSH and service interfaces used by VM
simulation and `target-deployment`.

Service API calls may originate from the control node or from a target over
SSH when network reachability requires it. Evidence must record the selected
origin when that origin affects interpretation of the proof.

Shared Jenkins storage is a target OS concern prepared during shared
integration. In v1 the Jenkins agent host is the NFS server for
`JENKINS_SHARED_STORAGE_PATH`, normally `/data/jenkins-shared`. The controller
mounts the agent export at that same path. The helper must validate the shared
group/GID on both Jenkins hosts, create or validate the agent-hosted export
directory with setgid group-write permissions, keep `root_squash` enabled by
default, validate the controller mount source, and prove controller-write plus
agent-read behavior through runtime accounts.

## Gerrit ACL Modes

The shared helper supports these ACL workflow modes:

| Mode | Default environment | Behavior |
| --- | --- | --- |
| `create-review` | `target-deployment` | Create the reviewable `All-Projects` and target-project changes through REST, record both change IDs and URLs, and return `blocked` without setup success until external approved submission makes both effective. |
| `apply-direct` | `docker-simulation`, `vm-simulation` | Directly apply Gerrit REST label/access changes when explicitly selected, label the action `simulation-only direct Gerrit REST apply`, and validate effective global and project/ref state. Reviewed Access is `not-applicable`. |

`target-deployment` setup resumes only with the same reviewed inputs, targets,
selected state, ACL mode, and two review identifiers. It must fail closed until
both reviews have been submitted and Gerrit reports the global `Verified`
label, `stream-events`, and scoped read and `label-Verified -1..+1`
permissions as effective.

`apply-direct` must fail closed outside simulation modes. Simulation evidence
must not claim review creation, approval, submission, or target-deployment
acceptance.

## Helper Command Workflow

For target deployment, set the shared env arguments once and reuse them for
every helper command:

```bash
common_args=(
  --gerrit-env <reviewed-gerrit.env>
  --jenkins-controller-env <reviewed-jenkins-controller.env>
  --jenkins-agent-env <reviewed-jenkins-agent.env>
  --integration-env <reviewed-integration.env>
)
```

For simulation, invoke the backend harness integration phase. The harness
passes the published effective role env files and its private temporary
integration adapter to this same helper interface; operators do not construct
or retain that adapter.

Review the complete integration plan and validate its inputs without mutation:

```bash
scripts/integration-setup.sh "${common_args[@]}" --dry-run configure-integration
```

Apply Jenkins-to-Gerrit SSH setup after review:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes configure-integration
```

In `target-deployment`, the first mutating invocation creates the two Gerrit
reviews and returns `blocked` without a setup-success marker. After external
approval and submission, rerun the same command with the same reviewed inputs
to validate both reviews and complete shared setup. Do not change inputs or
replace review identifiers across that resume boundary.

Validate cross-role readiness:

```bash
scripts/integration-setup.sh "${common_args[@]}" validate-integration
```

Run end-to-end integration proof:

```bash
scripts/integration-setup.sh "${common_args[@]}" --yes prove-integration
```

Collect sanitized integration evidence:

```bash
scripts/integration-setup.sh "${common_args[@]}" collect-evidence
```

Use `--dry-run` only for planning commands. Dry runs must not create Gerrit or
Jenkins state, disposable projects, Jenkins jobs, credentials, nodes, review
votes, or evidence that claims runtime success.

## Validation Contract

`validate-integration` is observational. It requires matching shared-setup
state and performs read-only SSH and application queries for:

- Mode-appropriate Gerrit access is effective: both target-deployment reviews
  are submitted, or simulation direct global and project/ref checks pass.
- Jenkins-to-Gerrit SSH authentication as the integration account.
- Global `Verified`, `stream-events`, and target-project read/vote authority.
- Jenkins-to-agent SSH authentication from the controller.
- Shared group, export, mount, and storage permissions, while consuming the
  setup-owned write/read result without creating another proof file.
- Jenkins node configuration and online state.
- Gerrit Trigger server configuration and connection state.

Validation writes only bounded local status, logs, and evidence. It must not
create target directories, credentials, nodes, jobs, builds, changes, storage
files, events, or votes, and it must not repair shared setup.

`prove-integration` requires the matching validation marker. It creates the
labeled disposable verification job and one Gerrit change, observes
`patchset-created` delivery over Gerrit SSH, schedules and runs the build on the
selected agent, verifies REST `Verified +1`, and confirms Gerrit review state.
It must not invoke validation implicitly. REST vote posting does not replace
the SSH event-delivery proof.

## Evidence And Failure Classification

`collect-evidence` emits integration-scoped records using the common evidence
contract. Records must identify the verification mode, timestamp, command,
checkpoint, mode-appropriate input and selected-state binding, both Gerrit
review IDs and URLs, public key fingerprints, credential IDs where safe,
endpoints, disposable artifact IDs, observed checks, bounded log references,
redaction status, and final status. Partial collection must not promote a
blocked or incomplete checkpoint to pass.

Classify failures at the point where proof breaks:

| Failure point | Classification |
| --- | --- |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` capability or Gerrit Trigger server connectivity failure. |
| Global `Verified` label is absent | `All-Projects` label definition failure. |
| Jenkins cannot vote `Verified -1..+1` on the reviewed ref scope | Project/ref access grant failure. |
| Jenkins cannot authenticate to the agent over SSH | Jenkins-to-agent SSH credential or agent authorization failure. |
| Jenkins node is offline or has the wrong executor/label state | Jenkins node readiness failure. |
| A `patchset-created` event is received but no build runs | Gerrit Trigger job mapping or Jenkins scheduling failure. |
| The build runs on the wrong label | Jenkins agent scheduling failure. |
| REST review API rejects the `Verified +1` vote | REST vote, label, or voting permission failure. |
| Gerrit review state does not show the expected vote | Gerrit review-state verification failure. |

Failed `Verified` voting must not be collapsed into SSH, stream-events, or job
scheduling failures. Legacy SSH review command use must be recorded as an
explicit exception with the operator justification and compatibility evidence
that made it acceptable for that run.
