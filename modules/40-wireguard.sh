#!/usr/bin/env bash
# shellcheck disable=SC2034
# Module metadata variables are consumed dynamically by main.sh after sourcing this file.
set -euo pipefail

module_id="wireguard"
module_desc="Configure WireGuard client endpoint"
module_env="WG_INTERFACE, WG_ADDRESS, WG_CONFIRM, WG_TEST, WG_ENDPOINT_HOST, WG_ENDPOINT_PORT, WG_PEER_PUBLIC_KEY, WG_ALLOWED_IPS, WG_PERSISTENT_KEEPALIVE, WG_DNS"
module_deps=()

prompt_wireguard() {
  local message="$1"
  local reply=""

  if [[ -t 0 ]]; then
    printf "%s" "$message" >/dev/tty
    read -r reply
  elif [[ -r /dev/tty ]]; then
    printf "%s" "$message" >/dev/tty
    read -r reply </dev/tty
  else
    return 1
  fi
  printf '%s' "$reply"
}

validate_wg_endpoint_host() {
  local value="$1"
  [[ "$value" =~ ^[a-zA-Z0-9.-]+$ ]]
}

validate_wg_public_key() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9+/=]{42,60}$ ]]
}

normalize_csv_list() {
  local value="$1"
  value="${value//,/ }"
  local -a parts=()
  IFS=' ' read -r -a parts <<<"$value"
  printf '%s' "${parts[*]}"
}

to_config_csv() {
  local value="$1"
  local normalized token out=""
  normalized="$(normalize_csv_list "$value")"
  for token in $normalized; do
    if [[ -z "$out" ]]; then
      out="$token"
    else
      out="${out}, ${token}"
    fi
  done
  printf '%s' "$out"
}

validate_wg_allowed_ips() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  local normalized token
  normalized="$(normalize_csv_list "$value")"
  for token in $normalized; do
    if ! validate_ipv4_cidr "$token"; then
      return 1
    fi
  done
  return 0
}

