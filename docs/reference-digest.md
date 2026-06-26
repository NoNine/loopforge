# Gerrit/Jenkins Draft Reference Digest

## Purpose

This digest summarizes behavior proven in the draft repository at
`/home/ubuntu/ai-assisted/gerrit-jenkins`.

Do not copy code, docs, templates, scripts, config files, command bodies, or
verbatim implementation from the draft repository. Use this digest only for
behavior, workflow order, validation expectations, integration intent, and
known failure boundaries.

Implementation agents for this repository should use this digest, `docs/prd.md`,
and the implementation plans in this repository. They should not open or copy
from the draft repository unless a human explicitly approves a new reference
review.

## Authority Notes

`docs/prd.md` and `docs/implementation-plan.md` govern v1 boundaries and
intended topology. When draft repository materials are stale or conflict with
the v1 plan, this digest follows the v1 plan.

For Docker simulation, stale draft lab docs may describe fewer runtime
containers. v1 uses the five-environment model from the implementation plan:
bundle factory, LDAP, Gerrit, Jenkins controller, and Jenkins agent.

## V1 Adaptation Rules

- v1 is not a strict air-gapped installer.
- v1 does not support offline Ubuntu dependency bundles.
- Public internet fallback on target hosts is simulation-only and must be
  labeled `simulation-only` in docs, logs, and evidence summaries.
- Artifact preparation remains separate from target-host installation.
- The bundle factory is an environment that runs role helper
  `prepare-artifacts` commands; it is not a public helper API.
- Helper commands must match manual phases closely enough to be repeatable
  accelerators for reviewed env files.
- Runtime, human admin, integration, test, bind, and simulation operator
  accounts must remain separate.

## Proven Workflow

The draft proves a full Gerrit/Jenkins flow with LDAP, Gerrit Trigger, SSH
agent scheduling, and a `Verified +1` review vote. v1 keeps the flow but
renames and narrows the artifact model so dependency-bundle behavior does not
become a supported product surface.

| Phase | Environment | Intent | Inputs | Outputs | Side effects | Validation |
| --- | --- | --- | --- | --- | --- | --- |
| Inputs | Operator workstation | Create reviewed role env files and remove placeholder values. | Env examples, hostnames, ports, LDAP values, account names, URL choices. | Role env files for Gerrit, Jenkins controller, and Jenkins agent. | Local env-file creation only. | Required values are present and browser-visible simulation URLs are confirmed. |
| Artifact preparation | Bundle factory | Prepare curated application artifacts, plugin inputs, manifests, and checksums. | Reviewed role env files, version selections, plugin source locations or allowed download sources. | Role artifact directories, release manifests, checksum files, and archives when packaging is needed. | Downloads or copies artifacts; any public internet use in simulation is labeled `simulation-only`. | Manifests exist and checksums verify before staging. |
| Artifact staging | Bundle factory and target hosts | Move prepared role artifacts to the hosts that will install them. | Prepared role artifact outputs and target staging paths. | Staged artifacts on Gerrit, Jenkins controller, and Jenkins agent hosts. | Copies files to target hosts but does not install services. | Target-side checksum verification passes before mutation. |
| Gerrit readiness | Gerrit host | Install, configure, start, and validate Gerrit with LDAP and integration prerequisites. | Gerrit env, staged Gerrit artifacts, LDAP bind values, runtime account values. | Gerrit service config, secure LDAP config, plugin placement, readiness evidence. | Creates or updates runtime paths, service config, plugins, and service state. | HTTP, SSH, LDAP, plugin readiness, and integration account readiness checks pass. |
| Jenkins controller readiness | Jenkins controller | Install, configure, start, and validate Jenkins with LDAP, JCasC, plugins, and controller-only readiness. | Jenkins env, staged controller artifacts, LDAP bind values, admin group values. | Jenkins service config, JCasC material, plugin state, readiness evidence. | Creates or updates Jenkins home, service settings, plugin state, and service state. | HTTP, LDAP, plugins, JCasC, and controller runtime checks pass before cross-role SSH, Gerrit Trigger, scheduling, or vote proof. |
| Gerrit integration | Jenkins controller and Gerrit host | Give Jenkins a Gerrit integration account that can stream events and vote. | Jenkins-generated public key, Gerrit admin credentials, Gerrit account/group values. | Gerrit integration account key registration, global `Verified` label in reviewed `All-Projects` config, project/ref access grants, Jenkins Gerrit Trigger server config, and REST vote posting config. | Creates or updates Gerrit permissions, label config, Jenkins credentials, and trigger server config. | SSH auth, stream-events permission, global label existence, scoped vote permission, trigger connection, REST vote posting, and Gerrit review state are validated separately. |
| Agent integration | Jenkins controller and Jenkins agent | Let Jenkins connect to an SSH build agent and schedule work on a label. | Jenkins-generated agent public key, agent host/user/node-name/labels/remote FS values. | Agent authorized key, runtime filesystem, Jenkins node, smoke job evidence. | Creates or updates agent SSH access, runtime directories, Jenkins credentials, node config, and validation job state. | Jenkins connects to the named node and runs a smoke job on the selected scheduling label. |
| End-to-end acceptance | Jenkins controller and Gerrit | Prove that a Gerrit change triggers Jenkins and receives `Verified +1`. | Disposable project, branch, uploader identity, Jenkins job, trigger server config. | Gerrit change, Jenkins build, Gerrit review vote, evidence summary. | Creates disposable verification project/job/change and vote artifacts. | Event streaming, job scheduling, agent execution, and vote posting all pass. |
| Evidence | All role environments | Preserve reviewable proof without leaking secrets or streaming verbose logs. | Validation outputs, manifests, checksums, sanitized config inputs, bounded logs. | Mode-labeled summaries with checksums, fingerprints, endpoints, and bounded log references. | Writes evidence summaries only. | Evidence identifies simulation vs target-deployment mode and redacts secrets. |

