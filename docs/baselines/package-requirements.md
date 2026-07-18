# Package Requirements

This document is the consolidated requirements reference for Ubuntu 24.04.
It has two parts: host prerequisites by mode, and layered package
requirements. A package can be required by the product runtime, by native
operator or helper validation, or only by Docker simulation.

`docs/baselines/version-baseline.md` owns the default Ubuntu, Java, Gerrit, Jenkins,
plugin-manager, and Jenkins agent/tooling versions. This document owns the
package layer rationale for that baseline.

Native target hosts install OS packages from approved internal Ubuntu/OS
repositories. Application artifacts are separate from OS packages and are
staged through reviewed artifact bundles. v1 does not support offline Ubuntu
dependency bundles. Public internet fallback for target-host OS package
installation is simulation-only.

## Host Prerequisites by Mode

| Mode | Minimum host prerequisites | Notes |
| --- | --- | --- |
| `docker-simulation` | Linux host, Python 3.9+, Docker Engine, Docker Compose, enough disk space for `generated/` and `logs/` | Runs the local harness and Docker simulation CLI. |
| `vm-simulation` | Linux host with libvirt/KVM access, Python 3.9+, `virsh`, `flock`, VM image or install tooling, cloud-init or seed media tooling, SSH client tools, and enough disk space for VM images, `generated/`, and `logs/` | Runs the VM simulation CLI and owns simulation VM provisioning. `flock` serializes selected VM-set base-image preparation. VM provisioning satisfies role target OS dependency baselines before the clean baseline snapshot. LDAP service packages such as `slapd`, proof tools such as `ldap-utils`, and NFS packages for shared Jenkins storage are guest VM dependencies, not control-node host prerequisites. |
| `target-deployment` | Linux operator host, Python 3.9+, SSH client tools, access to approved internal Ubuntu/OS package repositories, enough disk space for reviewed inputs, `generated/`, and `logs/` | Native operator host prerequisites; per-role package details stay in the role manuals and matrix below. |

## Package Matrix

| Context | Product/runtime packages | Operator/helper packages | Simulation-only packages | Notes |
| --- | --- | --- | --- | --- |
| Gerrit target | `openjdk-21-jre-headless` | `ca-certificates`, `curl`, `ldap-utils`, `openssh-client`, `rsync`, `tar` | Shared Docker image also carries `git`, `procps`, `unzip`, and `wget` for helper/runtime proof paths | Gerrit needs Java; `ldap-utils` supports native and helper bind/search proof without becoming a Gerrit runtime dependency. |
| Jenkins controller target | `fontconfig`, `nfs-common`, `openjdk-21-jre` | `ca-certificates`, `curl`, `ldap-utils`, `openssh-client`, `rsync`, `tar`, `wget`; helper artifact checks also use `unzip` | `sudo` through the operator account for Docker integration orchestration; default example `ci-operator` | Jenkins is staged as a reviewed application artifact; `ldap-utils` supports native and helper bind/search proof without becoming a Jenkins runtime dependency. The controller mounts the Jenkins-agent-hosted shared storage export at `JENKINS_SHARED_STORAGE_PATH`. |
| Jenkins agent target | `nfs-kernel-server`, `openjdk-21-jre-headless`, `openssh-server` | Native install uses `ca-certificates`, `curl`, `rsync`, `tar`, and `wget`; helper defaults also expect `git` and `unzip`; OpenSSH tooling provides `ssh-keygen` for helper-owned host key generation | `sudo` through the operator account for Docker integration orchestration; default example `ci-operator` | Agent runtime exposes inbound SSH for Jenkins controller access and hosts the NFS export for shared Jenkins storage. Workload-specific build tools are out of scope. |
| Bundle factory | None: not a target service runtime | `ca-certificates`, `openjdk-21-jre-headless`, `tar`, `unzip`, `wget` | Public internet use is simulation-only where explicitly labeled | Prepares Gerrit, Jenkins controller, and Jenkins agent artifact bundles. These are not target-host service dependencies. |
| Docker shared target image | Union of role product packages | Union of role operator/helper packages | `sudo`, `procps`, `tree`; `net-tools` and `netcat-openbsd` currently have no evidence-backed consumer | The shared Dockerfile is a simulation superset, not authority for native target-host baselines. |
| VM simulation host | None: not a product target runtime | `python3`, SSH client tools, checksum/archive tooling, and `flock` used by the harness | libvirt/KVM tooling such as `virsh`, image or install tooling, and cloud-init or seed media tooling | VM tooling provisions and inspects simulation-owned VMs; it is not a native target package baseline. NFS server/client packages for shared Jenkins storage are installed in the Jenkins agent and controller VMs, not on the VM control host. |
| VM LDAP guest | `slapd` for the simulation-owned LDAP service | `ldap-utils` for LDAP bind/search readiness and seed proof | Simulation-owned LDAP seed data and test credentials | Applies only to the LDAP VM in `vm-simulation`; native target deployment uses approved target-owned LDAP instead. |

