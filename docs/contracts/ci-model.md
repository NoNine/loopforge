# CI Model

## Purpose

This design note defines how Loopforge should model CI configuration that
lives outside this repository while still using the Loopforge simulation
environment to develop and validate that CI behavior.

Loopforge owns the Gerrit, Jenkins controller, Jenkins agent, integration,
validation, and evidence environment. Product CI configuration owns product
job definitions, seed-job logic, environment bindings, and generated Jenkins job
definitions. Application Gerrit repositories own their Jenkinsfiles and their
project-specific build, test, packaging, and release logic.

This document is a design model, not an implemented command manual. It records
the intended boundary for later implementation and validation work.

This document does not define a Loopforge CI catalog DSL, product CI schema,
CLI contract, required repository layout, or supported file format. Product CI
repositories may use Jenkinsfiles, Jenkins Job DSL, Jenkins Job Builder,
product-owned scripts, or another reviewed representation. Loopforge models
the ownership boundary and the CI behaviors the simulation should be able to
exercise.

## Ownership Model

Loopforge owns:

- Gerrit, Jenkins controller, and Jenkins agent setup.
- Jenkins-to-Gerrit and Jenkins-to-agent integration wiring.
- Gerrit Trigger, `Verified` voting proof, validation, and evidence.
- Simulation lifecycle, generated state handling, and simulation-only labels.

Each product CI configuration repository owns:

- Product job definitions or job-generation inputs.
- Product-owned target SoC and branch selection rules.
- Environment-specific bindings for simulation and product deployment.
- The product seed or reconciliation mechanics.
- Validation tests for its own CI configuration.

Each application Gerrit repository owns:

- Jenkins Pipeline as Code through app-owned Jenkinsfiles.
- Build, test, package, publish, and release commands.
- Product-specific source layout, toolchain use, and target behavior.

Jenkins UI remains available for inspection, manual runs, build history,
debugging, and manually created jobs. For generated jobs, the product CI
configuration repository is authoritative. Manual UI edits to generated jobs
are temporary and may be overwritten by the product seed job.

This generated-job ownership does not extend to Jenkins global configuration.
After Loopforge completes the one-time JCasC bootstrap handoff, Jenkins
persistent state is authoritative for LDAP, authorization, credentials, nodes,
and other global settings. A product seed or reconciliation operation must not
re-enable JCasC ownership or overwrite those settings.

## Model Versus Implementation

This model records ownership boundaries and desired behavior. A later
implementation may use different file names, configuration formats, generator
structure, or seed-job mechanics if it preserves those boundaries.

## Real-World Job DSL Practice

Jenkins Job DSL is commonly used as a reviewed job-generation layer rather
than as an application build language. Teams store Job DSL Groovy scripts in
source control, review them like other infrastructure code, and apply them
through a seed job or a Jenkins Configuration as Code `jobs:` bootstrap. The
Job DSL plugin then creates or updates Jenkins job XML inside Jenkins.

Real deployments usually keep these responsibilities separate:

- Job DSL defines Jenkins folders, job wrappers, triggers, parameters,
  scheduling labels, retention, views, SCM bindings, and generated-job
  descriptions.
- Application repositories own Jenkinsfiles or other pipeline entrypoints.
- Seed jobs reconcile Jenkins with the reviewed job-generation inputs.
- Jenkins UI edits to generated jobs are temporary and can be overwritten by
  the next seed run.

Mature Job DSL setups also treat drift and plugin compatibility as explicit
operational concerns. Seed jobs commonly fail when required plugins are
missing, mark deprecated DSL usage as unstable, and choose a reviewed policy
for removed generated jobs, such as disabling or deleting only jobs in the
seed-owned scope. Generated jobs should include a visible marker that names
the authoritative configuration repository and warns that manual edits may be
overwritten.

