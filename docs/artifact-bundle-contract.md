# Artifact Bundle Contract

This document defines the artifact bundle contract for bundle-factory
workspaces, release archive layout, target transfer, target extraction,
helper-owned execution state, helper-visible artifact paths, and mode
parity. It is a contract and validation authority, not an operator command
manual.

## Workspaces

- Bundle-factory workspaces live under helper-owned state, currently
  `/var/lib/loopforge/artifact-bundle-work/<role>`.
- Bundle-factory workspaces produce the role's release-unit contents before
  packaging.
- Target transfer inboxes live under helper-owned target state, currently
  `/var/lib/loopforge/staging/<role>/incoming`.
- Helper-owned generated execution state on target environments lives under
  `/var/lib/loopforge/`.
- Helper-owned logs on target environments live under `/var/log/loopforge/`.

## Release Archives

- Gerrit release archive: `gerrit-artifacts-bundle.tar.gz`
- Jenkins controller release archive: `jenkins-artifacts-bundle.tar.gz`
- Jenkins agent release archive: `jenkins-agent-artifacts-bundle.tar.gz`
- Each archive must have a sibling `.sha256` file.
- Each archive must contain a top-level directory matching the bundle name.
- Each bundle must contain `checksums/SHA256SUMS` and a role payload directory.
- The archive pair is the handoff artifact; extracted trees are disposable
  staging or target state, not the source of truth.

## Target Extraction

- Gerrit extracted bundle root: `/opt/gerrit-artifacts-bundle`
- Jenkins controller extracted bundle root: `/opt/jenkins-artifacts-bundle`
- Jenkins agent extracted bundle root: `/opt/jenkins-agent-artifacts-bundle`
- Helper-visible payload directories:
  - `/opt/gerrit-artifacts-bundle/gerrit`
  - `/opt/jenkins-artifacts-bundle/jenkins`
  - `/opt/jenkins-agent-artifacts-bundle/jenkins-agent`

## Helper Contract

- `prepare-artifacts` writes bundle contents in the bundle-factory workspace.
- `stage-artifacts` verifies the archive checksum, extracts to the target
  extraction root, and verifies the bundle checksum files before service
  mutation.
- Role helpers consume the extracted payload directory only.
- Helper-owned generated state, runtime inputs, staging handoff, evidence
  inputs, and bounded logs use `/var/lib/loopforge/` and `/var/log/loopforge/`
  on target environments.
- Docker and VM simulation may back these paths with generated host
  directories, bind mounts, container copies, or VM transfer paths, but the
  helper-visible paths stay product-like and the lifecycle checks remain
  required.

## Mode Parity

- Docker and VM simulation must follow the same helper-visible artifact bundle
  paths and lifecycle checkpoints as target-deployment.
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

- Bundles contain application artifacts, config/templates, manifests,
  checksums, and package intent metadata where relevant.
- Bundles must not contain SSH private keys, public-key handoff files,
  `authorized_keys`, generated integration keys, passwords, tokens, or LDAP
  bind secrets.
- Bundles must not become offline Ubuntu dependency bundles or expose
  supported offline dependency bundle workflows.

## Evidence And Failure Semantics

- Passing evidence must show mode, role, archive checksum verification,
  extracted bundle checksum verification, role payload checksum verification,
  source-boundary metadata, and bounded log references.
- Missing, stale, mismatched, or drifted manifests/checksums block comparable
  readiness instead of passing.
- Simulation evidence must be labeled as simulation and must not imply
  `target-deployment` acceptance.
