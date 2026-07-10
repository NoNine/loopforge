# VM Simulation Command Sequences

This document records internal command sequence diagrams for the VM simulation
harness. `simulation/vm/README.md` owns the public command contract, and
`simulation/vm/design.md` owns the module boundary model. These diagrams
validate how the public commands should flow through the folded VM modules.

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
  participant SET as vm-set.sh
  participant BASE as baseline.sh
  participant SNAP as snapshots.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_create(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_prepare()
  LC->>SNAP: vm_snapshots_status()
  Note over LC,SNAP: reuse only matching ready baseline state; fail on stale state
  LC->>SET: vm_set_create()
  LC->>LV: vm_libvirt_start_set()
  LC->>SSH: vm_ssh_prepare_all()
  LC->>BASE: vm_baseline_verify_prereqs()
  Note over LC,BASE: verify role OS dependency baselines and LDAP proof
  LC->>LV: vm_libvirt_shutdown_set()
  LC->>SNAP: vm_snapshots_capture()
  LC-->>CLI: compact create summary
```

## up

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh
  participant SSH as ssh.sh

  CLI->>LC: vm_cmd_up(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_run_and_set()
  LC->>LV: vm_libvirt_start_set()
  LC->>SSH: vm_ssh_prepare_all()
  LC-->>CLI: compact up summary
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
  LC->>ART: vm_artifacts_prepare(role)
  ART->>SSH: vm_ssh_run(bundle-factory, helper prepare-artifacts)
  ART->>SSH: vm_ssh_copy_from(bundle-factory, archives)
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
  LC->>ART: vm_artifacts_stage(role)
  ART->>SSH: vm_ssh_copy_to(target role, archive and checksum)
  ART->>SSH: vm_ssh_run(target role, verify checksum)
  ART->>SSH: vm_ssh_run(target role, unpack to staging)
  ART->>SSH: vm_ssh_run(target role, verify manifest)
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
  INT->>ST: vm_state_write_checkpoint_marker(validate-integration)
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
  LC->>ST: vm_state_verify_checkpoint_marker(validate-integration)
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

## down

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant SET as vm-set.sh
  participant LV as libvirt.sh

  CLI->>LC: vm_cmd_down(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_marker_for_teardown()
  LC->>LV: vm_libvirt_shutdown_set()
  LC-->>CLI: compact down summary
```

## clean

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant CFG as config.sh
  participant ST as state.sh
  participant SET as vm-set.sh
  participant SNAP as snapshots.sh

  CLI->>LC: vm_cmd_clean(env)
  LC->>CFG: vm_config_load_runtime()
  LC->>SET: vm_set_verify_run_and_set()
  LC->>SNAP: vm_snapshots_restore()
  LC->>ST: vm_state_clean_mutable_run_state()
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
  LC->>CFG: vm_config_load_runtime()
  LC->>ST: vm_state_verify_run_marker()
  LC->>SET: vm_set_destroy()
  LC->>SET: vm_set_remove_metadata()
  LC-->>CLI: compact destroy summary
```

## run

```mermaid
sequenceDiagram
  participant CLI as simulate.sh
  participant LC as lifecycle.sh
  participant ST as state.sh

  CLI->>LC: vm_cmd_run(env)
  LC->>ST: vm_state_detect_run_mode()
  LC-->>CLI: run mode summary
  LC->>LC: vm_cmd_preflight()
  LC->>LC: vm_cmd_init_run()
  LC->>LC: vm_cmd_create()
  LC->>LC: vm_cmd_up()
  LC->>LC: vm_cmd_prepare_artifacts()
  LC->>LC: vm_cmd_stage_artifacts()
  LC->>LC: vm_cmd_configure_role()
  LC->>LC: vm_cmd_validate_role()
  LC->>LC: vm_cmd_configure_integration()
  LC->>LC: vm_cmd_validate_integration()
  LC->>LC: vm_cmd_prove_integration()
  LC-->>CLI: compact run summary
```
