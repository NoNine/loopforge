# Integration Native Operations Reference

This document is the manual target-deployment native operations reference for
shared Gerrit/Jenkins integration. It uses OS, Gerrit, Jenkins, SSH, and
application-native operations only, not repository automation commands.

Repository v1 boundary: v1 is not a strict air-gapped installer and does not
support installing OS dependencies from locally bundled Ubuntu packages. Target
hosts use approved internal Ubuntu/OS package repositories for OS dependencies.
Public internet fallback on target hosts is simulation-only and must be labeled
as such in docs, logs, and verification summaries.

Audience: production operators integrating already-ready Gerrit, Jenkins
controller, and Jenkins SSH build-agent hosts on Ubuntu 24.04 LTS without
Docker.

Run this manual only after all three role-local native references have passed
role readiness:

- `gerrit-native-operations-reference.md`
- `jenkins-controller-native-operations-reference.md`
- `jenkins-agent-native-operations-reference.md`

Privilege warning: shared integration cannot be completed by an unprivileged
user alone. Gerrit account/key administration, reviewed Gerrit config changes,
Jenkins credential and node configuration, agent `authorized_keys` updates, and
service validation require delegated administrator privilege from the operator
account or application administrator credentials. Root may own OS-reserved
files, but root is not a Loopforge account, helper execution identity, runtime
identity, or supported direct login identity.

Manual authority: this manual is the reference procedure for manual shared
integration operations. It intentionally contains only native OS, Gerrit,
Jenkins, and OpenSSH operations. Do not add repository automation commands or
automation-equivalent command tables to this document.

## 1. Operator Inputs And Readiness

Record these values before shared integration:

| Item | Value |
| --- | --- |
| Gerrit URL | `GERRIT_CANONICAL_WEB_URL` |
| Gerrit SSH endpoint | `GERRIT_HOST:GERRIT_SSH_PORT`, normally `29418` |
| Jenkins URL | `JENKINS_URL` |
| Jenkins controller host | `JENKINS_HOST` |
| Jenkins agent SSH endpoint | `JENKINS_AGENT_HOST:JENKINS_AGENT_SSH_PORT` |
| Jenkins agent runtime account | `JENKINS_AGENT_ACCOUNT`, normally `jenkins-agent` |
| Jenkins node name | `JENKINS_AGENT_NODE_NAME` |
| Jenkins scheduling labels | `JENKINS_AGENT_LABELS` |
| Gerrit integration account | `jenkins-gerrit` or reviewed site value |
| Gerrit integration group | reviewed site value |
| Gerrit integration auth token ID | `jenkins-trigger` or reviewed site value |
| Gerrit project/ref scope | reviewed project and ref pattern |
| Jenkins Gerrit credential ID | reviewed Jenkins credential ID |
| Jenkins agent credential ID | reviewed Jenkins credential ID |

Prerequisites:

- Gerrit role-local readiness evidence shows HTTP, SSH, LDAP, runtime account,
  staged artifacts, and plugin readiness.
- Jenkins controller role-local readiness evidence shows controller startup,
  plugin readiness, LDAP/JCasC readiness, zero built-in executors, and endpoint
  readiness.
- Jenkins agent role-local readiness evidence shows OpenSSH reachability,
  runtime account ownership, remote filesystem ownership, and host-side
  readiness.
- The operator has Gerrit administrator access sufficient to create reviewable
  `All-Projects` and project config changes.
- The Gerrit administrator account is already provisioned in Gerrit. If the
  account comes from LDAP, sign in once through Gerrit before using REST
  administration; an LDAP directory entry alone is not a Gerrit account.
- The test user account is already provisioned in Gerrit. If the account comes
  from LDAP, sign in once through Gerrit before using it for disposable change
  creation during proof.
- The operator has Jenkins administrator access sufficient to create credentials,
  configure Gerrit Trigger, register SSH nodes, and create disposable validation
  jobs.

Credential custody:

- The Jenkins controller owns the Jenkins-to-Gerrit private key.
- Gerrit receives only the matching Jenkins-to-Gerrit public key.
- Gerrit issues a Gerrit HTTP auth token for the Jenkins Gerrit integration
  account. Record only the reviewed token ID, not the token value.
- The Jenkins controller owns the Jenkins-to-agent private key.
- The Jenkins agent receives only the matching Jenkins-to-agent public key.
- Evidence may record public-key fingerprints, credential IDs, account names,
  endpoints, change numbers, build URLs, and bounded log paths.
- Evidence must not contain private keys, passwords, tokens, LDAP bind secrets,
  or full secret-bearing env values.

## 2. Jenkins-To-Gerrit SSH

Create a Jenkins-to-Gerrit SSH keypair on the Jenkins controller under protected
Jenkins custody:

```bash
sudo -u jenkins install -d -m 0700 /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t ed25519 -N '' \
  -C jenkins-gerrit@loopforge \
  -f /var/lib/jenkins/.ssh/jenkins-gerrit
sudo -u jenkins ssh-keygen -lf /var/lib/jenkins/.ssh/jenkins-gerrit.pub
```

