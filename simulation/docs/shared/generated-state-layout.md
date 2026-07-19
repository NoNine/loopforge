# Generated Simulation State Layout

## Purpose And Authority

This document owns the host-side generated storage layout shared by Docker and
VM simulation. It defines canonical set, lock, and run roots; common child
paths; content custody; sensitivity; and mutable or retained cleanup classes.

It does not define target-visible runtime paths, record schemas, state
transitions, public command semantics, or backend implementation APIs:

- `docs/contracts/directory-model.md` owns paths visible inside the bundle
  factory and role targets.
- `simulation/docs/shared/lifecycle-state-model.md` owns the meaning, schema,
  publication order, and transitions of records stored in this layout.
- `simulation/docs/shared/simulation-model.md` owns public shared simulation
  terminology and command semantics.
- Backend guides own Docker- or VM-specific storage realization and transfer
  mechanisms; implementation designs assign construction to backend
  `paths.sh` modules.

Consumer documents may repeat a path when an operator must type, inspect, or
recognize it. They must link here instead of redefining its custody,
sensitivity, retention, or cleanup behavior.

## Canonical Roots

In these paths, `<backend>` is `docker` or `vm`:

```text
generated/simulation/<backend>/locks/<set-id>.lock
generated/simulation/<backend>/sets/<set-id>/
generated/simulation/<backend>/<run-id>/
```

The lock is stable and remains outside the deletable set root. The set root
owns reusable resources, durable runtime, baseline metadata, and at most one
active-run pointer. The run root owns one immutable attempt's inputs,
run step state, evidence, logs, and exported artifacts. Lifecycle
commands do not support arbitrary generated roots in v1.

The local account running the harness owns ordinary host-side generated paths
and need not be named `ci-operator`. Content dominance below identifies who
contributes the durable meaningful content; it does not redefine POSIX
ownership of host review copies. Libvirt-managed volumes are the exception and
remain managed through libvirt APIs.

## Shared Path Inventory

Paths without a `sets/<set-id>/` prefix are relative to the run root.

| Generated path | Content dominance | Custody and sensitivity | Cleanup class |
| --- | --- | --- | --- |
| `locks/<set-id>.lock` | Host-dominated | Shared-read or exclusive-mutation serialization; non-secret | Stable outside set and run cleanup |
| `sets/<set-id>/` | Host-dominated | Ownership marker, reusable resource records, durable runtime, and baseline metadata | Removed only by ownership-validated `destroy` |
| `sets/<set-id>/active-run.env` | Host-dominated | Strict non-secret run claim and reset-gate binding | Preserved by `start`, `stop`, and `restore-baseline`; removed last by successful `clean` or with set destruction |
| `host/rendered/` | Host-dominated | Operator-facing rendered harness configuration, inventory, run markers, and public manifest data | Mutable run custody removed by `clean` |
| `host/source-inputs/` | Host-dominated | Private actor-selected templates and supported overrides copied by `init-run`; mode `0700` directory with `0600` files | Mutable run custody removed by `clean` |
| `host/runtime-inputs/` | Host-dominated | Private effective helper inputs atomically published by the first successful `start`; mode `0700` directory with `0600` files | Mutable run custody removed by `clean` |
| `host/state/effective-inputs.env` | Host-dominated | Binding from source and effective fingerprints to backend, set, run, and run marker | Mutable run custody removed by `clean` |
| `host/state/run-plan-state.env` | Host-dominated | Strict run-step activity and current run-plan hash-chain head | Mutable run custody removed by `clean` |
| `host/state/run-steps/` | Host-dominated | Hash-linked immutable run-step records | Retained review output |
| `host/evidence/harness/operations/` | Host-dominated | Redacted, review-sensitive simulation operation records | Retained review output |
| `host/logs/harness/` | Host-dominated | Review-sensitive bounded harness logs | Retained review output |
| `host/evidence/integration/` | Host-dominated | Redacted, review-sensitive host-orchestrated integration producer records | Retained review output |
| `host/logs/integration/` | Host-dominated | Review-sensitive bounded integration logs | Retained review output |
| `target/evidence/<role>/` | Target-dominated | Retained producer-record copy corresponding to `/var/lib/loopforge/evidence` on one target | Retained review output |
| `target/logs/<role>/` | Target-dominated | Retained copy corresponding to `/var/log/loopforge` on one target | Retained review output |