Job DSL is different from Jenkins Job Builder and from app-owned
Jenkinsfiles. Jenkins Job Builder is an external tool that renders job
definitions from YAML or JSON and uploads them through Jenkins APIs.
Jenkinsfiles are Pipeline as Code stored with the application repository and
usually contain the project build and test logic. Job DSL is useful when the
team wants Jenkins-native, reviewed job generation while still allowing
applications to own their pipeline behavior.

## Product CI Repository Shape

A product CI repository should be self-contained in v1. It may contain
Jenkinsfiles, Job DSL, Jenkins Job Builder files, product-owned scripts,
validation tests, environment binding inputs, or other reviewed CI
configuration. Introducing a shared platform generator repository is deferred
until repeated duplication creates a clear maintenance problem.

A product CI repository should make these responsibilities reviewable:

- Which app Gerrit repositories participate in CI.
- Which Jenkins jobs or job-generation rules are owned by the product.
- Which app-owned Jenkinsfile or pipeline entrypoint each generated job uses.
- Which branch patterns each job should react to.
- Which target SoCs a branch or job applies to.
- Which environment-specific service URLs, credential IDs, and agent labels
  are used in simulation or product deployment.
- How the product validates the CI configuration before applying it.

## Product CI Configuration Model

Loopforge does not classify branch intent. Branch names and branch meaning
belong to the product. Product CI configuration only needs to express which
branch patterns a job uses and, when cross-compilation matters, which target
SoCs those branch patterns imply.

Any chosen representation should be able to describe:

- App repositories and the jobs or pipelines that apply to them.
- Multi-repo app groups where one buildable product unit spans more than one
  Gerrit repository.
- Branch patterns selected by each job or pipeline.
- Target SoCs selected by branch, job, or release parameter.
- App-owned Jenkinsfiles or other pipeline entrypoints, including entrypoints
  owned by a main repository for a multi-repo app group.
- Gerrit-triggered verify jobs, scheduled jobs, and manual release jobs.
- Product-specific jobs that do not fit a shared naming convention.

Each app repository may have its own job or pipeline list. One repository may
have verify, nightly, and release jobs; another may have only verify; another
may have a product-specific job such as documentation publishing.

Any chosen representation should validate enough to prevent common mistakes:

- Unknown target SoCs.
- Generated job name collisions inside the product Jenkins folder.
- Branch selection that does not map to the intended target SoCs.
- Ambiguous branch pattern precedence when overlapping patterns are used.
- Missing branch or ref alignment rules for multi-repo app groups.
- Missing app-owned Jenkinsfiles or pipeline entrypoints.
- Secret-bearing configuration checked into the product CI repository.

Product CI repositories must not store passwords, tokens, private keys, LDAP
bind secrets, signing keys, or other secret values.

## Example Scenario

The following examples are explanatory scenarios, not a schema or required
file format.

One product might own these app repositories:

| App repository | Jobs | Target behavior |
| --- | --- | --- |
| `product-a/runtime` | `verify`, `nightly`, `release` | Cross-compiles for `soc-a` and `soc-b`. |
| `product-a/docs` | `publish` | No target SoC requirement. |

The corresponding app-owned entrypoints might be `Jenkinsfile.verify`,
`Jenkinsfile.nightly`, `Jenkinsfile.release`, and `Jenkinsfile.publish`.

The product CI configuration could express branch selection like this:

| Branch pattern | Target SoCs |
| --- | --- |
| `main` | `soc-a`, `soc-b` |
| `feature/*` | `soc-a`, `soc-b` |
| `soc-a-*` | `soc-a` |
| `soc-b-*` | `soc-b` |

Loopforge does not assign meaning to those branch names. The product decides
what `main`, `feature/*`, `soc-a-*`, and `soc-b-*` mean.

## Multi-Repo Applications

Some products are built from a set of repositories rather than from one
standalone app repository. In that shape, a satellite repository may not build
meaningfully by itself. A change in the satellite repository still needs CI,
but the build must use a coherent set of refs for the main repository and the
other dependent repositories.

