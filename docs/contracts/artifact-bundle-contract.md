# Artifact Bundle Contract

This document defines the artifact bundle contract for bundle-factory
workspaces, release archive layout, target transfer, target extraction,
helper-owned execution state, helper-visible artifact paths, and mode
parity. It is a contract and validation authority, not an operator command
manual. `docs/contracts/directory-model.md` defines target-visible directory
ownership, permissions, sensitivity, and evidence behavior for these paths.
`simulation/docs/shared/generated-state-layout.md` defines host-side simulation
copies and backing state.

## Workspaces

- Bundle-factory workspaces live under the Loopforge helper state root,
  currently `/var/lib/loopforge/preparing/<bundle>/<payload>`.
- Bundle-factory workspaces produce the role's release-unit contents and
  archive pair.
- Target artifact staging lives under helper-owned target state, currently
  `/var/lib/loopforge/staging`.
- Helper-owned generated execution state and logs use the directory model's
  helper-owned path contract.

## Bundle-Factory Ubuntu Dependencies

The bundle factory prepares role artifacts for Gerrit, Jenkins controller, and
Jenkins agent. These packages support artifact download, checksum generation,
archive creation, and Java-based plugin tooling. They are shared bundle-factory
dependencies, not target-host service dependencies.

| Class | Packages |
| --- | --- |
| Bundle-factory dependencies | `ca-certificates`, `openjdk-21-jre-headless`, `tar`, `unzip`, `wget` |

See `docs/baselines/package-requirements.md` for the layered package model that separates
bundle-factory, target-host, helper-script, and simulation-only requirements.

## Release Archives

- Gerrit release archive: `gerrit-artifacts-bundle.tar.gz`
- Jenkins controller release archive: `jenkins-artifacts-bundle.tar.gz`
- Jenkins agent release archive: `jenkins-agent-artifacts-bundle.tar.gz`
- Each archive must have a sibling `.sha256` file.
- The archive pair and bundle tree live together in the preparing root, for
  example
  `/var/lib/loopforge/preparing/{gerrit-artifacts-bundle.tar.gz,gerrit-artifacts-bundle.tar.gz.sha256,gerrit-artifacts-bundle}`.
- Each archive extracts directly to one role payload directory: `gerrit/`,
  `jenkins/`, or `jenkins-agent/`.
- Each helper-generated payload must contain exactly one compact `manifest.txt`
  and one payload `checksums.sha256`.
- Each native operator-prepared payload must contain one payload
  `checksums.sha256`. The native operation reference defines its remaining
  contents; native payloads do not inherit helper manifest or template
  requirements.
- A native operation reference may include its own manifest or templates when
  its procedure uses them.
- The archive pair is the handoff artifact; extracted trees are disposable
  staging or target state, not the source of truth.

## Target Extraction

- Helper-visible payload directories:
  - `/var/lib/loopforge/staging/gerrit`
  - `/var/lib/loopforge/staging/jenkins`
  - `/var/lib/loopforge/staging/jenkins-agent`

## Helper Contract

- `prepare-artifacts` creates `/var/lib/loopforge/preparing` when practical,
  cleans and recreates its own role bundle tree below that root, and writes
  the release archive pair in the bundle-factory workspace.
- Role helpers own practical child directory creation. The environment or
  simulation harness only provides prerequisites the helper cannot reasonably
  provide itself, such as generated run roots, environment lifecycle, or
  explicit file transfer waivers. Simulation harnesses must not create
  helper-visible `/var/lib/loopforge` or `/var/log/loopforge` role-helper roots.
  See `docs/architecture/system-model.md` for the general helper-versus-harness boundary.
- LDAP bind passwords must not be written to artifact bundles, rendered helper
  env files, runtime env files, or harness-created secret files. Docker and VM
  simulation may use labeled simulation-owned fake LDAP bind passwords for
  their own LDAP services; target-deployment LDAP bind passwords remain
  execution-time secret inputs only. Product runtime config may persist
  required product settings after a role helper writes them.
- `stage-artifacts` verifies the archive checksum, extracts to the target
  staging root, and verifies the payload `checksums.sha256` before service
  mutation.
- Target extraction uses helper-owned staging under `/var/lib/loopforge`; the
  staging root is created by the role helper, and transfer utilities may copy
  archive pairs into that existing root only through a labeled transfer
  waiver. Extraction should preserve operator-account ownership, for example
  by extracting as the operator account without preserving archive owners.
- Role helpers consume the extracted payload directory only.
- Helper-owned generated state, staging handoff, evidence inputs, and bounded
  logs follow `docs/contracts/directory-model.md`. Full reviewed helper env files remain
  operator inputs and must not be embedded in bundles.
- Docker and VM simulation may back these paths with generated host
  directories, container copies, or VM transfer paths, but helper-visible
  paths stay product-like and the lifecycle checks remain required.
- Successful artifacts leave the bundle factory only through the layer's
  explicit artifact export or transfer step. Target environments consume
  archive pairs through a labeled transfer waiver, then extract and verify
  payloads inside helper-visible target staging before role helpers use them.

## Mode Parity

- Docker and VM simulation must follow the same helper-visible artifact bundle
  paths and product checkpoints as target-deployment.
- Generated host directories, bind mounts, container copies, or VM transfer
  paths may support the lifecycle, but they may not replace checksum
  verification or role helper ownership.
- `/workspace` is only the read-only package-source mount for helper scripts.

## Product Behavior Boundary

- Artifact preparation is bundle-factory work, not target-host installation.
- Artifact staging is a target-side checkpoint that verifies archive and
  bundle checksums before service mutation.
- Simulation may host or transport these steps with generated backing paths,
  but may not skip role helpers, pre-populate target payloads as success, or
  treat helper internals as product interfaces.

## Bundle Contents Boundary

- Helper-generated bundles contain application artifacts, config/templates,
  one compact artifact manifest, and one payload checksum file.
- Native operator-prepared bundles contain one payload checksum file and the
  contents defined by their native operation reference. They need not match a
  helper-generated payload when both procedures produce equivalent product
  state.
- Bundles must not contain SSH private keys, public-key handoff files,
  `authorized_keys`, generated integration keys, passwords, tokens, or LDAP
  bind secrets.
- Bundles must not become offline Ubuntu dependency bundles or expose
  supported offline dependency bundle workflows.

## Evidence And Failure Semantics

- Passing machine-generated evidence must show mode, role, archive checksum
  verification, payload checksum verification, source-boundary metadata where
  applicable, and bounded log references.
- Missing or mismatched checksums block readiness for both operator interfaces.
  Missing, stale, mismatched, or drifted manifests also block helper readiness,
  and block native readiness when a native operation reference requires one.
- Simulation evidence must be labeled as simulation and must not imply
  `target-deployment` acceptance.
