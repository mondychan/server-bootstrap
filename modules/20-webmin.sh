#!/usr/bin/env bash
set -euo pipefail

module_id="webmin"
module_desc="Install Webmin and enable the service (default port 10000)"

module_run() {
  local webmin_port="${WEBMIN_PORT:-10000}"
  local os_id=""
  local os_like=""

  detect_wg_subnet() {
    local iface="${WG_INTERFACE:-}"
    local conf allowed_line allowed_ips
    if [[ -z "${iface}" ]] && command -v wg >/dev/null 2>&1; then
      iface="$(wg show interfaces 2>/dev/null | awk '{print $1}')"
    fi
    if [[ -z "${iface}" ]] && [[ -d /etc/wireguard ]]; then
      conf="$(ls /etc/wireguard/*.conf 2>/dev/null | head -n1 || true)"
      if [[ -n "${conf}" ]]; then
        iface="$(basename "${conf}" .conf)"
      fi
    fi
    if [[ -z "${iface}" ]]; then
      return 1
    fi
    conf="/etc/wireguard/${iface}.conf"
    if [[ ! -f "${conf}" ]]; then
      return 1
    fi
    allowed_line="$(grep -m1 -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "${conf}" || true)"
    if [[ -z "${allowed_line}" ]]; then
      return 1
    fi
    allowed_ips="${allowed_line#*=}"
    allowed_ips="${allowed_ips// /}"
    printf '%s' "${allowed_ips%%,*}"
  }

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "Updating package lists"
    apt-get -qq update
    apt-get -y -qq install ca-certificates curl gnupg >/dev/null

    echo "Removing legacy Webmin repo entries"
    # Remove legacy/unsupported Webmin repo definitions (e.g. sarge).
    rm -f /etc/apt/sources.list.d/webmin.list
    rm -f /etc/apt/sources.list.d/webmin.list.save
    rm -f /etc/apt/sources.list.d/webmin.repo
    if [[ -d /etc/apt/sources.list.d ]]; then
      find /etc/apt/sources.list.d -maxdepth 1 -type f -name '*.list' -print0 \
        | xargs -0 -r grep -l 'download\.webmin\.com/download/repository' \
        | xargs -r rm -f
    fi
    if [[ -f /etc/apt/sources.list ]]; then
      sed -i '/download\.webmin\.com\/download\/repository/d' /etc/apt/sources.list
      sed -i '/download\.webmin\.com\/download\/newkey\/repository/d' /etc/apt/sources.list
    fi

    # Official Webmin repo setup script
    local setup_script
    setup_script="$(mktemp)"
    curl -fsSL -o "${setup_script}" https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
    sh "${setup_script}"
    rm -f "${setup_script}"

    echo "Installing Webmin"
    apt-get -qq update
    apt-get -y -o Dpkg::Progress-Fancy=1 install --install-recommends webmin
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    rpm --import https://download.webmin.com/jcameron-key.asc
    cat >/etc/yum.repos.d/webmin.repo <<EOF
[Webmin]
name=Webmin Distribution Neutral
baseurl=https://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=https://download.webmin.com/jcameron-key.asc
EOF
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y webmin
    else
      yum install -y webmin
    fi
  else
    echo "ERROR: unsupported system (no apt-get/dnf/yum detected). ID=${os_id} ID_LIKE=${os_like}" >&2
    exit 1
  fi

  systemctl enable --now webmin

  if [[ "${webmin_port}" != "10000" ]]; then
    if [[ -f /etc/webmin/miniserv.conf ]]; then
      if grep -q '^port=' /etc/webmin/miniserv.conf; then
        sed -i "s/^port=.*/port=${webmin_port}/" /etc/webmin/miniserv.conf
      else
        echo "port=${webmin_port}" >>/etc/webmin/miniserv.conf
      fi
      systemctl restart webmin
    else
      echo "ERROR: /etc/webmin/miniserv.conf not found; cannot set WEBMIN_PORT" >&2
      exit 1
    fi
  fi

  if ! systemctl is-active --quiet webmin; then
    echo "ERROR: webmin service is not active" >&2
    exit 1
  fi

  # Ensure Webmin is reachable over WireGuard when ufw is active.
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qi "active"; then
      local wg_subnet
      wg_subnet="$(detect_wg_subnet || true)"
      if [[ -n "${wg_subnet}" ]]; then
        ufw allow from "${wg_subnet}" to any port 10000 proto tcp
      else
        echo "WARN: could not detect WG subnet; skipped ufw Webmin rule" >&2
      fi
    fi
  fi

  if ! curl -ks --max-time 5 "https://127.0.0.1:${webmin_port}/" >/dev/null 2>&1; then
    echo "ERROR: webmin HTTP check failed on https://127.0.0.1:${webmin_port}/" >&2
    exit 1
  fi

  echo "OK: webmin installed and running on https://<server-ip>:${webmin_port}/"
}