Product CI configuration may model that as a multi-repo app group. The group
should identify the repositories that form the buildable unit, which
repositories can trigger CI, which repository owns the Jenkinsfile or pipeline
entrypoint, and how branches or refs are aligned across the group.

The repo-set mechanism is product-owned. A product may use AOSP `repo`
manifests, plain Git checkout lists, Git submodules, product-owned workspace
scripts, Jenkins shared libraries, package lockfiles, or another reviewed
representation. Loopforge does not require AOSP `repo`, a manifests
repository, or any specific multi-repo checkout tool.

For a satellite repository patchset, a typical verify flow is:

```text
triggering repo: product-a/driver at refs/changes/...
pipeline repo:   product-a/main at the matching branch
dependent repo:  product-a/lib at the matching branch or pinned ref
entrypoint:      product-a/main:Jenkinsfile.verify
```

The generated job should pass enough context for the pipeline entrypoint to
build the correct repo set. The Jenkinsfile or product-owned pipeline code
usually performs the detailed multi-repo checkout and build orchestration.
Products may put more checkout logic in generated jobs, but that is a product
choice rather than a Loopforge requirement.

When changes across multiple repositories depend on each other, product CI may
build a change group instead of a single patchset. Gerrit topics are one
common grouping mechanism. The product CI repository owns the policy for
selecting related changes, validating that the group is coherent, and applying
those changes to the repo set before running the pipeline.

## Generated Jobs

The standard generated job topology is flat inside the product Jenkins folder:

```text
/product-a/runtime-verify
/product-a/runtime-nightly
/product-a/runtime-release
```

The generator should not create target-specific jobs in v1. If operators need
exceptional target-specific or one-off jobs, they may create manual Jenkins UI
jobs with non-colliding names in the same product folder.

Seed-job authority is exact-name based:

- The seed job overwrites jobs generated from the current product CI
  configuration.
- The seed job ignores unknown jobs in the same product folder.
- The seed job does not delete unknown jobs in v1.
- Manual jobs must not use names generated by the product CI configuration.

Generated jobs should include a visible description marker such as:

```text
Managed by product-a-ci seed job. Source of truth is the product CI
configuration repository. Manual edits may be overwritten.
```

For the example scenario above, standard generated jobs could be:

| Generated job | Trigger | App entrypoint |
| --- | --- | --- |
| `/product-a/runtime-verify` | Gerrit patchset events | `Jenkinsfile.verify` |
| `/product-a/runtime-nightly` | Product-owned schedule | `Jenkinsfile.nightly` |
| `/product-a/runtime-release` | Manual run | `Jenkinsfile.release` |
| `/product-a/docs-publish` | Product-owned trigger or manual run | `Jenkinsfile.publish` |

`runtime-verify` uses the matched branch to select `soc-a`, `soc-b`, or both.
`runtime-nightly` uses product-owned branch and target selection.
`runtime-release` uses release parameters supplied by the operator.
`docs-publish` has no target SoC parameter.

## Pipeline Behavior

Generated jobs are Jenkins wrappers. The pipeline behavior lives in the
application repository Jenkinsfile or pipeline entrypoint selected by the
product CI configuration. For multi-repo app groups, that entrypoint may live
in a pipeline owner repository rather than in the repository whose Gerrit
change triggered the job.

Generated jobs must resolve the app-owned pipeline entrypoint from the
checked-out app repository ref or pipeline owner repository ref being built.
They must not embed product-specific build or test logic centrally. This lets
different branches, tags, or Gerrit patchsets carry different Jenkinsfile
content and still have the correct pipeline behavior for that ref.

For a Gerrit-triggered verify job, the generated job should:

- Listen for the configured Gerrit project and branch patterns.
- Check out the exact Gerrit patchset ref, submitted ref, or other matching
  app repository ref.
