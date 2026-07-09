# Endpoint Identity

## Purpose And Authority

This document defines how Loopforge chooses hostnames, URLs, SSH host strings,
and LDAP endpoint identities across `docker-simulation`, `vm-simulation`, and
`target-deployment`.

`docs/system-model.md` owns the Standard Interfaces list. This document owns
which endpoint identity form should be used for those interfaces in each
deployment mode. Consumer docs should link here instead of repeating the full
policy.

## Recommended Rule

| Environment | Prefer | Use IP Only When |
| --- | --- | --- |
| Docker simulation | Docker service names inside containers; `127.0.0.1` with published ports from the host | Never use container IP addresses as stable endpoint identity. |
| VM simulation | Stable VM FQDNs published by the VM network DNS | DNS is unavailable and the VM IP address is static for the run. |
| Target deployment | Site-approved FQDNs or DNS names | Bootstrap, break-glass, or site policy requires reviewed static IP inventory. |

## Applied To Loopforge

| Value | Docker Simulation | VM Simulation | Target Deployment |
| --- | --- | --- | --- |
| `GERRIT_HOST` | `gerrit-target` for container/service access | VM FQDN such as `gerrit.example.test` | FQDN such as `gerrit.example.internal` |
| `GERRIT_CANONICAL_WEB_URL` | Host browser URL: `http://127.0.0.1:$HARNESS_GERRIT_HTTP_HOST_PORT/` | Browser-reachable VM URL, preferably hostname-based | Public or internal user-facing URL, preferably HTTPS FQDN |
| `JENKINS_HOST` | `jenkins-controller-target` for container/service access | VM FQDN such as `jenkins-controller.example.test` | FQDN such as `jenkins.example.internal` |
| `JENKINS_URL` | Internal default `http://jenkins-controller-target:8080/`; host browser status URL `http://127.0.0.1:$HARNESS_JENKINS_HTTP_HOST_PORT/login` | Browser-reachable VM URL, preferably hostname-based | Jenkins root URL matching reverse proxy and TLS configuration |
| `JENKINS_AGENT_HOST` | `jenkins-agent-target` for container/service access | VM FQDN such as `jenkins-agent.example.test` | FQDN or site inventory hostname for the agent |
| `LDAP_URL` | `ldap://ldap:389` | VM LDAP FQDN such as `ldap.example.test` | Enterprise LDAP FQDN, normally `ldaps://...` when site policy requires TLS |
| `INTEGRATION_*_TARGET_SSH_HOST` | `127.0.0.1` with the published Docker SSH port | VM FQDN preferred | FQDN preferred; reviewed static IP inventory is acceptable by site policy |
| `INTEGRATION_*_TARGET_SSH_KNOWN_HOSTS_FILE` | Entries match `127.0.0.1:published-port` SSH inventory | Entries match the selected VM SSH host strings | Entries match the selected deployment SSH host strings |

## Identity Invariants

- Do not use Docker container IP addresses in docs, examples, env defaults, or
  integration wiring.
- Do not copy Docker service names such as `gerrit-target`,
  `jenkins-controller-target`, `jenkins-agent-target`, or `ldap` into
  `target-deployment` inventory.
- VM inventory must not use Docker service names or Docker published loopback
  ports unless an explicit VM port-forwarding design is documented for that
  run.
- Use `127.0.0.1` only for Docker published host ports or an explicit VM port
  forward. It is not a cross-host target-deployment identity.
- Prefer stable FQDNs for VM simulation and target deployment.
- Raw IP addresses are allowed only as a reviewed static inventory fallback.
- `known_hosts` files must be generated and checked for the exact SSH host
  string and port recorded in reviewed inventory.
- Browser URLs must be the URLs users and integrations actually use, not
  incidental process bind addresses.

## Endpoint Classes

| Endpoint class | Variables | Guidance |
| --- | --- | --- |
| Browser URL | `GERRIT_CANONICAL_WEB_URL`, `JENKINS_URL` | Use the browser-visible URL. In production this normally means an HTTPS FQDN, even when the service listens internally on HTTP. |
| Service host | `GERRIT_HOST`, `JENKINS_HOST`, `JENKINS_AGENT_HOST` | Use the stable name reachable from the component that consumes the service endpoint. |
| Target OS SSH inventory | `INTEGRATION_*_TARGET_SSH_HOST`, `INTEGRATION_*_TARGET_SSH_PORT`, `INTEGRATION_*_TARGET_SSH_KNOWN_HOSTS_FILE` | Use the operator/control-plane SSH identity and ensure host-key material matches that exact identity. |
| Directory endpoint | `LDAP_URL` | Use the LDAP endpoint identity approved for the mode. Simulation-owned LDAP names must not be copied into target deployment. |

## Evidence Expectations

Evidence may record selected hostnames, browser URLs, SSH aliases, target SSH
ports, LDAP URL identifiers, API origins, and known-hosts file references when
they do not contain secrets. Evidence must distinguish browser-visible URLs
from internal service endpoints when they differ.

Evidence must not include private keys, passwords, LDAP bind secrets, tokens,
or secret-bearing URLs.

## Official Basis

Docker Compose provides service-name discovery inside a Compose network, while
published ports are reached from the host through the host binding such as
`127.0.0.1:<port>`. Docker container IP addresses are runtime-assigned and are
not stable Loopforge endpoint identities.

Gerrit and Jenkins both distinguish service internals from the URL users and
integrations should use. Gerrit exposes `gerrit.canonicalWebUrl`; Jenkins
reverse-proxy guidance requires the externally used URL and context path to
match the configured service URL. Loopforge therefore treats browser URLs as
reviewed endpoint identity.

OpenSSH host-key trust is tied to the host string or address used for the SSH
connection. Loopforge `known_hosts` files must match the SSH host strings and
ports recorded in reviewed inventory.

## References

- Docker Compose networking:
  https://docs.docker.com/compose/how-tos/networking/
- Docker networking:
  https://docs.docker.com/engine/network/
- Gerrit `gerrit.canonicalWebUrl`:
  https://gerrit-review.googlesource.com/Documentation/config-gerrit.html
- Jenkins reverse proxy configuration troubleshooting:
  https://www.jenkins.io/doc/book/system-administration/reverse-proxy-configuration-troubleshooting/
- OpenSSH `ssh_config`:
  https://man.openbsd.org/ssh_config
- OpenSSH `ssh-keyscan`:
  https://man.openbsd.org/ssh-keyscan.1
