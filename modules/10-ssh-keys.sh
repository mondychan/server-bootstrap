#!/usr/bin/env bash
# shellcheck disable=SC2034
# Module metadata variables are consumed dynamically by main.sh after sourcing this file.
set -euo pipefail

module_id="ssh-keys"
module_desc="Sync authorized_keys from GitHub via systemd timer (root by default)"
module_env="GH_USER, USERNAME, INTERVAL_MIN, SSH_REQUIRE_SERVER, SSH_AUTO_INSTALL"
module_deps=()

detect_ssh_service_name() {
  local service_name unit_file_list
  unit_file_list="$(
    systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null ||
      systemctl list-unit-files --no-legend --no-pager 2>/dev/null ||
      true
  )"

  for service_name in sshd ssh; do
    if [[ -n "$unit_file_list" ]] &&
      printf '%s\n' "$unit_file_list" | grep -Eq "^${service_name}\\.service[[:space:]]"; then
      printf '%s' "$service_name"
      return 0
    fi
    if systemctl show -p LoadState --value "${service_name}.service" 2>/dev/null | grep -q '^loaded$'; then
      printf '%s' "$service_name"
      return 0
    fi
  done

  return 1
}

ensure_ssh_server_present() {
  local sshd_config="/etc/ssh/sshd_config"
  local missing=()

  if ! command -v sshd >/dev/null 2>&1; then
    missing+=("sshd binary")
  fi
  if [[ ! -f "$sshd_config" ]]; then
    missing+=("$sshd_config")
  fi
  if ! detect_ssh_service_name >/dev/null 2>&1; then
    missing+=("ssh/sshd systemd service")
  fi

  if ((${#missing[@]} > 0)); then
    echo "ERROR: SSH server prerequisites missing: ${missing[*]}" >&2
    echo "ERROR: install openssh-server (or equivalent) before running module 'ssh-keys'" >&2
    return 1
  fi

  return 0
}

install_ssh_server() {
  local os_id=""
  local os_like=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    require_cmd apt-get
    apt_mark_stale
    apt_update_once
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install openssh-server >/dev/null
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y openssh-server
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    yum install -y openssh-server
    return 0
  fi

  echo "ERROR: cannot auto-install SSH server (no apt-get/dnf/yum). ID=${os_id} ID_LIKE=${os_like}" >&2
  return 1
}

resolve_home_dir() {
  local target_user="$1"

  if [[ "$target_user" == "root" ]]; then
    printf '/root'
    return 0
  fi

  local home_dir
  home_dir="$(getent passwd "$target_user" | cut -d: -f6 || true)"
  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    echo "ERROR: cannot resolve home for USERNAME=$target_user" >&2
    return 1
  fi

  printf '%s' "$home_dir"
}

harden_sshd_config() {
  local sshd_config="$1"

  if [[ ! -f "$sshd_config" ]]; then
    echo "WARN: ${sshd_config} not found; skipped SSH hardening" >&2
    return 0
  fi

  local backup
  backup="${sshd_config}.bootstrap.$(date +%Y%m%d%H%M%S).bak"
  cp -a "$sshd_config" "$backup"

  set_config_option "$sshd_config" "PermitRootLogin" "prohibit-password"
  set_config_option "$sshd_config" "PubkeyAuthentication" "yes"
  set_config_option "$sshd_config" "PasswordAuthentication" "no"
  set_config_option "$sshd_config" "ChallengeResponseAuthentication" "no"
  set_config_option "$sshd_config" "KbdInteractiveAuthentication" "no"

  if command -v sshd >/dev/null 2>&1; then
    if ! sshd -t -f "$sshd_config"; then
      cp -a "$backup" "$sshd_config"
      echo "ERROR: sshd config validation failed, restored backup: $backup" >&2
      return 1
    fi
  fi

  local ssh_service_name
  if ssh_service_name="$(detect_ssh_service_name)"; then
    systemctl reload "$ssh_service_name" || systemctl restart "$ssh_service_name"
  else
    echo "WARN: ssh service unit not found; skipped reload" >&2
  fi

  echo "OK: sshd hardened (backup: ${backup})"
}

module_plan() {
  local gh_user="${GH_USER:-mondychan}"
  local target_user="${USERNAME:-root}"
  local interval_min="${INTERVAL_MIN:-15}"
  local ssh_require_server="${SSH_REQUIRE_SERVER:-1}"
  local ssh_auto_install="${SSH_AUTO_INSTALL:-1}"

  echo "Plan: create sync script + systemd timer for GitHub SSH keys"
  echo "Plan: GH_USER=${gh_user}, USERNAME=${target_user}, INTERVAL_MIN=${interval_min}"
  echo "Plan: SSH_REQUIRE_SERVER=${ssh_require_server}, SSH_AUTO_INSTALL=${ssh_auto_install}"
  echo "Plan: enforce SSH key-only login in /etc/ssh/sshd_config with rollback-safe validation"
}

module_apply() {
  local gh_user="${GH_USER:-mondychan}"
  local target_user="${USERNAME:-root}"
  local interval_min="${INTERVAL_MIN:-15}"
  local ssh_require_server="${SSH_REQUIRE_SERVER:-1}"
  local ssh_auto_install="${SSH_AUTO_INSTALL:-1}"
  local sshd_config="/etc/ssh/sshd_config"

  if [[ -z "$gh_user" || ! "$gh_user" =~ ^[a-zA-Z0-9-]{1,39}$ ]]; then
    echo "ERROR: invalid GH_USER='$gh_user' (expected GitHub username)" >&2
    exit 1
  fi
  if ! validate_username "$target_user"; then
    echo "ERROR: invalid USERNAME='$target_user'" >&2
    exit 1
  fi
  if ! validate_positive_int "$interval_min"; then
    echo "ERROR: invalid INTERVAL_MIN='$interval_min' (expected positive integer)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$ssh_require_server"; then
    echo "ERROR: invalid SSH_REQUIRE_SERVER='$ssh_require_server' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$ssh_auto_install"; then
    echo "ERROR: invalid SSH_AUTO_INSTALL='$ssh_auto_install' (expected 0 or 1)" >&2
    exit 1
  fi

  require_cmd curl systemctl install getent diff

  if [[ "$ssh_require_server" == "1" ]]; then
    if ! ensure_ssh_server_present; then
      if [[ "$ssh_auto_install" == "1" ]]; then
        echo "WARN: SSH server missing; attempting automatic installation" >&2
        install_ssh_server
        ensure_ssh_server_present
      else
        echo "ERROR: SSH server missing and SSH_AUTO_INSTALL=0" >&2
        exit 1
      fi
    fi
  fi

  local home_dir
  home_dir="$(resolve_home_dir "$target_user")"

  local ssh_dir auth_keys script_path service_name timer_name
  ssh_dir="${home_dir}/.ssh"
  auth_keys="${ssh_dir}/authorized_keys"

  install -d -m 700 -o "$target_user" -g "$target_user" "$ssh_dir"

  script_path="/usr/local/sbin/sync-${target_user}-authorized-keys.sh"
  service_name="sync-${target_user}-keys.service"
  timer_name="sync-${target_user}-keys.timer"

  cat <<EOF | safe_write_file "$script_path" 0755 root root
#!/bin/sh
set -eu
GH_USER="${gh_user}"
URL="https://github.com/\${GH_USER}.keys"
TMP="\$(mktemp)"

echo "sync-${target_user}-keys: fetching \$URL"

if ! curl -fsSL "\$URL" > "\$TMP"; then
  echo "sync-${target_user}-keys: ERROR curl failed" >&2
  rm -f "\$TMP"
  exit 1
fi

SIZE="\$(wc -c < "\$TMP" | tr -d ' ')"
echo "sync-${target_user}-keys: downloaded \${SIZE} bytes"

if [ "\$SIZE" -eq 0 ]; then
  echo "sync-${target_user}-keys: ERROR empty keys payload (no keys on GitHub?)" >&2
  rm -f "\$TMP"
  exit 1
fi

install -m 600 -o "${target_user}" -g "${target_user}" "\$TMP" "${auth_keys}"
rm -f "\$TMP"

echo "sync-${target_user}-keys: updated ${auth_keys} OK"
EOF

  cat <<EOF | safe_write_file "/etc/systemd/system/${service_name}" 0644 root root
[Unit]
Description=Sync ${target_user} authorized_keys from GitHub

[Service]
Type=oneshot
ExecStart=${script_path}
StandardOutput=journal
StandardError=journal
EOF

  cat <<EOF | safe_write_file "/etc/systemd/system/${timer_name}" 0644 root root
[Unit]
Description=Periodic sync of ${target_user} authorized_keys from GitHub

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval_min}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${timer_name}"
  systemctl start "${service_name}"

  if [[ "$ssh_require_server" == "1" ]]; then
    harden_sshd_config "$sshd_config"
  else
    if ensure_ssh_server_present; then
      harden_sshd_config "$sshd_config"
    else
      echo "WARN: SSH_REQUIRE_SERVER=0 and SSH server missing; skipped SSH hardening" >&2
    fi
  fi

  echo "OK: ${service_name} + ${timer_name} installed (GH_USER=${gh_user}, USERNAME=${target_user}, INTERVAL_MIN=${interval_min})"
}

module_verify() {
  local gh_user="${GH_USER:-mondychan}"
  local target_user="${USERNAME:-root}"
  local ssh_require_server="${SSH_REQUIRE_SERVER:-1}"
  local ssh_auto_install="${SSH_AUTO_INSTALL:-1}"

  if ! validate_bool_01 "$ssh_require_server"; then
    echo "ERROR: invalid SSH_REQUIRE_SERVER='$ssh_require_server' (expected 0 or 1)" >&2
    exit 1
  fi
  if ! validate_bool_01 "$ssh_auto_install"; then
    echo "ERROR: invalid SSH_AUTO_INSTALL='$ssh_auto_install' (expected 0 or 1)" >&2
    exit 1
  fi

  if [[ "$ssh_require_server" == "1" ]]; then
    if ! ensure_ssh_server_present; then
      exit 1
    fi
  fi

  local home_dir script_path service_name timer_name ssh_dir auth_keys
  home_dir="$(resolve_home_dir "$target_user")"
  ssh_dir="${home_dir}/.ssh"
  auth_keys="${ssh_dir}/authorized_keys"

  script_path="/usr/local/sbin/sync-${target_user}-authorized-keys.sh"
  service_name="sync-${target_user}-keys.service"
  timer_name="sync-${target_user}-keys.timer"

  if [[ ! -x "${script_path}" ]]; then
    echo "ERROR: expected script missing or not executable: ${script_path}" >&2
    exit 1
  fi
  if ! systemctl is-enabled --quiet "${timer_name}"; then
    echo "ERROR: timer not enabled: ${timer_name}" >&2
    exit 1
  fi
  if ! systemctl is-active --quiet "${timer_name}"; then
    echo "ERROR: timer not active: ${timer_name}" >&2
    exit 1
  fi

  if ! systemctl start "${service_name}"; then
    echo "ERROR: failed to start service: ${service_name}" >&2
    exit 1
  fi

  if [[ ! -s "${auth_keys}" ]]; then
    echo "ERROR: ${auth_keys} is empty after sync" >&2
    exit 1
  fi

  local verify_tmp
  verify_tmp="$(mktemp)"
  if ! curl -fsSL "https://github.com/${gh_user}.keys" >"${verify_tmp}"; then
    echo "ERROR: failed to fetch https://github.com/${gh_user}.keys for verification" >&2
    rm -f "${verify_tmp}"
    exit 1
  fi
  if ! diff -q "${verify_tmp}" "${auth_keys}" >/dev/null 2>&1; then
    echo "ERROR: ${auth_keys} does not match GitHub keys payload" >&2
    rm -f "${verify_tmp}"
    exit 1
  fi
  rm -f "${verify_tmp}"

  echo "OK: ${service_name} + ${timer_name} verified"
}