## Account And Credential Model

Use `account` for concrete roles. Use `identity` only when discussing
LDAP-backed identity integration.

| Account | Source | Purpose |
| --- | --- | --- |
| Gerrit runtime account | Local OS by default | Runs the Gerrit daemon only. |
| Jenkins runtime account | Local OS by default | Runs the Jenkins controller only. |
| Jenkins agent runtime account | Local OS by default | Owns SSH build-agent sessions and workspace paths only. |
| Gerrit admin account | LDAP-backed human account or group | Administers Gerrit and can configure integration permissions. |
| Jenkins admin account | LDAP-backed human account or group | Administers Jenkins and can apply JCasC/trigger/node configuration. |
| Jenkins Gerrit integration account | Gerrit service-style account | Lets Jenkins authenticate to Gerrit, stream events, and vote `Verified`. |
| Test user account | LDAP-backed human-style test account | Verifies login and disposable change workflow. |
| LDAP bind account | LDAP service account | Lets Gerrit and Jenkins search configured user and group bases read-only. |
| `ci-operator` account | Simulation OS account | Runs orchestration, SSH access, helper commands, and evidence collection in simulation. |

Credential custody rules:

- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.
- Jenkins agent consumes only the Jenkins-to-agent public key.
- Evidence may include public key paths, fingerprints, credential IDs, and
  account names.
- Evidence must redact private keys, passwords, tokens, LDAP bind secrets, and
  full secret-bearing env values.

## Helper Behavior Digest

The command names below describe v1 intent. They are not copied from the draft
command dispatch, and unsupported offline dependency bundle commands are
intentionally omitted.

Every command surface uses one owning script plus a subcommand:

- Role helpers use `scripts/<role>-setup.sh <command>`.
- Cross-role integration uses `scripts/integration-setup.sh <command>`.
- Docker simulation uses `simulation/docker/simulate.sh <command>`.
- VM simulation uses `simulation/vm/vm-verify.sh <command>`.

Do not add standalone role phase scripts such as `scripts/preflight.sh`, Docker
phase scripts such as `simulation/docker/check.sh`, or VM phase scripts such as
`simulation/vm/check.sh`.

### Gerrit Helper

`scripts/gerrit-setup.sh` should support:

