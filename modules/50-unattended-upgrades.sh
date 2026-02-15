#!/usr/bin/env bash
# shellcheck disable=SC2034
# Module metadata variables are consumed dynamically by main.sh after sourcing this file.
set -euo pipefail

module_id="unattended-upgrades"
module_desc="Enable automatic security updates via unattended-upgrades"
module_env="UAU_AUTO_REBOOT, UAU_AUTO_REBOOT_TIME, UAU_REMOVE_UNUSED, UAU_UPDATE_PACKAGE_LISTS, UAU_UNATTENDED_UPGRADE"
module_deps=()

validate_hhmm() {
  local value="$1"
  [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]
}

module_plan() {
  local auto_reboot="${UAU_AUTO_REBOOT:-0}"
  local reboot_time="${UAU_AUTO_REBOOT_TIME:-03:30}"
  local remove_unused="${UAU_REMOVE_UNUSED:-1}"
  local update_lists="${UAU_UPDATE_PACKAGE_LISTS:-1}"
  local unattended_upgrade="${UAU_UNATTENDED_UPGRADE:-1}"

  echo "Plan: install and configure unattended-upgrades for APT-based systems"
  echo "Plan: auto_reboot=${auto_reboot}, reboot_time=${reboot_time}, remove_unused=${remove_unused}"
  echo "Plan: periodic update_lists=${update_lists}, unattended_upgrade=${unattended_upgrade}"
}

module_apply() {
  local auto_reboot="${UAU_AUTO_REBOOT:-0}"
  local reboot_time="${UAU_AUTO_REBOOT_TIME:-03:30}"
  local remove_unused="${UAU_REMOVE_UNUSED:-1}"
  local update_lists="${UAU_UPDATE_PACKAGE_LISTS:-1}"
  local unattended_upgrade="${UAU_UNATTENDED_UPGRADE:-1}"
  local os_id=""
  local os_like=""

  if ! validate_bool_01 "$auto_reboot"; then
    echo "ERROR: invalid UAU_AUTO_REBOOT='${auto_reboot}' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_hhmm "$reboot_time"; then
    echo "ERROR: invalid UAU_AUTO_REBOOT_TIME='${reboot_time}' (expected HH:MM)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$remove_unused"; then
    echo "ERROR: invalid UAU_REMOVE_UNUSED='${remove_unused}' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$update_lists"; then
    echo "ERROR: invalid UAU_UPDATE_PACKAGE_LISTS='${update_lists}' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$unattended_upgrade"; then
    echo "ERROR: invalid UAU_UNATTENDED_UPGRADE='${unattended_upgrade}' (expected 0 or 1)" >&2
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: unattended-upgrades module requires apt-get (ID=${os_id} ID_LIKE=${os_like})" >&2
    exit 1
  fi

  require_cmd apt-get systemctl

  echo "Installing unattended-upgrades"
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt-get -y -qq install unattended-upgrades apt-listchanges >/dev/null

  cat <<EOF | safe_write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 root root
APT::Periodic::Update-Package-Lists "${update_lists}";
APT::Periodic::Unattended-Upgrade "${unattended_upgrade}";
EOF

  cat <<EOF | safe_write_file /etc/apt/apt.conf.d/52bootstrap-unattended-upgrades 0644 root root
Unattended-Upgrade::Automatic-Reboot "${auto_reboot}";
Unattended-Upgrade::Automatic-Reboot-Time "${reboot_time}";
Unattended-Upgrade::Remove-Unused-Dependencies "${remove_unused}";
EOF

  systemctl daemon-reload
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

  echo "OK: unattended-upgrades configured"
}

module_verify() {
  require_cmd dpkg-query

  if ! dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
    echo "ERROR: unattended-upgrades package is not installed" >&2
    exit 1
  fi

  if [[ ! -s /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    echo "ERROR: missing /etc/apt/apt.conf.d/20auto-upgrades" >&2
    exit 1
  fi
  if [[ ! -s /etc/apt/apt.conf.d/52bootstrap-unattended-upgrades ]]; then
    echo "ERROR: missing /etc/apt/apt.conf.d/52bootstrap-unattended-upgrades" >&2
    exit 1
  fi

  if ! grep -q '^APT::Periodic::Unattended-Upgrade' /etc/apt/apt.conf.d/20auto-upgrades; then
    echo "ERROR: unattended-upgrade periodic config is missing" >&2
    exit 1
  fi

  echo "OK: unattended-upgrades verify passed"
}
