# Operations Documentation

Loopforge has two operator documentation families. Use the document for the
target role and the kind of procedure being performed.

## Setup Manuals

`setup/` documents repository-assisted setup workflows. These manuals apply
the shared lifecycle and operator execution contracts through the Loopforge
helper commands, including their review and stop points.

- `setup/gerrit.md`
- `setup/jenkins-controller.md`
- `setup/jenkins-agent.md`
- `setup/integration.md`

## Native Operation References

`native/` documents direct OS and application procedures without repository
helper command transcripts or helper-equivalent workflows.

- `native/gerrit.md`
- `native/jenkins-controller.md`
- `native/jenkins-agent.md`
- `native/integration.md`

For a release claiming native `target-deployment` readiness, use
`native/acceptance-checklist.md` as the single end-to-end signoff surface after
following the four native operation references. The checklist records outcomes
without duplicating commands or requiring machine-generated evidence.

Product behavior remains owned by the authorities linked from
`docs/README.md`. These operation documents narrowly apply those facts and
must not redefine them.
