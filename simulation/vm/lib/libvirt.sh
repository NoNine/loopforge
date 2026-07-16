#!/usr/bin/env bash

VM_LIBVIRT_URI="${VM_LIBVIRT_URI:-qemu:///system}"
VM_BASELINE_SNAPSHOT_NAME="${VM_BASELINE_SNAPSHOT_NAME:-loopforge-clean-baseline}"
VM_BASE_IMAGE_BAKE_SCHEMA_VERSION=6
VM_BAKE_DEBUG_MARKER_SCHEMA_VERSION=1
vm_machines=(bundle-factory ldap gerrit jenkins-controller jenkins-agent)

. "$vm_lib_dir/libvirt-core.sh"
. "$vm_lib_dir/libvirt-storage.sh"
. "$vm_lib_dir/libvirt-domain.sh"
. "$vm_lib_dir/libvirt-image.sh"
