# VM Simulation Command Sequences

This document records internal command sequence diagrams for the VM simulation
harness. `simulation/docs/vm/vm-simulation.md` owns the public command contract, and
`simulation/docs/vm/implementation-design.md` owns the VM module boundary
model. These diagrams validate how the public commands should flow through the
folded VM modules.

Shared guards, checkpoint opening/commit, predecessor order, and failure effects
are intentionally omitted. `simulation/docs/shared/lifecycle-state-model.md` and
`simulation/docs/shared/checkpoint-acceptance-protocol.md` wrap each applicable phase;
the diagrams show only VM-specific module flow.

The diagrams use capability-shaped APIs below `lifecycle.sh`. Command-shaped
APIs should stay in `lifecycle.sh`.

## preflight

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant PATH as paths.sh
  participant ST as state.sh
  participant LV as libvirt.sh

  CLI->>LC: vm_cmd_preflight(env)
  LC->>CFG: vm_config_load(env)
  CFG->>PATH: vm_paths_init(selection)
  LC->>ST: vm_state_preflight_readonly()
  LC->>LV: vm_libvirt_preflight_readonly()
  LC-->>CLI: compact preflight summary
```

## init-run

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant PATH as paths.sh
  participant ST as state.sh

  CLI->>LC: vm_cmd_init_run(env)
  LC->>CFG: vm_config_load(env)
  CFG->>PATH: vm_paths_init(selection)
  LC->>PATH: vm_path_runtime_inputs()
  LC->>CFG: vm_config_copy_runtime_inputs()
  LC->>CFG: vm_config_write_runtime()
  LC->>ST: vm_state_write_run_marker()
  LC-->>CLI: compact init-run summary
```