The immutable backend run marker at the run root and exported artifact review
copies are also retained review output. Temporary publication files,
invocation adapters, transfer scratch, and retained-output cleanup backups are
private harness scratch; they do not become new canonical authorities.

## Input Custody

Simulation env examples are source templates, not final helper inputs.
`init-run` copies selected templates and supported overrides into
`host/source-inputs/`; helpers never consume those snapshots directly. The
first successful `start` publishes stable effective helper inputs in
`host/runtime-inputs/` and their binding in
`host/state/effective-inputs.env`. The lifecycle state model defines their
fingerprints, publication order, and repeated-start validation.

Backend-assigned transport hosts such as VM DHCP addresses are not stored in
either input directory. A private temporary integration invocation adapter may
overlay current transport hosts, but it is deleted after invocation and is not
retained state or evidence.

## Retention And Cleanup

`stop` preserves the complete set and run roots. `restore-baseline` changes
durable backend state but does not clean generated run state. After matching
restoration, `clean` removes mutable inputs, rendered state, the run-plan head,
and backend-specific run scratch while preserving the immutable run marker,
run-step records, operation records, exported artifact archives, producer
records, and bounded logs.
It removes `active-run.env` last. `destroy` removes the ownership-validated set
root and backend resources without deleting retained run roots.

The exact authorization, ordering, retry, and failure behavior of these
commands belongs to the lifecycle state model. This document owns only which
storage classes those commands affect.

## Docker Realization

Docker-specific generated state uses these additional paths:

| Docker path | Content dominance | Purpose |
| --- | --- | --- |
| `sets/<set-id>/baseline/` | Host-dominated | Checksummed image and Compose identity, bind-data archives, numeric ownership, and target SSH identity used by `restore-baseline` |
| `sets/<set-id>/runtime/` | Target-dominated | LDAP data, product homes, shared storage, integration helper state, and target staging for the reusable set |
| `host/bundle-factory/rendered/` | Host-dominated | Effective input copy before the labeled Docker input-transfer waiver |
| `host/bundle-factory/validation-public/` | Host-dominated | Public simulation validation material transferred to the bundle factory |
| `host/target-ssh/` | Host-dominated | Run-scoped private target SSH key and known-hosts material |
| `host/validation-secrets/gerrit/` | Host-dominated | Docker-only SSH validation key material; excludes LDAP bind secrets and uses mode `0700` |
| `target/artifacts/exported/` | Target-dominated | Exported archive review copies and checksums |

Docker generated directories are not target payload transfer mechanisms unless
the Docker guide explicitly labels a `docker cp` waiver. Container-visible
`/var/lib/loopforge` and `/var/log/loopforge` roots remain helper-created target
paths governed by the product directory model.

## VM Realization

VM-specific generated state uses these additional paths:

| VM path | Content dominance | Purpose |
| --- | --- | --- |
| `sets/<set-id>/libvirt/` | Host-dominated | Domain, network, pool, volume, seed-media, machine, and baseline descriptors |
| `sets/<set-id>/libvirt/disks/` | Libvirt-dominated | Libvirt directory-pool target for the set-local base image and mutable qcow2 volumes |
| `sets/<set-id>/seeds/` | Host-dominated | Simulation-owned VM bootstrap inputs and rendered seed metadata |
| `sets/<set-id>/snapshots/` | Host-dominated | Clean baseline snapshot names, fingerprints, and capture evidence |
| `sets/<set-id>/target-ssh/` | Host-dominated | Target OS SSH identity seeded into reusable VM disks |
| Jenkins agent VM disk content | Target-dominated | Jenkins-agent-hosted shared storage exported to the controller VM, normally `/data/jenkins-shared` |
| `host/target-ssh/` | Host-dominated | Run-scoped known-hosts material for target OS SSH |
| `host/artifacts/exported/` | Host-dominated | Exported bundle archives and checksums copied back for review |

VM artifact staging uses target OS SSH and the guest-local canonical path
`/var/lib/loopforge/staging/<role>/`; it does not use a generated
`target/artifacts/staging/` sideband. The host operator owns VM control
metadata but does not adopt libvirt-managed qcow2 ownership. Libvirt volume
APIs provide inspection and deletion without direct host ownership repair.