| Command | Behavior intent |
| --- | --- |
| `print-env-template` | Emit a reviewed env template with placeholders for host, port, runtime account, LDAP, artifact, admin, and integration public-key values. |
| `preflight` | Check required commands, disk space, host resolution, LDAP reachability, runtime account/group readiness, and env completeness without mutating services. |
| `prepare-artifacts` | Prepare version-pinned Gerrit application artifacts, plugin inputs, release manifests, and checksums from approved sources. |
| `install` | Verify staged artifacts and install Gerrit runtime inputs after confirmation or `--yes`. |
| `configure` | Render Gerrit service and LDAP configuration from reviewed env values, separating secret config from non-secret config. |
| `validate` | Check role-local service startup, HTTP reachability, SSH reachability, LDAP readiness, and plugin readiness. |
| `collect-evidence` | Emit sanitized Gerrit readiness evidence with manifests, checksums, fingerprints, endpoints, mode labels, and bounded log references. |

Gerrit behavior notes:

- Gerrit should use OpenJDK 21-compatible runtime assumptions.
- Gerrit exposes HTTP and SSH on reviewed internal ports.
- LDAP configuration requires a bind DN with search access to configured user
  and group bases.
- The `Verified` label and vote permission must exist before Jenkins can post
  successful verification results.
- Failed voting must be distinguishable from failed SSH authentication, failed
  event streaming, and failed Jenkins job scheduling.

### Jenkins Controller Helper

`scripts/jenkins-controller-setup.sh` should support:

| Command | Behavior intent |
| --- | --- |
| `print-env-template` | Emit a reviewed env template for Jenkins URL, runtime account, admin group, LDAP, Gerrit connection, artifacts, keys, agent, and verification values. |
| `preflight` | Check required commands, disk space, host resolution, LDAP reachability, Gerrit HTTP/SSH reachability, runtime account readiness, and env completeness. |
| `prepare-artifacts` | Prepare version-pinned Jenkins controller artifacts, plugin artifacts, manifests, checksums, and plugin review inputs. |
| `install` | Verify staged artifacts and install Jenkins controller runtime inputs after confirmation or `--yes`. |
| `configure-service` | Configure Jenkins runtime service settings, Jenkins home, and startup environment. |
| `install-plugins` | Install curated plugins from prepared artifacts and record plugin evidence. |
| `configure-jcasc` | Configure LDAP security realm, admin authorization, controller executor policy, and baseline Jenkins settings from reviewed env values. |
| `validate` | Check Jenkins startup, endpoint response, plugin/JCasC readiness, LDAP assumptions, and controller runtime readiness only. |
| `collect-evidence` | Emit sanitized role-local Jenkins evidence with plugin state, JCasC fingerprints, controller runtime checks, mode labels, and bounded log references. |

Jenkins controller behavior notes:

- Jenkins should use the LTS/controller version selected by reviewed inputs.
- Jenkins uses LDAP-backed human admin users or groups; it should not use
  runtime or integration accounts as human admin accounts.
- The built-in node should be kept at zero executors for target-deployment
  validation.
- Gerrit Trigger should connect as the Jenkins Gerrit integration account.
- The Jenkins agent node name is identity and lookup metadata. Scheduling uses
  the configured label set, selecting `gerrit-ci` when present and otherwise
  the first label.
- Trigger verification should run on the selected agent scheduling label except
  for explicitly labeled simulation-only checks.

### Jenkins Agent Helper

`scripts/jenkins-agent-setup.sh` should support:

| Command | Behavior intent |
| --- | --- |
| `print-env-template` | Emit a reviewed env template for agent host, SSH port, runtime user, remote filesystem, node name, labels, and artifact paths. |
| `preflight` | Check required commands, disk space, host resolution, SSH readiness assumptions, runtime account values, and env completeness. |
| `prepare-artifacts` | Prepare agent bootstrap artifacts, package intent manifests, and checksums without exposing an offline dependency bundle workflow. |
| `install` | Verify staged artifacts and install the agent host baseline after confirmation or `--yes`. |
| `configure-runtime` | Create or update the agent runtime filesystem and real SSH daemon readiness without installing controller-owned key material. |
| `validate` | Check SSH daemon reachability, runtime account ownership, remote filesystem readiness, and staged artifact checks. |
| `collect-evidence` | Emit sanitized agent evidence with SSH status, filesystem ownership, mode labels, and bounded log references. |

Agent behavior notes:

- Jenkins connects out to the agent over SSH.
- The agent helper owns only the agent host side.
- Jenkins-to-agent public-key authorization, Jenkins node registration, and
  controller-side scheduling validation belong to the shared integration
  helper.

### Shared Integration Helper

