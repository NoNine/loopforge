# Package Requirements

This document is the consolidated requirements reference for Ubuntu 24.04.
It has two parts: host prerequisites by mode, and layered package
requirements. A package can be required by the product runtime, by the
Loopforge helper scripts, or only by Docker simulation.

Native target hosts install OS packages from approved internal Ubuntu/OS
repositories. Application artifacts are separate from OS packages and are
staged through reviewed artifact bundles. v1 does not support offline Ubuntu
dependency bundles. Public internet fallback for target-host OS package
installation is simulation-only.

## Host Prerequisites by Mode

| Mode | Minimum host prerequisites | Notes |
| --- | --- | --- |
| `docker-simulation` | Linux host, Python 3.9+, Docker Engine, Docker Compose, enough disk space for `generated/` and `logs/` | Runs the local harness and Docker simulation CLI. |
| `vm-simulation` | Linux host with VM tooling available, Python 3.9+, SSH client access to the VM host, enough disk space for VM images, `generated/`, and `logs/` | Planned VM harness host prerequisites; keep VM-specific details in the VM simulation docs. |
| `target-deployment` | Linux operator host, Python 3.9+, SSH client tools, access to approved internal Ubuntu/OS package repositories, enough disk space for reviewed inputs, `generated/`, and `logs/` | Native operator host prerequisites; per-role package details stay in the role manuals and matrix below. |

## Package Matrix

| Context | Product/runtime packages | Helper-script packages | Simulation-only packages | Notes |
| --- | --- | --- | --- | --- |
| Gerrit target | `openjdk-21-jre-headless` | `ca-certificates`, `curl`, `openssh-client`, `rsync`, `tar` | Shared Docker image also carries `git`, `ldap-utils`, `procps`, `unzip`, and `wget` for helper/runtime proof paths | Native Gerrit service needs Java. Docker validation also proves LDAP and Gerrit runtime behavior. |
| Jenkins controller target | `fontconfig`, `openjdk-21-jre` | `ca-certificates`, `curl`, `openssh-client`, `rsync`, `tar`, `wget`; helper artifact checks also use `unzip` | `sudo` through `ci-operator` for Docker integration orchestration | Jenkins `.deb` is staged as an application artifact, not installed from an apt repository setup path. |
| Jenkins agent target | `openjdk-21-jre-headless`, `openssh-server` | Native install uses `ca-certificates`, `curl`, `rsync`, `tar`, and `wget`; helper defaults also expect `git` and `unzip`; OpenSSH tooling provides `ssh-keygen` for helper-owned host key generation | `sudo` through `ci-operator` for Docker integration orchestration | Agent runtime exposes inbound SSH for Jenkins controller access. Workload-specific build tools are out of scope. |
| Bundle factory | None: not a target service runtime | `ca-certificates`, `openjdk-21-jre-headless`, `tar`, `unzip`, `wget` | Public internet use is simulation-only where explicitly labeled | Prepares Gerrit, Jenkins controller, and Jenkins agent artifact bundles. These are not target-host service dependencies. |
| Docker shared target image | Union of role product packages | Union of role helper packages | `sudo`, `procps`, `ldap-utils`; `net-tools` and `netcat-openbsd` currently have no evidence-backed consumer | The shared Dockerfile is a simulation superset, not authority for native target-host baselines. |

## Layer Rules

| Layer | Meaning | Where it belongs |
| --- | --- | --- |
| Product/runtime | Packages required for the role service to run. | Native role install command and this document. |
| Helper-script | Packages required because Loopforge helper scripts validate, stage, configure, or collect evidence. | Helper defaults, env examples, setup manuals, and this document. |
| Simulation-only | Packages required only because Docker containers simulate target hosts and run harness orchestration. | Docker README and this document. |

## Native Target Install Baselines

Native manuals keep the role-local install commands because operators need a
copyable sequence on the target host. Those commands are task instructions. This
document owns the layered rationale.

| Target role | Native install packages |
| --- | --- |
| Gerrit | `ca-certificates`, `curl`, `openssh-client`, `openjdk-21-jre-headless`, `rsync`, `tar` |
| Jenkins controller | `ca-certificates`, `curl`, `fontconfig`, `openjdk-21-jre`, `openssh-client`, `rsync`, `tar`, `wget` |
| Jenkins agent | `ca-certificates`, `curl`, `openjdk-21-jre-headless`, `openssh-server`, `rsync`, `tar`, `wget` |

## Evidence Map

| Requirement | Evidence |
| --- | --- |
| Gerrit native target baseline | `docs/gerrit-native-operations-reference.md` keeps the role-local install command; `scripts/gerrit-setup.sh` validates the static `GERRIT_OS_DEPENDENCIES` baseline. |
| Jenkins controller native target baseline | `docs/jenkins-controller-native-operations-reference.md` keeps the role-local install command; `scripts/jenkins-controller-setup.sh` validates `JENKINS_OS_DEPENDENCIES`. |
| Jenkins agent native target baseline | `docs/jenkins-agent-native-operations-reference.md` keeps the role-local install command; `scripts/jenkins-agent-setup.sh` validates `JENKINS_AGENT_OS_DEPENDENCIES` and starts helper-owned `sshd`. |
| Bundle-factory baseline | `docs/artifact-bundle-contract.md` records the shared package list used to prepare role artifact bundles. |
| Docker shared target image | `simulation/docker/target/Dockerfile` installs the shared superset used by Gerrit, Jenkins controller, and Jenkins agent target containers. |
| Docker `sudo` layer | `simulation/docker/target/Dockerfile` creates `ci-operator` with passwordless sudo; `simulation/docker/README.md` documents the account; `scripts/integration-setup.sh` uses sudo for simulation orchestration. |
| Docker `procps` layer | `simulation/docker/simulate.sh` and Gerrit helper runtime checks use `ps` to inspect service processes inside slim containers. |
| Docker `ldap-utils` layer | `scripts/gerrit-setup.sh` requires `ldapsearch` to prove LDAP bind/search readiness. |
| Docker removal candidates | No current helper, harness, or role consumer was found for `net-tools` or `netcat-openbsd`. |

## Docker Removal Candidates

| Package | Current status | Action |
| --- | --- | --- |
| `net-tools` | No current helper, harness, or role consumer found. | Candidate for Dockerfile removal. |
| `netcat-openbsd` | No current helper, harness, or role consumer found. | Candidate for Dockerfile removal. |

## Scope Boundaries

- Do not add workload-specific build tools, such as compilers, to the default
  Jenkins agent baseline unless every general agent requires them.
- Do not treat `sudo` as a native role dependency. It is an operator privilege
  mechanism, and in Docker it supports `ci-operator` orchestration.
- Do not treat bundle-factory packages as target-host service dependencies.
- Do not use artifact bundles as offline Ubuntu package bundles.
