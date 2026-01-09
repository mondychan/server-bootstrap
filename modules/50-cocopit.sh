#!/usr/bin/env bash
set -euo pipefail

module_id="cocopit"
module_desc="Install Cockpit, create cockpit user, restrict UI to WG subnet"

module_run() {
  local wg_iface="${COCOPIT_WG_INTERFACE:-${WG_INTERFACE:-}}"
  local wg_subnet="${COCOPIT_WG_SUBNET:-}"
  local cockpit_user="cockpit"
  local password_len="${COCOPIT_PASSWORD_LEN:-20}"

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

  gen_password() {
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${password_len}"
  }

  if [[ -z "${wg_iface}" ]]; then
    if command -v wg >/dev/null 2>&1; then
      wg_iface="$(wg show interfaces 2>/dev/null | awk '{print $1}')"
    fi
  fi
  if [[ -z "${wg_iface}" ]]; then
    if [[ -d /etc/wireguard ]]; then
      local conf_guess
      conf_guess="$(ls /etc/wireguard/*.conf 2>/dev/null | head -n1)"
      if [[ -n "${conf_guess}" ]]; then
        wg_iface="$(basename "${conf_guess}" .conf)"
      fi
    fi
  fi

  if [[ -z "${wg_iface}" ]]; then
    echo "ERROR: no WireGuard interface found. Run wireguard module first." >&2
    exit 1
  fi

  local wg_conf="/etc/wireguard/${wg_iface}.conf"
  if [[ ! -f "${wg_conf}" ]]; then
    echo "ERROR: WireGuard config not found: ${wg_conf}" >&2
    exit 1
  fi

  if [[ -z "${wg_subnet}" ]]; then
    local allowed_line allowed_ips
    allowed_line="$(grep -m1 -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "${wg_conf}" || true)"
    if [[ -n "${allowed_line}" ]]; then
      allowed_ips="${allowed_line#*=}"
      allowed_ips="${allowed_ips// /}"
      wg_subnet="${allowed_ips%%,*}"
    fi
  fi

  if [[ -n "${wg_subnet}" ]]; then
    local use_subnet
    use_subnet="$(prompt "Detected WG subnet '${wg_subnet}'. Use this? [Y/n]: ")"
    if [[ "${use_subnet}" == "n" || "${use_subnet}" == "N" ]]; then
      wg_subnet=""
    fi
  fi

  if [[ -z "${wg_subnet}" ]]; then
    wg_subnet="$(prompt "WG subnet to allow for Cockpit (e.g. 192.168.70.0/24): ")"
  fi
  if [[ -z "${wg_subnet}" ]]; then
    echo "ERROR: WG subnet is required" >&2
    exit 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing Cockpit"
    apt-get -qq update
    apt-get -y -qq install cockpit >/dev/null
  else
    echo "ERROR: unsupported system (no apt-get detected)" >&2
    exit 1
  fi

  systemctl enable --now cockpit.socket

  if ! command -v ufw >/dev/null 2>&1; then
    echo "ERROR: ufw not found. Install ufw or set COCOPIT_SKIP_UFW=1 to skip." >&2
    if [[ "${COCOPIT_SKIP_UFW:-0}" != "1" ]]; then
      exit 1
    fi
  else
    local ufw_status
    ufw_status="$(ufw status | head -n1 || true)"
    if echo "${ufw_status}" | grep -qi "inactive"; then
      if [[ "${COCOPIT_ALLOW_INACTIVE_UFW:-0}" == "1" ]]; then
        echo "WARN: ufw inactive, skipping firewall rule"
      else
        local enable_ufw
        enable_ufw="$(prompt "UFW is inactive. Enable now? [y/N]: ")"
        if [[ "${enable_ufw}" == "y" || "${enable_ufw}" == "Y" ]]; then
          ufw --force enable
        else
          echo "ERROR: ufw is inactive. Enable it or set COCOPIT_ALLOW_INACTIVE_UFW=1." >&2
          exit 1
        fi
      fi
    else
      if ufw status | grep -qiE '^9090/tcp[[:space:]].*ALLOW IN[[:space:]].*Anywhere'; then
        echo "WARN: existing broad rule allows 9090 from anywhere"
      fi
      ufw allow in on "${wg_iface}" from "${wg_subnet}" to any port 9090 proto tcp
    fi
  fi

  local new_pass
  new_pass="$(gen_password)"

  if id "${cockpit_user}" >/dev/null 2>&1; then
    echo "User '${cockpit_user}' exists; resetting password"
  else
    if command -v adduser >/dev/null 2>&1; then
      adduser --disabled-password --gecos "" "${cockpit_user}" >/dev/null
    else
      useradd -m -s /bin/bash "${cockpit_user}"
    fi
  fi

  echo "${cockpit_user}:${new_pass}" | chpasswd
  usermod -aG sudo "${cockpit_user}"

  local wg_ip
  wg_ip="$(ip -o -4 addr show dev "${wg_iface}" | awk '{print $4}' | head -n1 | cut -d/ -f1 || true)"
  if [[ -n "${wg_ip}" ]]; then
    echo "Cockpit URL: https://${wg_ip}:9090"
  else
    echo "Cockpit URL: https://<server-wg-ip>:9090"
  fi
  echo "Cockpit user: ${cockpit_user}"
  echo "Cockpit password: ${new_pass}"
  echo "OK: Cocopit installed and restricted to ${wg_subnet} on ${wg_iface}"
}
