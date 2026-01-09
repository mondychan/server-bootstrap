#!/usr/bin/env bash
set -euo pipefail

module_id="webmin"
module_desc="Install Webmin and enable the service (default port 10000)"

module_run() {
  local webmin_port="${WEBMIN_PORT:-10000}"
  local os_id=""
  local os_like=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg

    install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://download.webmin.com/jcameron-key.asc \
      | gpg --dearmor -o /usr/share/keyrings/webmin.gpg

    cat >/etc/apt/sources.list.d/webmin.list <<EOF
deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib
EOF

    apt-get update
    apt-get install -y webmin
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

  if ! curl -ks --max-time 5 "https://127.0.0.1:${webmin_port}/" >/dev/null 2>&1; then
    echo "ERROR: webmin HTTP check failed on https://127.0.0.1:${webmin_port}/" >&2
    exit 1
  fi

  echo "OK: webmin installed and running on https://<server-ip>:${webmin_port}/"
}
