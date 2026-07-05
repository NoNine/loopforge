# AOSP-Style Jenkins CI Research

## Purpose

This research note records practical CI patterns for Android AOSP and
AOSP-style multi-repository projects that integrate Gerrit, Repo manifests,
and Jenkins. It supports the product CI ownership model in `docs/ci-model.md`
but does not replace it as product authority.

The central distinction is important: official AOSP documents Repo, manifest,
Git, and Gerrit workflows. It does not document Jenkins as the official AOSP
CI architecture. Jenkins integration appears in vendor, community, and
project-adjacent AOSP-style deployments layered on top of Repo and Gerrit.

## Official AOSP And Gerrit Baseline

Official AOSP uses Git repositories aggregated by Repo. AOSP's source control
tools documentation says Android work uses Git and Repo together, and that
Repo uses manifest files to aggregate Git projects into the Android
superproject. The Repo command reference describes `repo init -u` for choosing
the manifest repository, `-b` for choosing the manifest branch, `-m` for
choosing a manifest file, and `repo sync` for fetching and updating projects.

Practical CI implications:

- A coherent checkout starts from a manifest repository, manifest branch, and
  manifest file, not from a single application Git repository.
- Branch and revision alignment are encoded by manifest state and by each
  project's selected revision.
- CI should record the manifest URL, manifest branch, manifest file, manifest
  commit, project list, and any local manifests or groups used for the build.

The Repo manifest format defines `remote`, `default`, and `project` elements.
Project entries can carry attributes such as project `name`, checkout `path`,
`revision`, `dest-branch`, `groups`, and upstream metadata. In CI terms,
`revision` is the checkout selection, while `dest-branch` helps describe where
reviews are intended to land when it differs from the checkout revision.

Gerrit review changes are project-scoped. Gerrit's `refs/for` documentation
describes pushes to `refs/for/<branch>` as review pushes that create refs
under `refs/changes/<last-two-digits>/<change>/<patchset>`. Gerrit's
`stream-events` command emits events such as `patchset-created` and
`ref-updated`, and requires either administrator membership or the
`Stream Events` global capability.

Practical CI implications:

- A satellite repository patchset is identified by Gerrit project, target
  branch, change number, patchset number, and review ref.
- The CI workspace usually needs a base manifest checkout plus an overlay of
  the triggering Gerrit patchset in the matching project.
- Direct branch updates and review patchsets are distinct triggers:
  `ref-updated` is a branch/ref movement; `patchset-created` is a review
  patchset event.

AOSP's Repo command reference also documents `repo upload --topic=TOPIC` and
`repo upload -t` for grouping related changes. Gerrit's cross-repository topic
documentation describes topics as a way to submit related changes across
repositories, while also making clear that topic behavior depends on Gerrit
configuration and submit policy.

Practical CI implications:

- Topic-based CI is a policy layer, not automatic magic. Product CI must
  decide whether to build only the triggering patchset or all open changes in
  the same topic.
- If topic builds are supported, CI must validate that topic changes are
  coherent for the selected manifest branch and do not mix incompatible target
  branches or product lines.

## AOSP-Style Jenkins Practice

The Jenkins Gerrit Trigger plugin is a common integration point for AOSP-style
Jenkins deployments. Its documentation describes listening to Gerrit events,
matching projects and branches, and exposing Gerrit environment variables to
jobs. It also documents a Repo-oriented checkout pattern: initialize and sync
the manifest workspace, then apply the review change with `repo download`
using the Gerrit project and change/patchset values.

Practical CI shape:

1. Jenkins receives a Gerrit `patchset-created` event.
2. The generated or configured job filters on Gerrit project and branch.
3. The job initializes the product manifest checkout.
4. The job syncs the manifest-selected repo set.
5. The job overlays the triggering patchset in the triggering project.
6. The job runs the selected Jenkinsfile or pipeline script.
7. Jenkins reports verification back to Gerrit through the configured review
   path.

This is AOSP-style practice, not official AOSP architecture. The strong
pattern is that Gerrit supplies event context, Repo supplies the coherent
workspace, and product CI supplies the policy for selecting manifests,
branches, groups, build targets, and cross-repo change grouping.

The Jenkins Repo plugin provides Repo as a Jenkins SCM implementation. Jenkins
Job Builder also documents a Repo SCM module with fields for manifest URL,
manifest branch, manifest file, manifest group, mirror directory,
current-branch behavior, and local manifests. These mechanisms are optional;
many pipelines instead run `repo init`, `repo sync`, and `repo download` from
shell or shared library code.

Practical CI implications:

- The checkout mechanism should be product-owned. Loopforge should not require
  Repo, the Jenkins Repo plugin, or shell checkout as the only supported
  pattern.
- The CI contract should still expose the same core inputs: manifest identity,
  project identity, Gerrit event ref, branch, topic, and selected product
  target.
- If Jenkins plugins perform the checkout, the product CI repository should
  still make the manifest and ref policy reviewable.

## Where Pipeline Definitions Live

Jenkins supports Pipeline as Code through Jenkinsfiles in source control.
Jenkins shared libraries can also live in source control and provide reusable
pipeline code.

In AOSP-style multi-repo systems, there are several defensible placements:

- Application repository Jenkinsfile: the triggering or build-owner repo
  contains the Jenkinsfile used for that repo's verify, nightly, or release
  build.
- Manifest or product CI repository Jenkinsfile: a repository that defines the
  repo set also contains orchestration for that repo set.
- Product CI repository job definitions: jobs are generated or reconciled from
  reviewed CI definitions, while the actual build steps remain in app-owned
  Jenkinsfiles or shared libraries.
- Shared pipeline library: common checkout, topic handling, and vote posting
  logic lives in a Jenkins shared library, with product jobs passing explicit
  manifest and Gerrit context.

