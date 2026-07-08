#!/usr/bin/env bash

vm_integration_blocked_m1() {
  vm_cmd_blocked_m1 "${1:?command required}" ""
}