`docs/integration-setup-manual.md` is the operator command manual for the
shared helper. It runs after the three role manuals are complete.

`scripts/integration-setup.sh` should support:

| Command | Behavior intent |
| --- | --- |
| `configure-integration` | Configure durable cross-role integration state: Jenkins-to-Gerrit SSH, Jenkins-to-agent SSH, Gerrit integration access, the global `Verified` label, scoped vote permissions, Jenkins credentials, Jenkins node config, shared storage, and the Gerrit Trigger server. |
| `validate-integration` | After `--yes`, passively validate cross-role readiness and required configuration without creating disposable proof state. `--dry-run` must not create Gerrit or Jenkins state. |
| `prove-integration` | After `--yes` and a successful validation marker, run active proof: shared storage, Gerrit SSH and stream-events, agent connection, disposable Jenkins job execution, REST `Verified +1`, and Gerrit review state. |
| `collect-evidence` | Emit sanitized integration evidence with fingerprints, credential IDs, accounts, endpoints, REST vote results, Gerrit review state, bounded logs, and redaction status. |

The helper may fail closed until Docker or VM integration exists. The reviewed
Gerrit ACL REST workflow is part of the shared integration manual. The shared
integration helper should use SSH as the common target OS/control-plane
interface for Docker simulation, VM simulation, and target deployment; Docker
APIs belong to Docker simulation lifecycle tooling, not to the helper's target
communication surface. Role helpers must not expose cross-role commands.
Legacy SSH review commands or flags are exception-only and require operator
justification plus compatibility evidence.

### Docker Simulation Helpers

Docker simulation should expose:

| Command | Behavior intent |
| --- | --- |
| `simulation/docker/simulate.sh preflight` | Check local Docker/Compose tooling, static harness files, script wiring, and baseline labels while bootstrapping from the harness env file. |
| `simulation/docker/simulate.sh init-run` | Initialize simulation configs from the bootstrap env file and browser-visible URLs, copy selected inputs into run-scoped runtime inputs, and write the generated-run marker under `generated/simulation/docker/<run-id>/`. |
| `simulation/docker/simulate.sh prepare-artifacts` | Run role helper `prepare-artifacts` commands in the bundle factory container, retain manifests/checksums/source labels, and export successful bundle archives plus checksums to host-owned `exported-artifacts/`. |
| `simulation/docker/simulate.sh stage-artifacts` | Stage prepared bundle archives from host-owned handoff files to Gerrit, Jenkins controller, and Jenkins agent containers, then verify target-side manifests and checksums under the role-specific `/opt` bundle roots. |
| `simulation/docker/simulate.sh up` | Start the five-environment simulation after artifacts/configs exist, using the bootstrap env file to locate the run-scoped runtime config. |
| `simulation/docker/simulate.sh configure-role` | Run role-local install and configuration for one or all roles without rerunning artifact phases. |
| `simulation/docker/simulate.sh validate-role` | Run role-local validation and evidence collection for one or all roles without rerunning configuration. |
| `simulation/docker/simulate.sh configure-integration` | Expose Docker targets through the standard SSH/service interfaces, then invoke the shared integration helper for durable cross-role configuration. |
| `simulation/docker/simulate.sh validate-integration` | Invoke passive shared integration validation and write the validation marker. |
| `simulation/docker/simulate.sh prove-integration` | Require the validation marker, then invoke active shared integration proof without rerunning validation. |
| `simulation/docker/simulate.sh down` | Stop the simulation without deleting retained generated output. |
| `simulation/docker/simulate.sh clean` | Manually remove mutable generated runtime data under the validated repo-local generated run root while preserving exported artifacts, evidence, and logs. |

Docker simulation behavior notes:

- The five environments are bundle factory, LDAP, Gerrit, Jenkins controller,
  and Jenkins agent.
- Docker is the first integration gate.
- The bundle factory container runs role helper `prepare-artifacts` commands; it
  is not a separate public helper API.
- Staged artifacts must be manifest/checksum verified on service containers
  before service mutation.
- Readiness checks should report LDAP, local OS runtime accounts, Gerrit
  HTTP/SSH, Jenkins HTTP/LDAP/JCasC/plugins, Jenkins-to-Gerrit SSH,
  stream-events, and agent readiness separately.
- Docker-local state should be generated or ignored, not committed as runtime
  output.