- Resolve the selected Jenkinsfile or pipeline entrypoint from that checkout
  or from the selected pipeline owner repository checkout so branch-specific
  or patchset-specific pipeline changes are honored.
- Pass build context to the Jenkinsfile, including the matched branch pattern
  and target SoC list derived from the product CI configuration. For
  multi-repo app groups, also pass the triggering repository, triggering ref,
  aligned branch or ref set, and any selected change group.
- Let the Jenkinsfile run product-specific build and test behavior.
- Report `Verified +1` or `Verified -1` through the Loopforge-supported
  Gerrit integration path.

For cron-triggered jobs, the generated job should use the product-owned
schedule and run the selected Jenkinsfile against the configured branch
patterns.

For manual release jobs, the generated job should not define a Gerrit
patchset trigger or cron trigger. It should require explicit parameters:

```text
TARGET_SOC
RELEASE_REF
RELEASE_REF_TYPE
```

`TARGET_SOC` must be one of the repository targets. `RELEASE_REF_TYPE` must be
`branch` or `tag`. `RELEASE_REF` is the user-selected branch or tag to build.
The release job should check out that selected branch or tag, then resolve the
release Jenkinsfile or pipeline entrypoint from that checkout.

For example, an operator might run `/product-a/runtime-release` with:

```text
TARGET_SOC=soc-a
RELEASE_REF=soc-a-customer-x
RELEASE_REF_TYPE=branch
```

## Environment Bindings

Environment selection must be explicit. The product seed job receives
`CI_ENV`, for example:

```text
CI_ENV=simulation
CI_ENV=product
```

The selected environment binding should stay small. It binds the same product
CI configuration to a runtime environment; it must not become a second
configuration source. The binding can be represented however the product CI
repository chooses.

Environment-specific bindings should normally include only:

- Service URLs.
- Credential IDs.
- Jenkins folder.
- Agent label bindings.
- Artifact publishing mode or endpoint.
- Notification mode or endpoint.
- Simulation-only safety switches.

Environment-specific bindings should not normally include:

- Repository names.
- Target names.
- Branch pattern mappings.
- Pipeline lists.
- Jenkinsfile paths.
- Job naming rules.

For example, the simulation binding for `product-a` might point at the
Loopforge Gerrit endpoint, use the `/simulation/product-a` Jenkins folder,
reference a simulation Gerrit credential ID, use the simulation cross-build
agent label, and disable artifact publishing. The product binding might use
the product Gerrit endpoint, the `/product-a` Jenkins folder, the product
credential ID, the product cross-build agent label, and the product artifact
publishing mode.

## Seed Job Operation

The product seed job is created by bootstrap work outside the generated product
jobs. In Loopforge simulation, that bootstrap is a later simulation
integration task. In target deployment, it may be created by a Jenkins
administrator or by reviewed Jenkins controller bootstrap automation.

Initial seed-job behavior:

- Run manually.
- Checkout the product CI configuration repository.
- Require explicit `CI_ENV`.
- Load and validate the product CI configuration.
- Load the selected environment binding.
- Run the product-owned job reconciliation or generation mechanism.
- Overwrite generated jobs listed by the product CI configuration.
- Ignore unknown jobs in the product folder.
- Record the selected environment, CI config repository URL, ref, commit,
  configuration digest, generated job list, and bounded log references.

Automatic seed execution on product CI repository merge may be added later,
but it is not the initial requirement.

## Simulation And Product Portability

The same product CI configuration repository should be usable in simulation
and product deployment. Migration is source-control based:

```text
simulation to product:
  promote reviewed product CI repository commits through product Gerrit review

product to simulation:
  clone selected product CI and app repository refs into simulation Gerrit
```

Jenkins runtime state is not the source of truth for migration. Product CI
configuration repositories, app repositories, and reviewed Gerrit changes are
the source of truth.

