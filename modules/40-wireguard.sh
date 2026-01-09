#!/usr/bin/env bash
set -euo pipefail

module_id="wireguard"
module_desc="Configure WireGuard client to vpn.cocoit.cz (interactive IP)"

module_run() {
  local wg_iface="${WG_INTERFACE:-wg0}"
  local wg_address="${WG_ADDRESS:-}"
  local endpoint_host="vpn.cocoit.cz"
  local endpoint_port="13231"
  local peer_pubkey="UG3ZXlRKMuNkzpsHDrknr7KGu7BTmSANgDvBP6yjSGI="
  local allowed_ips="192.168.70.0/24"

  local priv_key_path pub_key_path conf_path
  priv_key_path="/etc/wireguard/${wg_iface}.key"
  pub_key_path="/etc/wireguard/${wg_iface}.pub"
  conf_path="/etc/wireguard/${wg_iface}.conf"

  prompt() {
    local message="$1"
    local reply=""
    if [[ -t 0 ]]; then
      read -r -p "$message" reply
    elif [[ -r /dev/tty ]]; then
      read -r -p "$message" reply < /dev/tty
    else
      return 1
    fi
    printf '%s' "$reply"
  }

  if [[ -z "${wg_address}" ]]; then
    wg_address="$(prompt "WireGuard IP address for this server (e.g. 192.168.70.10/32): ")"
  fi
  if [[ -z "${wg_address}" ]]; then
    echo "ERROR: WG_ADDRESS is required" >&2
    exit 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing WireGuard packages"
    apt-get -qq update
    apt-get -y -qq install wireguard >/dev/null
  else
    echo "ERROR: unsupported system (no apt-get detected)" >&2
    exit 1
  fi

  install -d -m 0700 /etc/wireguard

  if [[ ! -f "${priv_key_path}" ]]; then
    umask 077
    wg genkey | tee "${priv_key_path}" >/dev/null
    wg pubkey < "${priv_key_path}" > "${pub_key_path}"
  fi

  cat >"${conf_path}" <<EOF
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
  if ! systemctl is-active --quiet "wg-quick@${wg_iface}"; then
    echo "ERROR: WireGuard service not active (wg-quick@${wg_iface})" >&2
    exit 1
  fi

  echo "WireGuard public key for this server:"
  cat "${pub_key_path}"
  echo "OK: WireGuard configured (${wg_iface}, ${wg_address} -> ${endpoint_host}:${endpoint_port})"
}
