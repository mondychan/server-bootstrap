#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2034
# Module metadata variables are consumed dynamically by main.sh after sourcing this file.

module_id="wireguard"
module_desc="Configure WireGuard client to vpn.cocoit.cz"
module_env="WG_INTERFACE, WG_ADDRESS, WG_CONFIRM, WG_TEST"
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

module_plan() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local wg_address="${WG_ADDRESS:-<prompt>}"
  local wg_confirm="${WG_CONFIRM:-0}"
  local wg_test="${WG_TEST:-ask}"

  echo "Plan: install WireGuard package and configure ${wg_iface}"
  echo "Plan: address=${wg_address}, auto-confirm=${wg_confirm}, test=${wg_test}"
}

module_apply() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local wg_address="${WG_ADDRESS:-}"
  local wg_confirm="${WG_CONFIRM:-0}"
  local wg_test="${WG_TEST:-ask}"

  local endpoint_host="vpn.cocoit.cz"
  local endpoint_port="13231"
  local peer_pubkey="UG3ZXlRKMuNkzpsHDrknr7KGu7BTmSANgDvBP6yjSGI="
  local allowed_ips="192.168.70.0/24"

  if ! validate_interface_name "$wg_iface"; then
    echo "ERROR: invalid WG_INTERFACE='$wg_iface'" >&2
    exit 1
  fi
  if ! validate_bool_01 "$wg_confirm"; then
    echo "ERROR: invalid WG_CONFIRM='$wg_confirm' (expected 0 or 1)" >&2
    exit 1
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
    printf "WireGuard public key for this server:\n%s\n" "${pub_key}" >/dev/tty
  else
    echo "WireGuard public key for this server:"
    echo "${pub_key}"
  fi

  if [[ -z "${wg_address}" ]]; then
    wg_address="$(prompt_wireguard "WireGuard IP address for this server (e.g. 192.168.70.10/32): " || true)"
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

[Peer]
PublicKey = ${peer_pubkey}
AllowedIPs = ${allowed_ips}
Endpoint = ${endpoint_host}:${endpoint_port}
PersistentKeepalive = 25
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
