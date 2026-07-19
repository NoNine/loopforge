# Version Baseline

## Purpose

This document owns the default v1 version baseline for Loopforge. Role
manuals, native operation references, simulations, helpers, verifiers, and
evidence summaries should reference this baseline instead of redefining the
full version set.

The baseline applies to Docker simulation, VM simulation scaffolds, target
deployment guidance, and future real VM verification unless a reviewed change
updates the baseline everywhere in one logical change.

## Default Baseline

| Component | Default |
| --- | --- |
| Ubuntu target baseline | Ubuntu 24.04.4 LTS, release `24.04`, codename `noble` |
| Java runtime | OpenJDK 21 for Gerrit, Jenkins controller, and Jenkins agent |
| Gerrit | `3.13.6` |
| Jenkins controller | `2.555.3 LTS` |
| Jenkins Plugin Installation Manager Tool | `2.15.0` |
| Jenkins agent | OpenJDK 21, OpenSSH server/client tooling, and the Jenkins SSH Build Agents plugin from the controller plugin bundle |

Gerrit `3.13.6` is the default conservative production rollout line. Gerrit
`3.14.0` is noted by reference material as a current/latest line, but it is
not the v1 default because `.0` releases require careful production testing.

## Jenkins Direct Plugin Baseline

The v1 Jenkins controller direct plugin intent is the following exact pinned
set. Transitive dependencies resolved by Plugin Installation Manager are not
part of this operator-owned direct intent.

```text
configuration-as-code:2100.vb_fd699d2a_09c
credentials:1506.v948b_b_b_7dec44
git:5.10.1
gerrit-trigger:3.1983.v57096fe9923c
ldap:807.809.vd3a_4e5e4ec98
matrix-auth:3.2.10
ssh-credentials:372.va_250881b_08cd
ssh-slaves:3.1097.v868116049892
workflow-aggregator:608.v67378e9d3db_1
job-dsl:3654.vdf58f53e2d15
timestamper:1.30
ws-cleanup:0.49
```

## Update Rules

A baseline change must update all affected docs, helpers, simulations,
verifiers, tests, examples, templates, and evidence expectations in one
logical change. Do not change a role manual, helper default, Docker harness,
VM scaffold, or evidence expectation independently from this document.

Producer records and verifier summaries must record the baseline values used
by the run. Docker and VM verification must fail or report blocked rather than
claim comparable verification when the environment does not match the reviewed
baseline for that run.
