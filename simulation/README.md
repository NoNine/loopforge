# Simulation Model

This directory defines the shared simulation model for the v1 Gerrit/Jenkins
setup package. Layer-specific command ownership lives in the Docker and VM
README files; this file owns the common topology, baseline, source boundaries,
output conventions, and checkpoint meanings.

The model has two layers:

1. Docker-based simulation first, owned by
   `simulation/docker/simulate.sh`.
2. VM-based simulation second.

Both layers use the same five-machine topology:

| Machine/environment | Docker form | VM form | Responsibility |
| --- | --- | --- | --- |
| Bundle factory | Container | VM | Runs role helper `prepare-artifacts` commands and produces curated application artifacts, plugins, manifests, and checksums. |
| LDAP | Container | VM | Hosts LDAP bind, admin, and test accounts and groups. |
| Gerrit | Container | VM | Runs Gerrit with LDAP authentication, SSH access, integration permissions, and the `Verified` label. |
| Jenkins controller | Container | VM | Runs Jenkins, LDAP/JCasC configuration, Gerrit Trigger, and agent registration. |
| Jenkins agent | Container | VM | Runs SSH build jobs scheduled by Jenkins. |

The simulation model derives account usage from `docs/account-model.md`. It
does not introduce a separate account taxonomy. The `ci-operator` account is
a local OS account on simulation machines only; it is not a Gerrit or Jenkins
product account.

## Version Baseline

Version baseline inputs for both simulation layers:

- Ubuntu 24.04.4 LTS, release `24.04`, codename `noble`
- OpenJDK 21 for Gerrit, Jenkins controller, and Jenkins agent
- Gerrit `3.13.6`
- Jenkins controller `2.555.3 LTS`
- Jenkins Plugin Installation Manager Tool `2.15.0`
- Jenkins agent OpenJDK 21 plus SSH server/client tooling and the Jenkins SSH
  Build Agents plugin from the controller plugin bundle

Future verifiers must fail or report blocked rather than claim comparable
readiness when the Ubuntu, Java, Gerrit, Jenkins controller, plugin-manager,
or Jenkins agent/plugin-bundle versions differ from this baseline.

## Source Boundaries

Ubuntu/OS dependencies and application artifacts are separate supply lanes.
Target hosts may use approved internal Ubuntu/OS package repositories for OS
dependencies. Application artifacts are prepared only in the bundle factory,
then staged to Gerrit, Jenkins controller, and Jenkins agent target/service
environments and verified by manifest and checksum before mutation.

Public internet fallback for target-host Ubuntu/OS dependency installation is
simulation-only and must be labeled `simulation-only` in docs, logs, and
verification summaries. Target hosts must not download Gerrit/Jenkins
application artifacts from the public internet as fallback. In v1, offline
Ubuntu dependency bundle workflows are not supported.

## Output Locations

Generated runtime output is not committed. Docker and VM steps write generated
state, staged artifacts, evidence, and bounded logs under layer- and
run-scoped paths so separate runs do not collide.

Use these canonical roots and subpath patterns:

| Output kind | Canonical root | Run-scoped pattern |
| --- | --- | --- |
| State | `simulation/state/` | `simulation/state/<layer>/<run-id>/` |
| Staged artifacts | `simulation/staging/` | `simulation/staging/<layer>/<run-id>/<environment>/` |
| Evidence | `simulation/evidence/` | `simulation/evidence/<layer>/<run-id>/` |
| Bounded logs | `logs/` | `logs/<layer>/<run-id>/` |

`<layer>` is `docker` or `vm`. `<run-id>` is a unique run identifier, such as
a UTC timestamp plus a short label. `<environment>` is one of
`bundle-factory`, `ldap`, `gerrit`, `jenkins-controller`, or
`jenkins-agent`.

These paths are generated runtime output unless a file in the tree states
otherwise. Keep them ignored or documented as generated when created by
simulation steps.

## Checkpoint Contract

Each simulation layer maps these checkpoints to its own commands. The
checkpoint meaning stays the same across layers.

| Checkpoint | Purpose | What it does | Output/evidence | Pass or block condition |
| --- | --- | --- | --- | --- |
| Preflight | Answer whether this environment can run the tools. | Checks required local tools, command surfaces, run naming, and version/source-boundary constraints before service mutation. Docker preflight may bootstrap from the operator env file, but it does not render runtime inputs. Terminal output is a short summary line. | Preflight evidence and bounded logs. | Pass only when prerequisites and baseline constraints are ready; fail or block on missing tools, invalid names, missing helpers, or baseline drift. |
| Input rendering | Answer what exact operator-selected config this run will use. | Loads the selected env file, applies defaults, resolves run-scoped paths and ports, records redacted env values, and writes layer-specific rendered env files. Docker rendering also persists run identity for later lifecycle commands. Terminal output is a short summary; Docker `status` prints live browser URLs from running containers. | Rendered env files and render evidence. | Pass when selected input files exist, rendered inputs are complete, and secrets are redacted; fail on invalid or unavailable configured values. |
| Artifact preparation | Produce application artifacts in the bundle factory. | Runs role helper `prepare-artifacts` commands in the bundle factory and creates role artifacts, manifests, checksums, and source-boundary labels. | Bundle factory artifact directories, `manifest.txt`, `checksums.sha256`, and preparation evidence. | Pass only when required artifacts, manifests, checksums, and simulation-only source labels exist; block comparable readiness on missing or drifted manifest metadata. |
| Artifact staging | Move prepared artifacts to targets before mutation. | Copies prepared artifacts to target/service environments and verifies manifest and checksum data on the target side. | Staged artifact directories, checksum verification logs, and staging evidence. | Pass only after target-side manifest/checksum verification succeeds; fail or block on missing artifacts, checksum mismatch, or manifest drift. |
| Service configuration | Start or configure role-local runtime environments. | Starts the simulation environments and runs role-local install/configuration paths needed before readiness checks. Terminal output uses short lifecycle summaries. | Service startup/configuration logs and evidence. | Pass when required environments are running/configured against the version baseline; fail on startup or configuration errors. |
| Readiness checks | Prove service readiness without claiming full trigger success. | Runs role-local readiness gates, then validates cross-role integration readiness such as SSH paths, stream-events, agent connection, and scheduling. Terminal output stays short and role-oriented. | Readiness evidence, integration evidence, and bounded logs. | Pass only on real runtime checks; fail on role-local errors and block when cross-role proof is not implemented or unavailable. |
| End-to-end execution | Prove the full Gerrit Trigger workflow. | Creates or uses a disposable verification change, proves Gerrit event receipt, Jenkins job scheduling, agent execution, and Gerrit `Verified +1`. Success prints a short final summary. | End-to-end verification evidence and bounded logs. | Pass only when the real workflow completes; block if readiness did not pass or trigger proof is unavailable. |
| Evidence audit | Summarize retained proof without rerunning the workflow. | Collects and reviews evidence, manifests, checksums, log references, redaction status, and source-boundary labels. | Audit summaries and evidence references. | Pass when evidence is complete, bounded, redacted, and traceable; fail or block on missing proof, unredacted secrets, or unsupported claims. |

Role helpers stay role-local in both layers. Cross-role SSH, trigger setup,
integration validation, trigger verification, and integration evidence use
`scripts/integration-setup.sh`. Scaffold-level integration commands must fail
closed until a real Docker or VM implementation exists.
