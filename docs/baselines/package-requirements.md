# Package Requirements

This document is the consolidated Ubuntu 24.04 package-requirements reference.
It applies package requirements to the logical environments defined by
`docs/architecture/system-model.md`. The system model owns environment identity
and responsibility; `simulation/docs/shared/simulation-model.md` owns Docker
and VM realization details.

`docs/baselines/version-baseline.md` owns the default Ubuntu, Java, Gerrit,
Jenkins, plugin-manager, and Jenkins agent/tooling versions. This document owns
the package-layer rationale for that baseline.

Target-deployment environments install OS packages from approved internal
Ubuntu/OS repositories. Application artifacts are separate from OS packages
and are staged through reviewed artifact bundles. v1 does not support offline
Ubuntu dependency bundles. Public internet fallback for target-host OS package
installation is simulation-only.

## Package Ownership Rules

`common-operations` is the only reusable package set. All other packages are
owned directly by their logical environment. A package present in a shared
Docker image or VM base-image superset is not, by itself, a dependency of every
environment that uses that realization.

Helper-specific packages belong to the logical environment in which the helper
runs. `*_OS_DEPENDENCIES` identifies the narrower command subset validated by a
helper; it is not a reusable package set or the complete environment package
composition. Native procedures apply the complete target-deployment package
composition.

## Target-Deployment Requirements

### Control Node

```text
python3
openssh-client
```

These packages support the operator or machine runner's control-plane access.
They are not a Gerrit, Jenkins controller, or Jenkins agent service baseline.

### Gerrit Target