The right placement depends on ownership. If a satellite repo cannot build by
itself, the Jenkinsfile often belongs to a main repository, manifest
repository, or product CI repository that understands the whole repo set.

## Job DSL, Jenkinsfiles, And JJB

These tools solve different problems:

- Jenkinsfile: Pipeline definition, usually stored in SCM and evaluated by a
  Jenkins Pipeline job.
- Job DSL: Groovy-based Job DSL scripts that represent Jenkins jobs and can
  generate job XML inside Jenkins. A seed job is a common way to load those
  scripts, but the fundamental representation is the Job DSL script.
- Jenkins Job Builder: YAML or JSON job definitions that the external
  `jenkins-jobs` tool reads and uses to create or update Jenkins jobs.

Practical CI implications:

- Job DSL or JJB can own Jenkins job topology: folders, triggers, parameters,
  SCM bindings, labels, retention, and generated job descriptions.
- Jenkinsfiles should normally own product build and test behavior, especially
  when branch-specific pipeline behavior matters.
- Product CI repositories outside Loopforge can choose Jenkinsfiles, Job DSL,
  JJB, or another reviewed representation without changing the Loopforge
  Gerrit/Jenkins integration model.

## Project-Adjacent Examples

### CORD

The OpenCORD manifest repository includes a Jenkinsfile in the manifest
repository itself. The Jenkinsfile operates against CORD's Gerrit projects and
manifest repository, creates support branches, checks out the manifest repo,
uses Jenkins' Repo SCM with a `manifestBranch` and `manifestGroup`, and
publishes instructions using `repo init -u https://gerrit.opencord.org/manifest
-b <branch>` followed by `repo sync`.

This is useful evidence for a product CI model because it shows a practical
pattern where CI orchestration lives near the manifest/repo-set definition.
It should be classified as CORD project practice, not as official AOSP
practice.

### Linux Foundation Releng

The Linux Foundation releng Jenkins guide documents Jenkins Job Builder usage
for LF-managed project CI. This is not AOSP-specific, but it is
project-adjacent to Gerrit/Jenkins open source infrastructure practice and
shows the reviewed CI configuration repository style that many Gerrit-based
projects use.

This supports the Loopforge model where product-owned CI configuration can
live outside Loopforge and generate or reconcile Jenkins jobs.

## Implications For Loopforge

Loopforge should keep the product CI boundary in `docs/ci-model.md`: Loopforge
owns Gerrit, Jenkins, agent wiring, Gerrit Trigger integration, `Verified`
voting, validation, and evidence. Product CI repositories own product job
definitions, manifest/ref policy, checkout orchestration, and generated job
reconciliation.

For AOSP-style product CI repositories outside Loopforge, the minimum useful
contract is:

- Manifest URL, manifest branch, manifest file, and optional manifest groups.
- Gerrit project, target branch, change number, patchset number, refspec, and
  topic when present.
- Pipeline owner repository and Jenkinsfile or pipeline entrypoint.
- Trigger policy for satellite repositories in a multi-repo app group.
- Branch/ref alignment policy for the main repo, satellite repos, and pinned
  dependencies.
- Whether topic builds are supported, and how related changes are selected and
  validated.
- Jenkins folder, credential IDs, agent labels, and environment binding values
  for simulation or product deployment.

The model should avoid these unsupported claims:

- Do not present Jenkins as official Android Open Source Project CI
  architecture.
- Do not imply Gerrit topics automatically create a coherent multi-repo build.
- Do not require all products to use Repo just because AOSP-style projects
  often do.
- Do not require Job DSL, JJB, or Jenkinsfiles as the only product CI
  representation.

The most defensible Loopforge statement is:

```text
Official AOSP documents Repo, manifests, Git, and Gerrit review workflows.
Jenkins integration is a vendor, community, or product CI layer that can use
Gerrit events and Repo manifests to build coherent multi-repo workspaces.
Loopforge supports the Gerrit/Jenkins integration substrate while product CI
repositories own the manifest, job, checkout, and branch/ref policy.
```

## References

- AOSP source control tools:
  <https://source.android.com/docs/setup/download/source-control-tools>
- AOSP Repo command reference:
  <https://source.android.com/docs/setup/reference/repo>
- Repo manifest format:
  <https://gerrit.googlesource.com/git-repo/+/HEAD/docs/manifest-format.md>
- Gerrit `refs/for` namespace:
  <https://gerrit-review.googlesource.com/Documentation/concept-refs-for-namespace.html>
- Gerrit `stream-events`:
  <https://gerrit-review.googlesource.com/Documentation/cmd-stream-events.html>
- Gerrit cross-repository topics:
  <https://gerrit-review.googlesource.com/Documentation/cross-repository-changes.html>
- Jenkins Gerrit Trigger plugin:
  <https://plugins.jenkins.io/gerrit-trigger/>
- Jenkins Pipeline:
  <https://www.jenkins.io/doc/book/pipeline/>
- Jenkins shared libraries:
  <https://www.jenkins.io/doc/book/pipeline/shared-libraries/>
- Jenkins Job DSL plugin:
  <https://plugins.jenkins.io/job-dsl/>
- Jenkins Job Builder job definitions:
  <https://jenkins-job-builder.readthedocs.io/en/stable/definition.html>
- Jenkins Job Builder Repo SCM:
  <https://jenkins-job-builder.readthedocs.io/en/stable/scm.html#scm.repo>
- Jenkins Repo plugin:
  <https://github.com/jenkinsci/repo-plugin>
- OpenCORD manifest Jenkinsfile:
  <https://github.com/opencord/manifest/blob/master/Jenkinsfile>
- Linux Foundation releng Jenkins guide:
  <https://docs.releng.linuxfoundation.org/en/latest/jenkins.html>
