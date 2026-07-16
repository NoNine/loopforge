# Account Model

This v1 model keeps runtime, operator, human admin, integration, test, bind,
and simulation environment accounts separate. Use account names that match the
local naming standard for the deployment; the examples here describe roles,
not required literal names.

Use `identity` only when discussing LDAP-backed identity integration. Concrete
roles in this package are accounts.

## Product Accounts

| Account | Source | Purpose |
| --- | --- | --- |
| Gerrit runtime account | Local OS | Runs Gerrit only. |
| Jenkins runtime account | Local OS | Runs the Jenkins controller only. |
| Jenkins agent runtime account | Local OS | Runs SSH build-agent sessions only. |
| Jenkins shared integration group | Local OS group | Grants Jenkins controller and agent runtime accounts access to shared integration storage only. |
| Gerrit admin account | LDAP-backed human account or group | Administers Gerrit. |
| Jenkins admin account | LDAP-backed human account or group | Administers Jenkins. |
| Jenkins Gerrit integration account | Gerrit service account | Lets Jenkins authenticate to Gerrit, stream events, and vote `Verified`. |
| Test user account | LDAP-backed human-style test account | Verifies login and change workflow. |
| LDAP bind account | LDAP service account | Lets Gerrit and Jenkins search the directory read-only. |

## Operator Account

| Account | Source | Purpose |
| --- | --- | --- |
| Operator account | Local OS account on operator, bundle-factory, and target environments | Runs orchestration, SSH access, helper commands, delegated privileged operations, and evidence collection. |

The operator account is configurable through `LOOPFORGE_OPERATOR_ACCOUNT`.
The operator group is configurable through `LOOPFORGE_OPERATOR_GROUP`, which
defaults to the selected operator account. The default example account and
group are `ci-operator:ci-operator` for all modes.

`root` is strictly forbidden as a Loopforge account value or workflow
identity. Do not configure `root` as the operator account, a runtime account,
an application admin account, an integration account, an LDAP bind account, a
test account, or a direct SSH login identity for Loopforge operations. The
root superuser is an OS-reserved privilege boundary, not a package role.

The operator account is not a Gerrit or Jenkins runtime account, application
admin account, integration account, LDAP bind account, or test user account.
Target-environment operations should run as the operator account whenever
practical, including helper commands, staging, validation, and evidence
collection. Delegated privilege from the operator account is used only for
narrow OS operations that require it, and service runtime accounts remain
service owners rather than orchestration identities.

Root-owned system files may exist only where the host OS, package manager, or
service manager requires protected custody, for example a `root:root 0600`
systemd environment file. That ownership is an OS custody detail and does not
make root a Loopforge account, login identity, helper execution identity, or
runtime identity.

Simulation-specific realizations of the operator account, seeded LDAP accounts,
and fake test credentials are documented in `simulation/README.md`.

## Numeric Identity Policy

Account and group names are local deployment choices, but UID and GID values
are the durable filesystem identity. Ownership on local filesystems, NFS
exports, bind mounts, backups, and restored data follows numeric UID/GID
values, not friendly names. Before any target-owned durable path is created,
operators must define reviewed, stable, non-colliding numeric identities for
the local OS accounts and groups that can own that data.

The reviewed role env file supplies the runtime account name, primary group
name, UID, and GID before role setup begins. Role preflight validates those
values without mutation. A role's `install` phase creates its fully absent
runtime group and account immediately before creating the role product home,
or adopts a fully matching account/group/empty-home set for initial setup.
Partial state, numeric collisions, mismatches, and a non-empty home without the
exact input-bound completion record block and require explicit operator cleanup
or correction; helpers do not reconfigure existing identities or application
state.

This ownership applies only to the Gerrit, Jenkins controller, and Jenkins
agent runtime identities. The operator account must already exist so it can
run helpers with delegated privilege. The Jenkins shared integration group is
created or verified later by `scripts/integration-setup.sh`, and LDAP-backed
accounts remain owned by their directory or application administration flow.

The example target-local identity range is `61000-61999`. Use a site-reserved
range instead when local policy requires it, and verify that the chosen values
do not collide on every participating host and storage server.

| Role | Example name | Example UID | Example primary GID |
| --- | --- | --- | --- |
| Operator account | `ci-operator` | `61000` | `61000` |
| Gerrit runtime account | `gerrit` | `61010` | `61010` |
| Jenkins controller runtime account | `jenkins` | `61020` | `61020` |
| Jenkins agent runtime account | `jenkins-agent` | `61030` | `61030` |
| Jenkins shared integration group | `jenkins-share` | not applicable | `61040` |