Register only `/var/lib/jenkins/.ssh/jenkins-gerrit.pub` with the reviewed
Gerrit integration account. Use the Gerrit UI or a reviewed Gerrit REST/API
operation that records the target account and public-key fingerprint. Do not
copy the private key to Gerrit, the operator workstation, the agent host, or any
artifact bundle.

Validate SSH authentication from the Jenkins controller to Gerrit:

```bash
sudo -u jenkins ssh -p GERRIT_SSH_PORT \
  -i /var/lib/jenkins/.ssh/jenkins-gerrit \
  jenkins-gerrit@GERRIT_HOST gerrit version
```

Expected result: Gerrit returns its version and the SSH server identifies the
authenticated integration account.

## 3. Gerrit Access And Verified Label

Target deployment uses reviewed Gerrit config changes. Do not directly edit
Gerrit bare repositories, mutate site Git state, or directly apply access and
label changes as a shortcut. Direct apply is simulation-only unless a future
reviewed production policy explicitly changes that boundary.

Create reviewable config changes for:

- Global `Verified` label definition in `All-Projects`.
- Global `stream-events` capability for the reviewed Jenkins integration group.
- Scoped project/ref read access for the reviewed Jenkins integration group.
- Scoped `label-Verified -1..+1` grant for the reviewed project/ref scope.

The reviewable change should leave these facts clear in its commit message or
review description:

- Target project and ref pattern.
- Jenkins integration account or group.
- Reason the `Verified` label is global.
- Reason vote permission is scoped to the reviewed project/ref pattern.
- Confirmation that direct apply is not used for target deployment.

After review submission, verify the effective access state through Gerrit UI,
REST, SSH inspection commands, or a site-approved access audit method. Do not
continue to Jenkins trigger validation until the global label, stream-events
capability, and scoped vote permission are effective.

## 4. Jenkins Gerrit Trigger Configuration

On the Jenkins controller, create a Jenkins SSH credential whose private key is
`/var/lib/jenkins/.ssh/jenkins-gerrit`. The credential ID must be the reviewed
Jenkins Gerrit credential ID and must not encode secret material.

In Gerrit, generate or rotate an HTTP auth token for the Gerrit integration
account using the reviewed token ID, normally `jenkins-trigger`. The token is
for Gerrit REST review posting by Gerrit Trigger. It is not an LDAP password,
and it is not used for `stream-events` SSH authentication.

If the Gerrit integration account does not exist yet, create it as a Gerrit
service account before generating the token. Do not create it as an LDAP user
or assign it an LDAP password for Loopforge integration.

Configure the Gerrit Trigger server in Jenkins with:

- Gerrit host and SSH port.
- Gerrit HTTP URL.
- Jenkins Gerrit integration account.
- Jenkins SSH credential ID for Gerrit.
- Gerrit HTTP username set to the Jenkins Gerrit integration account.
- Gerrit HTTP password/token set to the generated Gerrit auth token.
- Event stream enabled over Gerrit SSH.
- REST review API settings for posting `Verified` votes from the verification
  job result.

Validate that Jenkins can connect to Gerrit and establish an event stream. If
SSH authentication succeeds but event streaming fails, classify the failure as a
`stream-events` capability or Gerrit Trigger server connectivity failure, not as
a generic Jenkins failure.

## 5. Jenkins-To-Agent SSH

Create a Jenkins-to-agent SSH keypair on the Jenkins controller under protected
Jenkins custody:

```bash
sudo -u jenkins install -d -m 0700 /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t ed25519 -N '' \
  -C jenkins-agent@loopforge \
  -f /var/lib/jenkins/.ssh/jenkins-agent
sudo -u jenkins ssh-keygen -lf /var/lib/jenkins/.ssh/jenkins-agent.pub
```

Install only the public key on the Jenkins agent host:

```bash
sudo install -d -m 0700 -o jenkins-agent -g jenkins-agent /var/lib/jenkins-agent/.ssh
sudo install -m 0600 -o jenkins-agent -g jenkins-agent /dev/null /var/lib/jenkins-agent/.ssh/authorized_keys
sudo sh -c 'cat /path/to/reviewed/jenkins-agent.pub >> /var/lib/jenkins-agent/.ssh/authorized_keys'
sudo chown jenkins-agent:jenkins-agent /var/lib/jenkins-agent/.ssh/authorized_keys
sudo chmod 0600 /var/lib/jenkins-agent/.ssh/authorized_keys
```

Replace `/path/to/reviewed/jenkins-agent.pub` with the reviewed public-key file
transferred from the Jenkins controller. The transferred file must contain
exactly one OpenSSH public-key line. Reject private keys, PEM blocks, tokens,
passwords, or multi-key payloads.

Validate controller-to-agent SSH from the Jenkins controller:

