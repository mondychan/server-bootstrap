#!/usr/bin/env bash
# shellcheck disable=SC2034
# Module metadata variables are consumed dynamically by main.sh after sourcing this file.
set -euo pipefail

module_id="time-sync"
module_desc="Configure timezone and NTP sync via systemd-timesyncd"
module_env="TS_TIMEZONE, TS_NTP_SERVERS, TS_FALLBACK_NTP, TS_STRICT_SYNC, TS_SYNC_TIMEOUT_SEC"
module_deps=()

normalize_ntp_list() {
  local value="$1"
  value="${value//,/ }"
  local -a parts=()
  IFS=' ' read -r -a parts <<<"$value"
  printf '%s' "${parts[*]}"
}

validate_ntp_list() {
  local value="$1"
  [[ -z "$value" ]] && return 0

  local server
  for server in $value; do
    if [[ ! "$server" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
      return 1
    fi
  done
}

wait_for_ntp_sync() {
  local timeout_sec="$1"
  local elapsed=0
  local step=2

  while ((elapsed < timeout_sec)); do
    if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]; then
      return 0
    fi
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  return 1
}

module_plan() {
  local timezone="${TS_TIMEZONE:-CET}"
  local ntp_servers_raw="${TS_NTP_SERVERS:-}"
  local fallback_servers_raw="${TS_FALLBACK_NTP:-}"
  local strict_sync="${TS_STRICT_SYNC:-0}"
  local timeout_sec="${TS_SYNC_TIMEOUT_SEC:-60}"
  local ntp_servers fallback_servers

  ntp_servers="$(normalize_ntp_list "$ntp_servers_raw")"
  fallback_servers="$(normalize_ntp_list "$fallback_servers_raw")"

  echo "Plan: configure timezone=${timezone} and enable systemd-timesyncd"
  echo "Plan: NTP='${ntp_servers:-system-default}', fallback='${fallback_servers:-system-default}'"
  echo "Plan: strict_sync=${strict_sync}, timeout=${timeout_sec}s"
}

module_apply() {
  local timezone="${TS_TIMEZONE:-CET}"
  local ntp_servers_raw="${TS_NTP_SERVERS:-}"
  local fallback_servers_raw="${TS_FALLBACK_NTP:-}"
  local strict_sync="${TS_STRICT_SYNC:-0}"
  local timeout_sec="${TS_SYNC_TIMEOUT_SEC:-60}"
  local ntp_servers fallback_servers

  ntp_servers="$(normalize_ntp_list "$ntp_servers_raw")"
  fallback_servers="$(normalize_ntp_list "$fallback_servers_raw")"

  if ! validate_bool_01 "$strict_sync"; then
    echo "ERROR: invalid TS_STRICT_SYNC='${strict_sync}' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_positive_int "$timeout_sec"; then
    echo "ERROR: invalid TS_SYNC_TIMEOUT_SEC='${timeout_sec}' (expected positive integer)" >&2
    exit 1
  fi
  if ! validate_ntp_list "$ntp_servers"; then
    echo "ERROR: invalid TS_NTP_SERVERS='${ntp_servers_raw}'" >&2
    exit 1
  fi
  if ! validate_ntp_list "$fallback_servers"; then
    echo "ERROR: invalid TS_FALLBACK_NTP='${fallback_servers_raw}'" >&2
    exit 1
  fi

  require_cmd timedatectl systemctl

  if ! timedatectl list-timezones | grep -Fxq "$timezone"; then
    echo "ERROR: invalid TS_TIMEZONE='${timezone}' (not found in timedatectl list-timezones)" >&2
    exit 1
  fi

  echo "Setting timezone to ${timezone}"
  timedatectl set-timezone "$timezone"

  cat <<EOF | safe_write_file /etc/systemd/timesyncd.conf.d/50-bootstrap.conf 0644 root root
[Time]
EOF

  if [[ -n "$ntp_servers" ]]; then
    printf 'NTP=%s\n' "$ntp_servers" >>/etc/systemd/timesyncd.conf.d/50-bootstrap.conf
  fi
  if [[ -n "$fallback_servers" ]]; then
    printf 'FallbackNTP=%s\n' "$fallback_servers" >>/etc/systemd/timesyncd.conf.d/50-bootstrap.conf
  fi

  systemctl daemon-reload
  systemctl enable --now systemd-timesyncd
  timedatectl set-ntp true
  systemctl restart systemd-timesyncd

  if [[ "$strict_sync" == "1" ]]; then
    echo "Waiting for NTP synchronization (timeout ${timeout_sec}s)"
    if ! wait_for_ntp_sync "$timeout_sec"; then
      echo "ERROR: NTP did not reach synchronized state within ${timeout_sec}s" >&2
      exit 1
    fi
  fi

  echo "OK: time-sync configured (timezone=${timezone})"
}

module_verify() {
  local strict_sync="${TS_STRICT_SYNC:-0}"
  local timeout_sec="${TS_SYNC_TIMEOUT_SEC:-60}"

  if ! systemctl is-active --quiet systemd-timesyncd; then
    echo "ERROR: systemd-timesyncd is not active" >&2
    exit 1
  fi

  if [[ "$(timedatectl show -p NTP --value 2>/dev/null || true)" != "yes" ]]; then
    echo "ERROR: timedatectl reports NTP disabled" >&2
    exit 1
  fi

  if [[ "$strict_sync" == "1" ]]; then
    if ! wait_for_ntp_sync "$timeout_sec"; then
      echo "ERROR: NTPSynchronized is not yes within ${timeout_sec}s" >&2
      exit 1
    fi
  fi

  echo "OK: time-sync verify passed"
}