validate_wg_dns_list() {
  local value="$1"
  [[ -z "$value" ]] && return 0
  local normalized token
  normalized="$(normalize_csv_list "$value")"
  for token in $normalized; do
    if validate_ipv4 "$token"; then
      continue
    fi
    if [[ ! "$token" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      return 1
    fi
  done
  return 0
}

module_plan() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local wg_address="${WG_ADDRESS:-<prompt>}"
  local wg_confirm="${WG_CONFIRM:-0}"
  local wg_test="${WG_TEST:-ask}"
  local endpoint_host="${WG_ENDPOINT_HOST:-vpn.cocoit.cz}"
  local endpoint_port="${WG_ENDPOINT_PORT:-13231}"
  local allowed_ips="${WG_ALLOWED_IPS:-192.168.70.0/24}"
  local keepalive="${WG_PERSISTENT_KEEPALIVE:-25}"
  local dns="${WG_DNS:-<none>}"

  echo "Plan: install WireGuard package and configure ${wg_iface}"
  echo "Plan: address=${wg_address}, endpoint=${endpoint_host}:${endpoint_port}, auto-confirm=${wg_confirm}, test=${wg_test}"
  echo "Plan: allowed_ips=${allowed_ips}, keepalive=${keepalive}, dns=${dns}"
}

module_apply() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local wg_address="${WG_ADDRESS:-}"
  local wg_confirm="${WG_CONFIRM:-0}"
  local wg_test="${WG_TEST:-ask}"

  local endpoint_host="${WG_ENDPOINT_HOST:-vpn.cocoit.cz}"
  local endpoint_port="${WG_ENDPOINT_PORT:-13231}"
  local peer_pubkey="${WG_PEER_PUBLIC_KEY:-UG3ZXlRKMuNkzpsHDrknr7KGu7BTmSANgDvBP6yjSGI=}"
  local allowed_ips_raw="${WG_ALLOWED_IPS:-192.168.70.0/24}"
  local keepalive="${WG_PERSISTENT_KEEPALIVE:-25}"
  local wg_dns_raw="${WG_DNS:-}"
  local allowed_ips dns
  local dns_line=""

  allowed_ips="$(to_config_csv "$allowed_ips_raw")"
  dns="$(to_config_csv "$wg_dns_raw")"

  if ! validate_interface_name "$wg_iface"; then
    echo "ERROR: invalid WG_INTERFACE='$wg_iface'" >&2
    exit 1
  fi
  if ! validate_bool_01 "$wg_confirm"; then
    echo "ERROR: invalid WG_CONFIRM='$wg_confirm' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_wg_endpoint_host "$endpoint_host"; then
    echo "ERROR: invalid WG_ENDPOINT_HOST='$endpoint_host' (expected hostname or IPv4)" >&2
    exit 1
  fi
  if ! validate_port "$endpoint_port"; then
    echo "ERROR: invalid WG_ENDPOINT_PORT='$endpoint_port' (expected TCP/UDP port 1-65535)" >&2
    exit 1
  fi
  if ! validate_wg_public_key "$peer_pubkey"; then
    echo "ERROR: invalid WG_PEER_PUBLIC_KEY format" >&2
    exit 1
  fi
  if ! validate_wg_allowed_ips "$allowed_ips"; then
    echo "ERROR: invalid WG_ALLOWED_IPS='$allowed_ips_raw' (expected IPv4/CIDR list)" >&2
    exit 1
  fi
  if [[ ! "$keepalive" =~ ^[0-9]+$ ]] || ((keepalive < 0 || keepalive > 65535)); then
    echo "ERROR: invalid WG_PERSISTENT_KEEPALIVE='$keepalive' (expected 0-65535)" >&2
    exit 1
  fi
  if ! validate_wg_dns_list "$dns"; then
    echo "ERROR: invalid WG_DNS='$wg_dns_raw' (expected IPv4/hostname list)" >&2
    exit 1
  fi
  if [[ -n "$dns" ]]; then
    dns_line="DNS = ${dns}"
  fi
  case "$wg_test" in
  ask | 0 | 1) ;;
  *)
    echo "ERROR: invalid WG_TEST='$wg_test' (expected ask, 0, or 1)" >&2
    exit 1
    ;;
  esac

  require_cmd apt-get systemctl

  local priv_key_path pub_key_path conf_path
  priv_key_path="/etc/wireguard/${wg_iface}.key"
  pub_key_path="/etc/wireguard/${wg_iface}.pub"
  conf_path="/etc/wireguard/${wg_iface}.conf"

  echo "Installing WireGuard packages"
  apt_update_once
  apt-get -y -qq install wireguard >/dev/null
  require_cmd wg

  install -d -m 0700 /etc/wireguard

  if [[ ! -f "${priv_key_path}" ]]; then
    umask 077
    wg genkey | tee "${priv_key_path}" >/dev/null
    wg pubkey <"${priv_key_path}" >"${pub_key_path}"
  fi

  local pub_key
  pub_key="$(cat "${pub_key_path}")"
  if [[ -t 0 || -r /dev/tty ]]; then
    printf "WireGuard public key for this peer:\n%s\n" "${pub_key}" >/dev/tty
  else
    echo "WireGuard public key for this peer:"
    echo "${pub_key}"
  fi

  if [[ -z "${wg_address}" ]]; then
    wg_address="$(prompt_wireguard "WireGuard local interface address for this peer (e.g. 192.168.70.10/32): " || true)"
  fi
  if [[ -z "${wg_address}" ]]; then
    echo "ERROR: WG_ADDRESS is required (set WG_ADDRESS or run with a TTY)" >&2
    exit 1
  fi
  if ! validate_ipv4_cidr "$wg_address"; then
    echo "ERROR: invalid WG_ADDRESS='$wg_address' (expected IPv4/CIDR)" >&2
    exit 1
  fi

  if [[ "$wg_confirm" != "1" && ! -t 0 && ! -r /dev/tty ]]; then
    echo "ERROR: non-interactive run requires WG_CONFIRM=1 (or provide a TTY)" >&2
    exit 1
  fi

  if [[ "$wg_confirm" != "1" ]]; then
    local confirm
    confirm="$(prompt_wireguard "Use address '${wg_address}'? [y/N]: " || true)"
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  cat <<EOF | safe_write_file "$conf_path" 0600 root root
[Interface]
Address = ${wg_address}
PrivateKey = $(cat "${priv_key_path}")
${dns_line}

[Peer]
PublicKey = ${peer_pubkey}
AllowedIPs = ${allowed_ips}
Endpoint = ${endpoint_host}:${endpoint_port}
PersistentKeepalive = ${keepalive}
EOF

  systemctl enable --now "wg-quick@${wg_iface}"

  local run_test="0"
  if [[ "$wg_test" == "1" ]]; then
    run_test="1"
  elif [[ "$wg_test" == "ask" ]]; then
    local test_confirm=""
    test_confirm="$(prompt_wireguard "Test connection now (ping gateway)? [y/N]: " || true)"
    if [[ "${test_confirm}" == "y" || "${test_confirm}" == "Y" ]]; then
      run_test="1"
    fi
  fi

  if [[ "$run_test" == "1" ]]; then
    local base_ip gateway_ip
    base_ip="${wg_address%%/*}"
    gateway_ip="${base_ip%.*}.1"
    echo "Pinging gateway ${gateway_ip}"
    ping -c 3 -W 2 "${gateway_ip}"
  fi

  echo "OK: WireGuard configured (${wg_iface}, ${wg_address} -> ${endpoint_host}:${endpoint_port})"
}

module_verify() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local conf_path="/etc/wireguard/${wg_iface}.conf"

  if [[ ! -s "$conf_path" ]]; then
    echo "ERROR: missing WireGuard config: ${conf_path}" >&2
    exit 1
  fi

  if ! systemctl is-active --quiet "wg-quick@${wg_iface}"; then
    echo "ERROR: WireGuard service not active (wg-quick@${wg_iface})" >&2
    exit 1
  fi

  if ! wg show "$wg_iface" >/dev/null 2>&1; then
    echo "ERROR: wg show failed for interface ${wg_iface}" >&2
    exit 1
  fi

  echo "OK: WireGuard verify passed (${wg_iface})"
}