- Docker v1 generated output is fixed under
  `generated/simulation/docker/<run-id>/`; lifecycle and cleanup commands do
  not support arbitrary output roots.
- Docker generated-state lifecycle, stale-container recovery, and fresh-run
  rules are defined in `docs/docker-simulation-state-lifecycle.md`.
- `clean` is separate from `down` because Docker bind mounts may leave
  container-owned host data, while evidence, logs, and exported artifacts must
  remain reviewable.
- Docker logs should be written to log files and referenced by bounded
  summaries rather than streamed as verbose output.
- Any public internet fallback during artifact preparation must be labeled
  `simulation-only`.

### VM Simulation Helpers

VM simulation should expose:

| Command | Behavior intent |
| --- | --- |
| `simulation/vm/vm-verify.sh create` | Create or identify clean VM environments when explicitly approved. |
| `simulation/vm/vm-verify.sh bootstrap` | Prepare role env values and prerequisite state before service configuration. |
| `simulation/vm/vm-verify.sh prepare-artifacts` | Run role helper artifact preparation on the bundle factory VM and retain manifests, checksums, and simulation-only source labels. |
| `simulation/vm/vm-verify.sh stage-artifacts` | Transfer prepared artifacts from the bundle factory VM to service VMs and verify target-side manifests and checksums. |
| `simulation/vm/vm-verify.sh configure` | Configure LDAP, Gerrit, Jenkins controller, and Jenkins agent according to the reviewed flow. |
| `simulation/vm/vm-verify.sh check` | Validate host tooling, env values, SSH reachability, target addresses, service state, local OS runtime accounts, LDAP, endpoints, Gerrit/Jenkins integration, and agent readiness. |
| `simulation/vm/vm-verify.sh execute` | Run role helpers and the shared integration helper in order. |
| `simulation/vm/vm-verify.sh audit` | Collect retained evidence, checksums, summaries, and bounded log references. |
| `simulation/vm/vm-verify.sh full` | Run the approved end-to-end VM verification sequence. |

VM simulation behavior notes:

- VM verification repeats Docker-proven behavior in a systemd-oriented,
  target-deployment environment.
- VM verification uses separate bundle factory, LDAP, Gerrit, Jenkins
  controller, and Jenkins agent VMs.
- VM artifact preparation runs on the bundle factory VM, and staged artifacts
  must be manifest/checksum verified on Gerrit, Jenkins controller, and Jenkins
  agent VMs before service mutation.
- VM commands that mutate host, VM, or remote state require explicit operator
  approval and must describe expected side effects.
- VM evidence should be labeled as VM simulation or target-deployment
  validation, depending on the run.

## Gerrit Trigger Integration Behavior

The known working integration sequence is:

1. Gerrit is running with LDAP-backed authentication.
2. Gerrit has a Jenkins integration account or group intended for automation.
3. Jenkins controller generates the Jenkins-to-Gerrit SSH keypair.
4. Gerrit receives only the public key.
5. Gerrit defines global `Verified` in reviewed `All-Projects` config,
   grants project/ref read and `label-Verified -1..+1`, and grants
   `stream-events` as a global capability to the integration account or group.
6. Jenkins stores the controller-held private key as a credential.
7. Jenkins configures a Gerrit Trigger server using the integration account.
8. Jenkins registers a verification job that responds to `patchset-created`.
9. A disposable Gerrit change triggers Jenkins.
10. Jenkins runs the job on the selected SSH agent scheduling label.
11. Jenkins posts `Verified +1` back to the Gerrit change through the Gerrit
    REST review API and verifies Gerrit review state.

Failure classification:

- If Jenkins cannot authenticate to Gerrit over SSH, report an SSH credential
  or account setup failure.
- If SSH works but event streaming fails, report a stream-events permission or
  trigger-server connectivity failure.
- If the event is received but no build runs, report a Jenkins job or agent
  scheduling failure.
- If the build succeeds but Gerrit rejects the REST review vote, report a
  REST vote, `Verified` label, or voting permission failure.

## Validation And Evidence Expectations

Evidence must be useful for audit review without requiring repo history or
verbose runtime logs.

Evidence should include:

- Verification mode, such as Docker simulation, VM simulation, or
  target-deployment validation.
