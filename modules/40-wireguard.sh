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
      printf "%s" "$message" > /dev/tty
      read -r reply
    elif [[ -r /dev/tty ]]; then
      printf "%s" "$message" > /dev/tty
      read -r reply < /dev/tty
    else
      return 1
    fi
    printf '%s' "$reply"
  }

  add_ufw_rules() {
    local subnet="$1"
    if command -v ufw >/dev/null 2>&1; then
      if ufw status | grep -qi "active"; then
        ufw allow from "${subnet}" to any port 22 proto tcp
        ufw allow from "${subnet}" to any port 10000 proto tcp
      fi
    fi
  }

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

  echo "WireGuard public key for this server:"
  cat "${pub_key_path}"

  if [[ -z "${wg_address}" ]]; then
    wg_address="$(prompt "WireGuard IP address for this server (e.g. 192.168.70.10/32): ")"
  fi
  if [[ -z "${wg_address}" ]]; then
    echo "ERROR: WG_ADDRESS is required (set WG_ADDRESS or run with a TTY)" >&2
    exit 1
  fi

  local confirm
  confirm="$(prompt "Use address '${wg_address}'? [y/N]: ")"
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
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

  local test_confirm=""
  test_confirm="$(prompt "Test connection now (ping gateway)? [y/N]: ")"
  if [[ "${test_confirm}" == "y" || "${test_confirm}" == "Y" ]]; then
    local base_ip gateway_ip
    base_ip="${wg_address%%/*}"
    if [[ "${base_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      gateway_ip="${base_ip%.*}.1"
      echo "Pinging gateway ${gateway_ip}"
      if ! ping -c 3 -W 2 "${gateway_ip}"; then
        echo "ERROR: ping to ${gateway_ip} failed" >&2
        exit 1
      fi
    else
      echo "WARN: cannot derive gateway from address '${wg_address}', skipping ping" >&2
    fi
  fi
  add_ufw_rules "${allowed_ips}"
  echo "OK: WireGuard configured (${wg_iface}, ${wg_address} -> ${endpoint_host}:${endpoint_port})"
}
