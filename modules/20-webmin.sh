#!/usr/bin/env bash
set -euo pipefail

module_id="webmin"
module_desc="Install Webmin and enable the service (default port 10000)"
module_env="WEBMIN_PORT, WEBMIN_VERSION, WEBMIN_KEY_SHA256, WEBMIN_STRICT_KEY_CHECK"
module_deps=()

module_plan() {
  local webmin_port="${WEBMIN_PORT:-10000}"
  local webmin_version="${WEBMIN_VERSION:-latest}"
  local strict_key="${WEBMIN_STRICT_KEY_CHECK:-0}"

  echo "Plan: configure official Webmin repository without remote setup script execution"
  echo "Plan: install webmin version=${webmin_version}, port=${webmin_port}, strict_key_check=${strict_key}"
}

setup_webmin_repo_apt() {
  local key_url="https://download.webmin.com/jcameron-key.asc"
  local key_sha_expected="${WEBMIN_KEY_SHA256:-}"
  local strict_key="${WEBMIN_STRICT_KEY_CHECK:-0}"
  local key_tmp key_sha_actual

  if ! validate_bool_01 "$strict_key"; then
    echo "ERROR: invalid WEBMIN_STRICT_KEY_CHECK='$strict_key' (expected 0 or 1)" >&2
    return 1
  fi

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

  install -d -m 0755 /usr/share/keyrings
  key_tmp="$(mktemp)"
  curl -fsSL -o "$key_tmp" "$key_url"

  if [[ -n "$key_sha_expected" ]]; then
    key_sha_actual="$(sha256sum "$key_tmp" | awk '{print $1}')"
    if [[ "$key_sha_actual" != "$key_sha_expected" ]]; then
      echo "ERROR: Webmin key checksum mismatch (expected ${key_sha_expected}, got ${key_sha_actual})" >&2
      rm -f "$key_tmp"
      return 1
    fi
  elif [[ "$strict_key" == "1" ]]; then
    echo "ERROR: WEBMIN_STRICT_KEY_CHECK=1 requires WEBMIN_KEY_SHA256 to be set" >&2
    rm -f "$key_tmp"
    return 1
  else
    echo "WARN: WEBMIN_KEY_SHA256 not set; key is not checksum-pinned" >&2
  fi

  gpg --dearmor <"$key_tmp" >/usr/share/keyrings/webmin.gpg
  rm -f "$key_tmp"

  cat <<EOF | safe_write_file /etc/apt/sources.list.d/webmin.sources 0644 root root
Types: deb
URIs: https://download.webmin.com/download/repository
Suites: sarge
Components: contrib
Signed-By: /usr/share/keyrings/webmin.gpg
EOF
}

module_apply() {
  local webmin_port="${WEBMIN_PORT:-10000}"
  local webmin_version="${WEBMIN_VERSION:-}"
  local os_id=""
  local os_like=""

  if ! validate_port "$webmin_port"; then
    echo "ERROR: invalid WEBMIN_PORT='$webmin_port'" >&2
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    require_cmd apt-get curl gpg systemctl

    echo "Updating package lists"
    apt_update_once
    apt-get -y -qq install ca-certificates curl gnupg >/dev/null

    echo "Configuring Webmin APT repository (pinned key workflow)"
    setup_webmin_repo_apt

    echo "Installing Webmin"
    SB_APT_UPDATED=0
    apt_update_once

    if [[ -n "$webmin_version" ]]; then
      DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Progress-Fancy=1 install --install-recommends "webmin=${webmin_version}"
    else
      DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Progress-Fancy=1 install --install-recommends webmin
    fi
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    require_cmd rpm systemctl curl

    local key_url="https://download.webmin.com/jcameron-key.asc"
    rpm --import "$key_url"
    cat <<EOF | safe_write_file /etc/yum.repos.d/webmin.repo 0644 root root
[Webmin]
name=Webmin Distribution Neutral
baseurl=https://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=${key_url}
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

  echo "OK: webmin installed and configured"
}

module_verify() {
  local webmin_port="${WEBMIN_PORT:-10000}"

  if ! systemctl is-active --quiet webmin; then
    echo "ERROR: webmin service is not active" >&2
    exit 1
  fi

  if ! curl -ks --max-time 5 "https://127.0.0.1:${webmin_port}/" >/dev/null 2>&1; then
    echo "ERROR: webmin HTTP check failed on https://127.0.0.1:${webmin_port}/" >&2
    exit 1
  fi

  echo "OK: webmin verified on https://<server-ip>:${webmin_port}/"
}