The Jenkins controller runtime account and Jenkins agent runtime account must
not share a UID in the recommended v1 model. They remain separate OS
identities for ownership, audit, and least privilege. Cross-role shared
storage access is granted through the dedicated Jenkins shared integration
group, not by collapsing the controller and agent into the same UID. A site
that intentionally reuses these numeric identities must document that as a
site-specific exception outside the recommended model.

## Separation Rules

Runtime accounts are local OS accounts by default. They own service processes,
service files, and role-local runtime paths only. The Gerrit runtime account
runs Gerrit, the Jenkins runtime account runs the Jenkins controller, and the
Jenkins agent runtime account owns SSH build-agent sessions and workspace
paths. Runtime OS accounts are not application admin accounts.

Runtime accounts may have role-local primary groups. The Jenkins controller
role uses `JENKINS_RUNTIME_GROUP`, defaulting to `jenkins`. The Jenkins agent
role uses `JENKINS_AGENT_GROUP`, defaulting to `jenkins-agent`. These groups
own role-local files only; they are not the cross-role sharing mechanism.

Cross-role Jenkins controller and agent sharing uses a separate integration
group from `examples/integration.env.example`. That file is the source of
truth for the shared group name, shared group GID, and shared storage path,
normally `/data/jenkins-shared`. The Jenkins agent host owns the v1 NFS server
and exports that path. The Jenkins controller host mounts the agent export at
the same path, while the Jenkins agent host uses its local export directory
directly.

The shared GID is the cross-host contract for NFS-backed sharing and must
exist with the same numeric value on the Jenkins controller host and Jenkins
agent host. The exported directory must be owned by the Jenkins agent runtime
account and shared integration group with group write and setgid enabled,
normally mode `2775`. `scripts/integration-setup.sh` owns creating or
validating that group, adding the Jenkins controller runtime account and the
Jenkins agent runtime account to it, preparing or validating the agent-hosted
export and controller mount, setting group-writable shared storage
permissions, and recording read/write proof. Role-local helpers must not own
this shared group or shared storage setup.

The setgid bit keeps new children in the shared group on typical Linux
filesystems, but process umask can still remove group write bits. Use default
ACLs only when setgid plus reviewed umask policy is insufficient, and validate
ACL behavior consistently on the Jenkins agent NFS server and controller
client.

For NFS-backed storage, keep `root_squash` enabled unless an approved
site-specific storage policy says otherwise. With `root_squash`, client-side
privileged ownership changes may fail or map to anonymous IDs, so target
deployment ownership and mode for `/data/jenkins-shared` must be established
on the Jenkins agent host before or during shared integration and then
validated from both Jenkins hosts. Do not use `all_squash` as the v1 default;
if a site intentionally maps all client identities to anonymous IDs, document
explicit `anonuid` and `anongid` values and the resulting audit tradeoff.

Human admin accounts are LDAP-backed human accounts or LDAP-backed groups.
The Gerrit admin account administers Gerrit and can configure integration
permissions. The Jenkins admin account administers Jenkins and can apply
JCasC, trigger, credential, and node configuration. Keeping these accounts
separate from runtime accounts prevents service process ownership from also
granting application administration.

The Jenkins Gerrit integration account is a Gerrit service account. Jenkins
uses its SSH key to authenticate to Gerrit and stream events, and uses its
Gerrit-generated HTTP auth token to vote `Verified` through the REST review
API. It is separate from human admin accounts so automated voting and event
streaming can be permissioned, audited, and disabled without changing human
access. Credential rotation remains site-owned administration outside the
Loopforge v1 setup surface.

The test user account is an LDAP-backed human-style test account. It verifies
LDAP-backed login and the disposable Gerrit change workflow. It is separate
from admin and integration accounts so validation proves ordinary user access
without relying on elevated permissions or automation-only credentials.

The LDAP bind account is a read-only LDAP service account. Gerrit and Jenkins
use it to search the configured user and group bases. It is separate from
human admin, test, runtime, and integration accounts because its only purpose
is directory lookup, and it must not grant application administration,
runtime ownership, or Gerrit voting rights.

The operator account runs orchestration, SSH access, helper commands, and
evidence collection in all modes. It is never `root`. Keeping it separate makes
operator control-plane access distinct from product accounts and prevents
evidence collection access from being treated as Gerrit or Jenkins authority.
Simulation-specific operator behavior is documented in `simulation/README.md`.

## Credential Custody

- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.
- Jenkins agent consumes only the Jenkins-to-agent public key.
- Evidence may include public key paths, fingerprints, credential IDs, and
  account names.
- Evidence must redact private keys, passwords, tokens, LDAP bind secrets, and
  full secret-bearing environment values.