```bash
sudo -u jenkins ssh -p JENKINS_AGENT_SSH_PORT \
  -i /var/lib/jenkins/.ssh/jenkins-agent \
  jenkins-agent@JENKINS_AGENT_HOST 'printf "%s\n" "$USER"'
```

Expected result: the remote command prints the reviewed Jenkins agent runtime
account.

## 6. Jenkins Agent Node Registration

On the Jenkins controller, create an SSH build-agent node with:

- Node name from `JENKINS_AGENT_NODE_NAME`.
- Remote root directory from `JENKINS_AGENT_REMOTE_FS`.
- Executors from the reviewed executor policy.
- Labels from `JENKINS_AGENT_LABELS`.
- Launch method: SSH.
- Host and port from the Jenkins agent host inventory.
- Credential ID for the Jenkins-to-agent private key.
- Host-key verification policy approved by the site.

Keep the controller built-in node at zero executors. Do not run product builds
on the controller.

Validate the node becomes online and Jenkins reports the expected labels and
executor count. If the node is offline or the label/executor state is wrong,
classify the failure as Jenkins node readiness failure.

## 7. End-To-End Proof

Create a disposable Gerrit change in the reviewed verification project/ref
scope. Use a disposable Jenkins job or reviewed existing validation job that:

- Is triggered by Gerrit Trigger on the disposable change event.
- Is restricted to the reviewed Jenkins agent scheduling label.
- Runs on the Jenkins agent, not the controller.
- Posts `Verified +1` through the Gerrit REST review API.

Acceptance checks:

- Jenkins-to-Gerrit SSH authentication succeeds as the integration account.
- Jenkins receives Gerrit events through `stream-events`.
- Jenkins schedules the job on the reviewed agent label.
- Jenkins-to-agent SSH authentication succeeds from the controller.
- The build runs on the expected agent node.
- Gerrit REST review API accepts the `Verified +1` vote.
- Gerrit review state shows the expected `Verified +1` on the disposable change
  and patch set.

REST vote posting does not replace the SSH event-stream proof. Both must pass.

## 8. Evidence And Failure Classification

Collect an integration evidence record with:

- Verification mode.
- Timestamp.
- Gerrit, Jenkins controller, and Jenkins agent endpoints.
- Reviewed project and ref scope.
- Jenkins node name, labels, and executor policy.
- Public-key fingerprints only.
- Jenkins credential IDs only when they do not encode secret material.
- Gerrit config review change numbers and URLs.
- Disposable Gerrit change and Jenkins build identifiers.
- Bounded log references.
- Redaction status.

Classify failures at the point where proof breaks:

| Failure point | Classification |
| --- | --- |
| Jenkins cannot authenticate to Gerrit over SSH | SSH credential or Gerrit integration account setup failure. |
| SSH works but event streaming fails | `stream-events` capability or Gerrit Trigger server connectivity failure. |
| Global `Verified` label is absent | `All-Projects` label definition failure. |
| Jenkins cannot vote `Verified -1..+1` on the reviewed ref scope | Project/ref access grant failure. |
| Jenkins cannot authenticate to the agent over SSH | Jenkins-to-agent SSH credential or agent authorization failure. |
| Jenkins node is offline or has wrong executor/label state | Jenkins node readiness failure. |
| A Gerrit event is received but no build runs | Gerrit Trigger job mapping or Jenkins scheduling failure. |
| The build runs on the wrong label | Jenkins agent scheduling failure. |
| REST review API rejects the `Verified +1` vote | REST vote, label, or voting permission failure. |
| Gerrit review state does not show the expected vote | Gerrit review-state verification failure. |

Failed `Verified` voting must not be collapsed into SSH, stream-events, or job
scheduling failures.

## 9. Recovery And Rotation

For Jenkins-to-Gerrit key rotation:

- Generate a new private key on the Jenkins controller.
- Register only the new public key with the Gerrit integration account.
- Update the Jenkins Gerrit credential.
- Validate Gerrit SSH and stream-events.
- Remove the old public key from Gerrit only after the new key is proven.

For Jenkins-to-agent key rotation:

- Generate a new private key on the Jenkins controller.
- Install only the new public key in the agent runtime account's
  `authorized_keys`.
- Update the Jenkins agent credential.
- Validate controller-to-agent SSH and node readiness.
- Remove the old public key only after the new key is proven.

For Gerrit access or `Verified` label recovery, create reviewed Gerrit config
changes and wait for approved submission before rerunning integration proof.
Do not use direct apply in target deployment.

## 10. References

- Gerrit native operations:
  `gerrit-native-operations-reference.md`
- Jenkins controller native operations:
  `jenkins-controller-native-operations-reference.md`
- Jenkins agent native operations:
  `jenkins-agent-native-operations-reference.md`
- Shared integration helper manual:
  `integration-setup-manual.md`
- Gerrit Trigger integration contract:
  `gerrit-trigger-integration.md`
