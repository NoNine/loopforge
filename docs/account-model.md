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
| Operator account | Local OS account on operator, bundle-factory, and target environments | Runs orchestration, SSH access, helper commands, privileged operations, and evidence collection. |

The operator account is configurable through `LOOPFORGE_OPERATOR_ACCOUNT`.
The operator group is configurable through `LOOPFORGE_OPERATOR_GROUP`, which
defaults to the selected operator account. The default example account and
group are `ci-operator:ci-operator` for all modes.

The operator account is not a Gerrit or Jenkins runtime account, application
admin account, integration account, LDAP bind account, or test user account.
In Docker simulation, the target-local `ci-operator` OS account has
passwordless sudo for simulation orchestration and privileged helper
operations. Logging into a Docker target environment as `ci-operator` does
not mean the local host account running `simulate.sh` is named
`ci-operator`.

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
truth for the shared group name, shared group GID, and shared storage path.
`scripts/integration-setup.sh` owns creating or validating that group, adding
the Jenkins controller runtime account and the Jenkins agent runtime account
to it, setting group-writable shared storage permissions, and recording
read/write proof. Role-local helpers must not own this shared group or shared
storage setup.

Human admin accounts are LDAP-backed human accounts or LDAP-backed groups.
The Gerrit admin account administers Gerrit and can configure integration
permissions. The Jenkins admin account administers Jenkins and can apply
JCasC, trigger, credential, and node configuration. Keeping these accounts
separate from runtime accounts prevents service process ownership from also
granting application administration.

The Jenkins Gerrit integration account is a Gerrit service account. Jenkins
uses it to authenticate to Gerrit, stream events, and vote `Verified`. It is
separate from human admin accounts so automated voting and event streaming can
be permissioned, audited, rotated, and disabled without changing human access.

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
evidence collection in all modes. In Docker simulation, the default example
target-local `ci-operator` account has passwordless sudo for orchestration
and privileged helper operations. The Docker target `ci-operator` identity is
not mapped to the local host username, UID, or GID. Keeping it separate makes
operator control-plane access distinct from product accounts and prevents
evidence collection access from being treated as Gerrit or Jenkins authority.

## Credential Custody

- Jenkins controller owns the Jenkins-to-Gerrit private key.
- Jenkins controller owns the Jenkins-to-agent private key.
- Gerrit consumes only the Jenkins-to-Gerrit public key.
- Jenkins agent consumes only the Jenkins-to-agent public key.
- Evidence may include public key paths, fingerprints, credential IDs, and
  account names.
- Evidence must redact private keys, passwords, tokens, LDAP bind secrets, and
  full secret-bearing environment values.
