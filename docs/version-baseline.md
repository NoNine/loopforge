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

## Update Rules

A baseline change must update all affected docs, helpers, simulations,
verifiers, tests, examples, templates, and evidence expectations in one
logical change. Do not change a role manual, helper default, Docker harness,
VM scaffold, or evidence expectation independently from this document.

Evidence records and verifier summaries must record the baseline values used
by the run. Docker and VM verification must fail or report blocked rather than
claim comparable verification when the environment does not match the reviewed
baseline for that run.