In Docker simulation, Gerrit repositories are stored by Gerrit under:

```text
/srv/gerrit/git
```

That path is backed on the host by:

```text
generated/simulation/docker/sets/<set-id>/runtime/product-homes/gerrit/git
```

Treat this as Gerrit runtime state, similar to a database directory. Manage
repository content through Git and Gerrit APIs. Do not author, migrate, or
repair product CI configuration by editing the bare repository directories
directly.

For product-to-simulation sync, copy selected refs rather than mirroring all
refs by default. Usually include:

```text
refs/heads/main
refs/heads/release/*
needed refs/tags/*
```

Avoid copying these by default:

```text
refs/changes/*
refs/users/*
refs/cache-automerge/*
refs/meta/config
```

Copy `refs/meta/config` only when the work explicitly requires Gerrit project
configuration reproduction and the operator has reviewed the effect.

## Integration Handoff

Integration CI may be owned by another product or group. Product CI should not
manage external integration jobs by default. Instead, product CI should make
integration easy by publishing stable artifact metadata and handoff records.

Recommended handoff fields:

```json
{
  "product": "product-a",
  "repo": "product-a/runtime",
  "commit": "abc123",
  "branch": "soc-a-customer-x",
  "target": "soc-a",
  "ipFamily": "ai-accelerator-v1",
  "artifact": "product-a-runtime-soc-a.tar.gz",
  "checksum": "sha256:...",
  "buildType": "nightly"
}
```

External integration CI can consume those records without owning product build
logic or product generated jobs.

## Source References

This model follows common patterns from Jenkins and public CI configuration
systems:

- Jenkins Pipeline as Code and app-owned Jenkinsfiles.
- Jenkins Job DSL seed jobs for generated Jenkins job definitions.
- Jenkins Job Builder style external job configuration repositories.
- Wikimedia `integration/config`, Linux Foundation `ci-management`, and
  OpenDev project configuration patterns.
- Pattern-based branch matching from systems such as Zuul.

If Loopforge prototypes generated jobs first, Jenkins Job DSL is a practical
initial mechanism because the current Jenkins controller baseline already
includes the Job DSL plugin. That prototype choice must not prevent a product
CI repository from using Jenkins Job Builder or another reviewed
representation.

## Appendix: Non-Normative YAML Sketch

This appendix is a teaching aid only. It is not implemented, not supported,
not a required file format, and not a planned Loopforge CI DSL. Do not use it
as a schema or helper input contract. Product CI repositories may use
Jenkinsfiles, Jenkins Job DSL, Jenkins Job Builder, product-owned scripts, or
another reviewed representation.

The sketch below shows one possible way to visualize the concepts from this
model:

```yaml
product: product-a

repositories:
  - name: product-a/runtime
    targets: [soc-a, soc-b]

    branchPatterns:
      - pattern: main
        targets: [soc-a, soc-b]
      - pattern: feature/*
        targets: [soc-a, soc-b]
      - pattern: soc-a-*
        targets: [soc-a]
      - pattern: soc-b-*
        targets: [soc-b]

    jobs:
      verify:
        trigger: gerrit
        entrypoint: Jenkinsfile.verify
        branchPatterns: [main, feature/*, soc-a-*, soc-b-*]

      nightly:
        trigger: schedule
        entrypoint: Jenkinsfile.nightly
        branchPatterns: [main, soc-a-*, soc-b-*]

      release:
        trigger: manual
        entrypoint: Jenkinsfile.release
        parameters:
          TARGET_SOC: [soc-a, soc-b]
          RELEASE_REF: branch-or-tag-name
          RELEASE_REF_TYPE: [branch, tag]
```

The important model behavior is not the YAML shape. The important behavior is
that product CI configuration identifies app repositories, generated jobs,
branch selection, target SoC selection, app-owned pipeline entrypoints, and
manual release parameters while keeping Loopforge out of product-specific
build logic.