Every Gerrit target installs the shared
[`common-operations`](#common-operations) package set and the environment's
runtime package:

```text
openjdk-21-jre-headless
```

### Jenkins Controller Target

Every Jenkins controller target installs the shared
[`common-operations`](#common-operations) package set and the environment's
runtime packages:

```text
fontconfig
nfs-common
openjdk-21-jre
```

The controller mounts the Jenkins-agent-hosted shared storage export at
`JENKINS_SHARED_STORAGE_PATH`.

### Jenkins Agent Target

Every Jenkins agent target installs the shared
[`common-operations`](#common-operations) package set and the
environment-specific packages below.

#### Runtime Packages

```text
nfs-kernel-server
openjdk-21-jre-headless
openssh-server
```

`openssh-server` provides the inbound SSH endpoint used by the Jenkins
controller to launch agent sessions. `nfs-kernel-server` hosts the reviewed
shared Jenkins storage export. The Java runtime executes the Jenkins agent
process.

#### General Build Packages

```text
build-essential
cmake
debhelper
devscripts
dpkg-dev
fakeroot
g++-multilib
gcc-multilib
gdb
git
git-lfs
lintian
ninja-build
pkg-config
python3
python3-dev
python3-venv
shellcheck
```

These packages provide source checkout, native and multilib compilation,
CMake and Ninja builds, Python build environments, Debian package construction
and review, debugging, and shell validation.

The multilib packages make this exact environment specific to amd64 Jenkins
agents. A non-amd64 agent requires a separately reviewed package baseline;
installation must not silently omit unavailable packages.

Project-specific SDKs, language versions, and toolchains are outside the
general Jenkins agent requirement and must be added as separately reviewed
environment dependencies.

### Bundle Factory

```text
ca-certificates
openjdk-21-jre-headless
tar
unzip
wget
```

These packages prepare Gerrit, Jenkins controller, and Jenkins agent artifact
bundles. The bundle factory is logically separate from target-host installation
even when its infrastructure is co-located with another environment.

### LDAP Environment

Gerrit and the Jenkins controller require an approved LDAP environment that
provides the configured `LDAP_URL`, a read-only bind account, user and group
search bases, and network reachability from each target. The
`target-deployment` LDAP service is target-owned and outside Loopforge; this
document does not define an LDAP server package baseline for it.

The `common-operations` package set provides `ldap-utils` and its `ldapsearch`
command for the Gerrit and Jenkins controller bind and search proof. It is a
target-host validation prerequisite, not an application runtime dependency.
Endpoint identity and bind-account custody are owned by
`docs/contracts/endpoint-identity.md` and `docs/contracts/account-model.md`.

## Docker-Simulation Requirements

Docker simulation realizes the control node directly on the Docker host. The
bundle factory, Gerrit target, Jenkins controller target, and Jenkins agent
target use one shared Docker target image. That image is a simulation
implementation superset, not an additional target-deployment package baseline.
It adds `procps` and `sudo` for process inspection and the simulated operator
account. Its `tree` package is already part of `common-operations`.

### Control Node

```text
Docker Engine
Docker Compose
python3
openssh-client
tar
diffutils
coreutils
an awk implementation
```

These packages run the Docker harness and its local control plane. They are not
target-container packages.

### Gerrit Target

No Docker-specific package dependencies.

### Jenkins Controller Target

No Docker-specific package dependencies.

### Jenkins Agent Target

No Docker-specific package dependencies.

### Bundle Factory

No Docker-specific package dependencies.

### LDAP Environment

Uses `HARNESS_LDAP_IMAGE`; no target-deployment LDAP package baseline applies.

## VM-Simulation Requirements

VM simulation realizes the control node directly on the libvirt/KVM host. It
inherits the target-deployment package requirements for the Gerrit target,
Jenkins controller target, Jenkins agent target, and bundle factory. The
harness may bake their union into one VM-set-local base image as an
implementation optimization; package presence in that superset does not create
additional logical-environment dependencies.

Each VM still verifies its environment package and command expectations during
M4. Role helpers validate those expectations later; they do not install
Ubuntu/OS dependencies.

### Control Node

```text
python3
openssh-client
dnsutils
iproute2
libvirt-clients (virsh)
libvirt-daemon-system
qemu-system-x86
qemu-utils
virtinst
util-linux (flock)
coreutils
an awk implementation
cloud-image-utils or genisoimage
```

These packages provision and inspect simulation-owned VMs, configure host DNS
resolution, and generate seed media. The control-node requirement includes
`dnsutils` for host DNS checks, `iproute2` for libvirt bridge inspection,
`libvirt-clients` (`virsh`), and either `cloud-image-utils` or `genisoimage`.
These are not guest target packages.

### Gerrit Target

No VM-specific package dependencies.

### Jenkins Controller Target

No VM-specific package dependencies.

### Jenkins Agent Target

No VM-specific package dependencies.

### Bundle Factory

No VM-specific package dependencies.

### LDAP Environment

```text
ca-certificates
ldap-utils
slapd
```

`slapd` and `ldap-utils` support the simulation-owned LDAP service and readiness
proof.

VM simulation realizes role target OS dependency baselines during VM
provisioning before the clean baseline snapshot. Each environment remains
responsible only for its target-deployment requirements and the explicit
simulation-specific additions declared here.

## Shared Package Requirements

### Common Operations

Install this package set on every target-deployment Gerrit, Jenkins controller,
and Jenkins agent target:

```text
ca-certificates
curl
fd-find
jq
ldap-utils
openssh-client
ripgrep
rsync
strace
tar
tree
unzip
vim
wget
xz-utils
```

This set provides TLS, HTTP/API, LDAP proof, SSH, transfer, archive, directory
proof, search, editing, and bounded system-call inspection tools. Ubuntu
installs the `fd-find` executable as `fdfind`; the baseline does not create an
additional `fd` alias. `vim` is the selected baseline editor, so `nano` is not
also installed.

## Requirement Consumers

| Requirement scope | Applied by |
| --- | --- |
| Target environments | Native procedures and role helpers |
| Docker simulation | Docker harness and target image |
| VM simulation | VM harness, host tools, and guest provisioning |

## Scope Boundaries

- Keep the Jenkins agent build packages off Gerrit and Jenkins controller
  targets.
- Keep project-specific SDKs and toolchains outside the Jenkins agent package
  requirement. Add them as separately reviewed environment dependencies.
- Do not treat `sudo` as a target-deployment dependency. It is an operator
  privilege mechanism and, in Docker, supports the example `ci-operator`.
- Do not treat `ldap-utils` as a Gerrit or Jenkins runtime dependency. It is a
  target-host operator/helper validation prerequisite.
- Do not treat bundle-factory packages as target-host service dependencies.
- Do not use artifact bundles as offline Ubuntu package bundles.
