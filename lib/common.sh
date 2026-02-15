#!/usr/bin/env bash

SB_APT_UPDATED="${SB_APT_UPDATED:-0}"

sb_timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

json_escape() {
  local text="${1:-}"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  text="${text//$'\t'/\\t}"
  printf '%s' "$text"
}

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "ERROR: missing required command: $cmd" >&2
      return 1
    fi
  done
}

apt_update_once() {
  require_cmd apt-get
  if [[ "${SB_APT_UPDATED}" != "1" ]]; then
    apt-get -qq update
    SB_APT_UPDATED="1"
  fi
}

safe_write_file() {
  local target="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"

  local parent tmp
  parent="$(dirname "$target")"
  install -d -m 0755 "$parent"

  tmp="$(mktemp "${parent}/.tmp.XXXXXX")"
  cat >"$tmp"
  install -m "$mode" -o "$owner" -g "$group" "$tmp" "$target"
  rm -f "$tmp"
}

systemd_enable_verify() {
  local unit="$1"
  systemctl daemon-reload
  systemctl enable --now "$unit"
  if ! systemctl is-enabled --quiet "$unit"; then
    echo "ERROR: systemd unit is not enabled: $unit" >&2
    return 1
  fi
  if ! systemctl is-active --quiet "$unit"; then
    echo "ERROR: systemd unit is not active: $unit" >&2
    return 1
  fi
}

set_config_option() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]" "$file"; then
    sed -i "s|^[[:space:]]*#\?[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
  else
    printf '%s %s\n' "$key" "$value" >>"$file"
  fi
}

validate_username() {
  local username="$1"
  [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate_positive_int() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

validate_bool_01() {
  local value="$1"
  [[ "$value" == "0" || "$value" == "1" ]]
}

validate_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{1,5}$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

validate_interface_name() {
  local iface="$1"
  [[ "$iface" =~ ^[a-zA-Z0-9_.:-]{1,15}$ ]]
}

validate_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local a b c d
  IFS='.' read -r a b c d <<<"$ip"
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

validate_ipv4_cidr() {
  local cidr="$1"
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]] || return 1
  validate_ipv4 "${cidr%%/*}"
}