- Timestamp and helper/package version or git commit.
- Hostnames, ports, and service endpoint URLs.
- Sanitized config input manifest.
- Artifact manifests and checksum references.
- Public key fingerprints and credential IDs where relevant.
- Service startup and endpoint check results.
- LDAP bind/search check result.
- Gerrit SSH and stream-events check result.
- Jenkins plugin/JCasC readiness result.
- Jenkins agent online and scheduling result.
- Gerrit Trigger event, build, REST vote, and Gerrit review state result.
- Bounded log paths and short failure snippets.

Evidence must not include:

- Private keys.
- Passwords.
- Tokens.
- LDAP bind secrets.
- Full secret-bearing env files.
- Verbose Docker, Jenkins, Gerrit, package-manager, SSH, VM, or verification
  logs in normal command output.

## Explicit Non-Carry-Forward Items

Do not carry these draft concepts into v1 as supported behavior:

- Strict air-gapped installer claims.
- Offline Ubuntu dependency bundle support.
- Helper commands for supported offline dependency bundle workflows.
- Command names such as `prepare-offline-deps-bundle`,
  `install-offline-deps`, or role-specific equivalents.
- Public internet fallback on target hosts outside simulation-only labeling.
- A bundle-factory helper as a public API.
- Reuse of runtime accounts as human admin accounts.
- Jenkins builds on the controller for target-deployment validation.
- Evidence that exposes secrets or depends on unbounded runtime logs.

## Document Map

- `docs/gerrit-setup-manual.md` covers Gerrit role-local setup.
- `docs/jenkins-controller-setup-manual.md` covers Jenkins controller
  role-local setup.
- `docs/jenkins-agent-setup-manual.md` covers Jenkins agent host role-local
  setup.
- `docs/integration-setup-manual.md` covers the shared cross-role helper
  command workflow after the three role manuals complete.
- `docs/gerrit-trigger-integration.md` covers the Gerrit Trigger policy and
  validation contract.

## Maintained Native Operation References

The current repository keeps three native-operation references as strong
references for direct OS and application operations:

| Native reference | Maintained with |
| --- | --- |
| `docs/gerrit-native-operations-reference.md` | `docs/gerrit-setup-manual.md` and Step 7 behavior. |
| `docs/jenkins-controller-native-operations-reference.md` | `docs/jenkins-controller-setup-manual.md` and Step 8 behavior. |
| `docs/jenkins-agent-native-operations-reference.md` | `docs/jenkins-agent-setup-manual.md` and Step 9 behavior. |

These documents must not contain repository helper commands, helper-equivalent
tables, or `scripts/...` command references. When role manuals or helper
behavior changes native OS/application operations, update the corresponding
native reference in the same logical change.

## Source Traceability

These draft sources were consulted for behavior only. Copying from them is not
allowed for implementation in this repository.

| Draft source | Used for | Copy allowed? |
| --- | --- | --- |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/docs/gerrit-jenkins-identity-model.md` | Account roles, separation rationale, and LDAP/admin/integration terminology. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/docs/gerrit-install-air-gapped.md` | Gerrit phase order, host readiness checks, LDAP assumptions, integration readiness, and validation categories. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/docs/jenkins-install-air-gapped.md` | Jenkins controller phase order, LDAP/JCasC/plugin concepts, Gerrit Trigger behavior, and controller-side validation categories. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/docs/jenkins-agent-install-air-gapped.md` | SSH build-agent runtime expectations, public-key handoff, remote filesystem readiness, and scheduling validation split. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/docs/offline-bundle-verification.md` | Five-environment VM verification topology, clean-run expectations, audit outputs, and target-deployment verification intent. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/lab/README.md` | Docker integration gate, browser-visible URL handling, LDAP/Gerrit/Jenkins/agent checks, and proven trigger-vote outcome. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/gerrit-operator.sh` | Gerrit helper command intent, confirmation/dry-run concepts, manifest/checksum behavior, and integration validation categories. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/scripts/jenkins-operator.sh` | Jenkins helper command intent, key ownership, JCasC/plugin behavior, agent registration, trigger verification, and validation categories. | No |
| `/home/ubuntu/ai-assisted/gerrit-jenkins/vm/scripts/vm-verify.sh` | VM wrapper phase intent, approval-sensitive VM actions, logging/audit flow, and preflight/full verification split. | No |
