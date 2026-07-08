#!/usr/bin/env bash

vm_libvirt_preflight_readonly() {
  printf 'libvirt=deferred-m2\n'
}

vm_libvirt_status_readonly() {
  printf 'vm-resources=not-created-m1\n'
}