## Layer Rules

| Layer | Meaning | Where it belongs |
| --- | --- | --- |
| Product/runtime | Packages required for the role service to run. | Native role install command and this document. |
| Operator/helper | Packages required because native operators or Loopforge helpers validate, stage, configure, or collect evidence. | Native install commands, helper defaults, env examples, setup manuals, and this document. |
| Simulation-only | Packages required only because Docker containers simulate target hosts and run harness orchestration. | Docker simulation guide and this document. |

VM simulation realizes role target OS dependency baselines during VM
provisioning before the clean baseline snapshot. The VM harness bakes one
VM-set-local base image that contains the VM package superset for the selected
source image, Ubuntu baseline, apt mirror, source-boundary label, VM disk size,
and package matrix. Each VM must still verify role package and command
expectations during M4. Role helpers validate those expectations later; they do not install Ubuntu/OS dependencies.

## Native Target Install Baselines

Native manuals keep the role-local install commands because operators need a
copyable sequence on the target host. Those commands are task instructions. This
document owns the layered rationale.

| Target role | Native install packages |
| --- | --- |
| Gerrit | `ca-certificates`, `curl`, `ldap-utils`, `openssh-client`, `openjdk-21-jre-headless`, `rsync`, `tar` |
| Jenkins controller | `ca-certificates`, `curl`, `fontconfig`, `ldap-utils`, `nfs-common`, `openjdk-21-jre`, `openssh-client`, `rsync`, `tar`, `wget` |
| Jenkins agent | `ca-certificates`, `curl`, `nfs-kernel-server`, `openjdk-21-jre-headless`, `openssh-server`, `rsync`, `tar`, `wget` |

## Evidence Map

| Requirement | Evidence |
| --- | --- |
| Gerrit native target baseline | `docs/operations/native/gerrit.md` keeps the role-local install command; `scripts/gerrit-setup.sh` validates the static `GERRIT_OS_DEPENDENCIES` baseline. |
| Jenkins controller native target baseline | `docs/operations/native/jenkins-controller.md` keeps the role-local install command; `scripts/jenkins-controller-setup.sh` validates `JENKINS_OS_DEPENDENCIES`. |
| Jenkins agent native target baseline | `docs/operations/native/jenkins-agent.md` keeps the role-local install command; `scripts/jenkins-agent-setup.sh` validates `JENKINS_AGENT_OS_DEPENDENCIES` and validates the target OS `sshd` endpoint used by Jenkins. |
| Integration native operations | `docs/operations/native/integration.md` keeps the manual cross-role SSH, Gerrit access, Jenkins node, trigger, vote, and evidence procedures. |
| Bundle-factory baseline | `docs/contracts/artifact-bundle-contract.md` records the shared package list used to prepare role artifact bundles. |
| Docker shared target image | `simulation/docker/target/Dockerfile` installs the shared superset used by Gerrit, Jenkins controller, and Jenkins agent target containers. |
| Docker `sudo` layer | `simulation/docker/target/Dockerfile` creates the default example `ci-operator` with passwordless sudo; `simulation/docs/docker/docker-simulation.md` documents the operator account; `scripts/integration-setup.sh` uses sudo for simulation orchestration. |
| Docker `procps` layer | `simulation/docker/simulate.sh`, Gerrit helper runtime checks, and Jenkins agent SSH readiness checks use process inspection inside slim containers. |
| Target-host `ldap-utils` layer | The Gerrit and Jenkins native procedures and role helpers use `ldapsearch` to prove bind/search readiness. |
| Docker `tree` layer | `simulation/docker/target/Dockerfile` installs `tree` for simulation-only directory inspection and debugging. |
| VM simulation host tooling | `simulation/docs/vm/vm-simulation.md` and the VM harness preflight must validate libvirt/KVM access, `virsh`, image or seed media tooling, and SSH client tools. |
| VM LDAP guest service | `simulation/docs/vm/vm-simulation.md` documents the real LDAP service and seeded directory contract; VM evidence proves service readiness, seeded entries, and bind/search behavior. |
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
  mechanism, and in Docker it supports the default example `ci-operator`
  orchestration account.
- Do not treat `ldap-utils` as a Gerrit or Jenkins runtime dependency. It is a
  target-host operator/helper validation prerequisite.
- Do not treat bundle-factory packages as target-host service dependencies.
- Do not use artifact bundles as offline Ubuntu package bundles.
