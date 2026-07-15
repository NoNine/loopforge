# Operations Documentation

Loopforge has two operator documentation families. Use the document for the
target role and the kind of procedure being performed.

## Native Operation References

`native/` documents direct OS and application procedures without repository
helper command transcripts or helper-equivalent workflows. These references
are the procedural baseline for operation documentation.

Native references are operator-first and operator-friendly. Organize them
around the operator's task sequence, place prerequisites and inputs before
mutation, put native commands beside the task they perform, state expected
outcomes and failure boundaries, and make validation and handoffs clear. Write
for the operator completing the deployment, not for a repository maintainer
explaining helper internals.

Use the shortest reviewable sequence of OS and application-native commands that
preserves the owning contract. Prefer a tool's own validation, status, and
reporting options over embedded shell parsers or helper-like orchestration.
Commands should be independently runnable, keep their output inspectable, and
name the operator decision or stop condition immediately after the command.
Use shell loops or parsing only when the native tool has no suitable operation;
keep that logic small, local to the task, and directly auditable. Do not
reproduce helper implementation logic, generated state machines, or
machine-evidence pipelines in a native manual.

- `native/gerrit.md`
- `native/jenkins-controller.md`
- `native/jenkins-agent.md`
- `native/integration.md`

Use `native/review-guide.md` to review these manuals consistently and to keep
static review, native-tool proof, and runtime acceptance distinct.

For a release claiming native `target-deployment` readiness, use
`native/acceptance-checklist.md` as the single end-to-end signoff surface after
following the four native operation references. The checklist records outcomes
without duplicating commands or requiring machine-generated evidence.

## Setup Manuals

`setup/` documents repository-assisted setup workflows. These manuals apply
the shared lifecycle and operator execution contracts through the Loopforge
helper commands, including their review and stop points. They follow the
native procedural baseline and must produce equivalent product state and
validation outcomes without redefining the direct procedure.

- `setup/gerrit.md`
- `setup/jenkins-controller.md`
- `setup/jenkins-agent.md`
- `setup/integration.md`

Product behavior remains owned by the authorities linked from
`docs/README.md`. These operation documents narrowly apply those facts and
must not redefine them.
