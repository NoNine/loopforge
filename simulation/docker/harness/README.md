# Shared Docker Harness

`simulation/docker/docker-harness.sh` provides the reusable Docker harness for
role-step readiness gates. It is not the full end-to-end Docker simulation.

The harness starts five environments:

| Environment | Container role |
| --- | --- |
| Bundle factory | Runs role helper `prepare-artifacts` commands and stores bundle outputs. |
| LDAP | Runs a real LDAP service with bind, admin, integration, and test data. |
| Gerrit target | Host-like Ubuntu target for Gerrit helper gates. |
| Jenkins controller target | Host-like Ubuntu target for controller helper gates. |
| Jenkins agent target | Host-like Ubuntu target for agent helper gates. |

The target containers are intentionally host-like Ubuntu containers. They are
not `gerritcodereview/gerrit`, `jenkins/jenkins`, or prebuilt service images
with embedded application artifacts.

## Generated Output

The harness writes generated local output to ignored paths:

| Output kind | Path pattern |
| --- | --- |
| State | `simulation/state/docker/harness/<run-id>/` |
| Staged artifacts | `simulation/staging/docker/harness/<run-id>/<role>/` |
| Evidence | `simulation/evidence/docker/harness/<run-id>/` |
| Bounded logs | `logs/docker/harness/<run-id>/` |

Generated state, staged artifacts, evidence, and bounded logs are runtime
output. Do not commit them.

## Source Boundaries

The bundle factory is an environment, not a public API. The harness does not
add `bundle-factory-helper.sh`; it runs the role helpers'
`prepare-artifacts` commands inside the bundle factory container.

Application artifacts are prepared only in the bundle factory, then staged to
target containers and verified by manifest and checksum before any
install/configuration command can run. Public internet fallback on target hosts
is simulation-only and applies only to Ubuntu/OS dependency installation; it is
not support for target-host application artifact downloads.

## Artifact Manifest Contract

Role helper `prepare-artifacts` outputs must include
`manifest.txt` and `checksums.sha256` under the role artifact directory. The
harness validates `manifest.txt` as exact `key=value` lines before staging and
again before role readiness can pass.

Required common fields:

```text
harness_manifest_version=1
role=<gerrit|jenkins-controller|jenkins-agent>
ubuntu_release=24.04
ubuntu_codename=noble
java_version=21
```

Required role-specific fields:

```text
# Gerrit
gerrit_version=3.13.6
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable

# Jenkins controller
gerrit_version=not-applicable
jenkins_version=2.555.3
jenkins_plugin_manager_version=2.15.0

# Jenkins agent
gerrit_version=not-applicable
jenkins_version=not-applicable
jenkins_plugin_manager_version=not-applicable
```

Missing or drifted baseline metadata blocks staging and role readiness. The
harness must not report comparable readiness from checksum success or helper
validation alone.
