#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "list modules works without root" {
  run bash ./main.sh --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssh-keys"* ]]
  [[ "$output" == *"webmin"* ]]
  [[ "$output" == *"docker"* ]]
  [[ "$output" == *"wireguard"* ]]
  [[ "$output" == *"unattended-upgrades"* ]]
  [[ "$output" == *"time-sync"* ]]
}

@test "list modules json works" {
  run bash ./main.sh --list-json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id":"ssh-keys"'* ]]
  [[ "$output" == *'"id":"wireguard"'* ]]
  [[ "$output" == *'"id":"unattended-upgrades"'* ]]
  [[ "$output" == *'"id":"time-sync"'* ]]
}

@test "list profiles works" {
  run bash ./main.sh --list-profiles
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev"* ]]
  [[ "$output" == *"prod"* ]]
}

@test "plan mode works without root" {
  run bash ./main.sh --plan --no-interactive --modules docker --profile dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker: plan"* ]]
}

@test "dry-run apply works without root" {
  run env BOOTSTRAP_DRY_RUN=1 bash ./main.sh --apply --no-interactive --modules docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run skip apply/verify"* ]]
}

@test "unknown module fails" {
  run bash ./main.sh --plan --no-interactive --modules does-not-exist
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown module"* ]]
}