## create

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant BASE as baseline.sh
  participant SNAP as snapshots.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_create(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_prepare()
  LC->>SNAP: vm_snapshots_status()
  Note over LC,SNAP: reuse only matching ready baseline state and fail on stale state
  LC->>SET: vm_set_create()
  LC->>LV: vm_libvirt_start_set()
  LC->>SSH: vm_ssh_prepare_all()
  LC->>BASE: vm_baseline_verify_prereqs()
  Note over LC,BASE: verify role OS dependency baselines and LDAP proof
  LC->>LV: vm_libvirt_shutdown_set()
  LC->>SNAP: vm_snapshots_capture()
  LC-->>CLI: compact create summary
```

## start

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_start(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_run_and_set()
  LC->>ST: vm_state_verify_startable()
  LC->>LV: vm_libvirt_start_set()
  LC->>SSH: vm_ssh_prepare_all()
  LC-->>CLI: compact start summary
```

## status

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant SET as vm-set.sh
  participant BASE as baseline.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_status(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_validate_ownership_readonly()
  LC->>BASE: vm_baseline_status()
  LC->>LV: vm_libvirt_domain_state(service VMs)
  LC->>SSH: vm_ssh_status_readonly()
  LC-->>CLI: compact status summary
```

## ssh

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_ssh(role)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_run_and_set()
  LC->>LV: vm_libvirt_require_running(role)
  LC->>SSH: vm_ssh_interactive_role(role)
  SSH-->>LC: interactive session exit
  LC-->>CLI: ssh exit status
```

## prepare-artifacts

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant ART as artifacts.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_prepare_artifacts(role)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>ART: vm_artifacts_prepare_role(role)
  ART->>SSH: copy role env to operator input path
  ART->>SSH: invoke staged role helper
  ART->>SSH: vm_ssh_run(bundle-factory, helper prepare-artifacts)
  ART->>SSH: copy archive pair from bundle-factory
  ART->>ART: verify exported manifest and checksums
  ART-->>LC: artifact preparation summary
  LC-->>CLI: compact prepare-artifacts summary
```

## stage-artifacts

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant ART as artifacts.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_stage_artifacts(role)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>ART: vm_artifacts_stage_role(role)
  ART->>ART: verify exported manifest and checksums
  ART->>SSH: copy role env to operator input path
  ART->>SSH: run helper prepare-target-workspace
  ART->>SSH: vm_ssh_copy_to(target role, archive and checksum)
  ART->>SSH: vm_ssh_run(target role, verify checksum)
  ART->>SSH: vm_ssh_run(target role, unpack to staging)
  ART->>SSH: vm_ssh_run(target role, verify manifest and source label)
  LC-->>CLI: compact stage-artifacts summary
```

## configure-role

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant ROLE as roles.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_configure_role(role)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>ROLE: vm_roles_configure(role)
  ROLE->>SSH: vm_ssh_run(role target, helper configure-role)
  ROLE-->>LC: role evidence summary
  LC-->>CLI: compact configure-role summary
```

## validate-role

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant ROLE as roles.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_validate_role(role)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>ROLE: vm_roles_validate(role)
  ROLE->>SSH: vm_ssh_run(role target, helper validate-role)
  ROLE-->>LC: role evidence summary
  LC-->>CLI: compact validate-role summary
```

## configure-integration

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant INT as integration.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_configure_integration()
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>INT: vm_integration_configure()
  INT->>SSH: vm_ssh_run(controller and targets, integration setup)
  INT-->>LC: integration evidence summary
  LC-->>CLI: compact configure-integration summary
```

## validate-integration

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant INT as integration.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_validate_integration()
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>INT: vm_integration_validate()
  INT->>SSH: vm_ssh_run(controller and targets, integration validation)
  INT-->>LC: validation result and evidence
  LC-->>CLI: compact validate-integration summary
```

## prove-integration

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant INT as integration.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_prove_integration()
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>INT: vm_integration_prove()
  INT->>SSH: vm_ssh_run(controller and targets, integration proof)
  LC-->>CLI: compact prove-integration summary
```

## reboot

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_reboot(role or all)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_set_verify_run_and_set()
  LC->>SSH: vm_ssh_run(targets, delegated reboot)
  LC->>SSH: vm_ssh_wait_ready(targets)
  LC->>SSH: vm_ssh_verify_known_hosts(targets)
  LC-->>CLI: compact reboot summary
```

## audit-state

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant BASE as baseline.sh
  participant SNAP as snapshots.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_audit_state(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_audit_readonly()
  LC->>SET: vm_set_validate_ownership_readonly()
  LC->>BASE: vm_baseline_audit_readonly()
  LC->>SNAP: vm_snapshots_audit_readonly()
  LC->>ST: vm_state_read_summary()
  LC->>LV: vm_libvirt_status_readonly()
  LC->>SSH: vm_ssh_status_readonly()
  LC-->>CLI: compact audit-state summary
```

## stop

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh

  CLI->>LC: vm_cmd_stop(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_marker_for_teardown()
  LC->>LV: vm_libvirt_shutdown_set()
  LC-->>CLI: compact stop summary
```

## restore-baseline

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant SNAP as snapshots.sh

  CLI->>LC: vm_cmd_restore_baseline(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>SET: vm_set_verify_selected_ownership()
  LC->>SNAP: vm_snapshots_restore()
  LC->>ST: vm_state_record_restored_pending_clean()
  Note over LC,ST: publish gate only after matching restore verification
  LC-->>CLI: compact restore-baseline summary
```

## clean

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh

  CLI->>LC: vm_cmd_clean(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>SET: vm_set_verify_selected_ownership()
  LC->>LV: vm_libvirt_require_set_shut_off(clean)
  LC->>ST: vm_state_verify_restored_pending_clean()
  LC->>ST: vm_state_clean_mutable_run_state()
  Note over LC,ST: retain review output and clear active-run pointer last
  LC-->>CLI: compact clean summary
```

## destroy

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh

  CLI->>LC: vm_cmd_destroy(env)
  alt runtime config valid
    LC->>CFG: vm_config_load_runtime()
  else recovery from bootstrap env
    LC->>CFG: vm_config_load(env)
  end
  opt run marker exists
    LC->>ST: vm_state_verify_run_marker()
  end
  LC->>SET: vm_set_destroy()
  LC->>SET: vm_set_remove_metadata()
  LC-->>CLI: compact destroy summary
```

## run

`vm_cmd_run` applies the shared composite order through VM command entrypoints.
It adds no VM-only workflow phase; `reboot` remains an explicit command outside
the composite.

The shared harness design owns plan selection. This VM binding classifies the
selected state, then sends every command in the selected plan through the same
`vm_cmd_*` handler and lock mode used by direct CLI invocation. Individual
command diagrams above own the capability calls below each handler.

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant RUN as lifecycle.sh: vm_cmd_run
  participant ST as Shared and VM state
  participant STEP as lifecycle.sh: vm_workflow_step
  participant LOCK as lifecycle.sh: vm_command_with_lock
  participant CMD as lifecycle.sh: vm_cmd_phase
  participant CAP as Owning VM capability

  CLI->>RUN: vm_cmd_run(env)
  RUN->>ST: resolve active run and classify selected state
  ST-->>RUN: allowed command plan or blocked state
  alt blocked or conflicting
    RUN-->>CLI: nonzero blocked result
  else executable plan
    loop each selected command in order
      RUN->>STEP: vm_workflow_step(command)
      STEP->>LOCK: vm_command_with_lock(lock mode, vm_cmd_phase)
      LOCK->>CMD: invoke first-class command handler
      CMD->>CAP: delegate owning operation or observation
      CAP-->>CMD: bounded result
      CMD-->>LOCK: command result
      LOCK-->>STEP: command result
      break command failed
        STEP-->>RUN: same nonzero result
        RUN-->>CLI: same nonzero result and stop plan
      end
      STEP-->>RUN: command completed and continue plan
    end
    RUN-->>CLI: compact run summary
  end
```

The selected plan includes the intentional `status` observation described by
the shared harness design. A stopped resumable or completed run therefore uses
`start -> status`; an already-running completed run uses `status` before its
`already-complete` summary. Neither path repeats a completed workflow
checkpoint.
