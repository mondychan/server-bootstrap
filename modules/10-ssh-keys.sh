#!/usr/bin/env bash
set -euo pipefail

module_id="ssh-keys"
module_desc="Sync authorized_keys from GitHub via systemd timer (root by default)"

module_run() {
  local gh_user="${GH_USER:-mondychan}"
  local target_user="${USERNAME:-root}"
  local interval_min="${INTERVAL_MIN:-15}"
  local sshd_config="/etc/ssh/sshd_config"

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

  if [[ -z "$gh_user" ]]; then
    echo "ERROR: GH_USER is required for module 'ssh-keys' (e.g. GH_USER=mondychan)." >&2
    exit 1
  fi

  local home_dir ssh_dir auth_keys script_path service_name timer_name

  if [[ "$target_user" == "root" ]]; then
    home_dir="/root"
  else
    home_dir="$(getent passwd "$target_user" | cut -d: -f6 || true)"
    if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
      echo "ERROR: cannot resolve home for USERNAME=$target_user" >&2
      exit 1
    fi
  fi

  ssh_dir="${home_dir}/.ssh"
  auth_keys="${ssh_dir}/authorized_keys"

  install -d -m 700 -o "$target_user" -g "$target_user" "$ssh_dir"

  script_path="/usr/local/sbin/sync-${target_user}-authorized-keys.sh"
  service_name="sync-${target_user}-keys.service"
  timer_name="sync-${target_user}-keys.timer"

  cat >"$script_path" <<EOF
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

  chmod +x "$script_path"

  cat >"/etc/systemd/system/${service_name}" <<EOF
[Unit]
Description=Sync ${target_user} authorized_keys from GitHub

[Service]
Type=oneshot
ExecStart=${script_path}
StandardOutput=journal
StandardError=journal
EOF

  cat >"/etc/systemd/system/${timer_name}" <<EOF
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

  # Enforce key-only SSH for root by default.
  if [[ -f "${sshd_config}" ]]; then
    if grep -qE '^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]' "${sshd_config}"; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin prohibit-password/' "${sshd_config}"
    else
      echo "PermitRootLogin prohibit-password" >> "${sshd_config}"
    fi
    if grep -qE '^[[:space:]]*#?[[:space:]]*PubkeyAuthentication[[:space:]]' "${sshd_config}"; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*PubkeyAuthentication[[:space:]].*/PubkeyAuthentication yes/' "${sshd_config}"
    else
      echo "PubkeyAuthentication yes" >> "${sshd_config}"
    fi
    if grep -qE '^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]' "${sshd_config}"; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication no/' "${sshd_config}"
    else
      echo "PasswordAuthentication no" >> "${sshd_config}"
    fi
    if grep -qE '^[[:space:]]*#?[[:space:]]*ChallengeResponseAuthentication[[:space:]]' "${sshd_config}"; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*ChallengeResponseAuthentication[[:space:]].*/ChallengeResponseAuthentication no/' "${sshd_config}"
    else
      echo "ChallengeResponseAuthentication no" >> "${sshd_config}"
    fi
    if grep -qE '^[[:space:]]*#?[[:space:]]*KbdInteractiveAuthentication[[:space:]]' "${sshd_config}"; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*KbdInteractiveAuthentication[[:space:]].*/KbdInteractiveAuthentication no/' "${sshd_config}"
    else
      echo "KbdInteractiveAuthentication no" >> "${sshd_config}"
    fi

    if systemctl list-unit-files --type=service | grep -q '^sshd\.service'; then
      systemctl reload sshd || systemctl restart sshd
    elif systemctl list-unit-files --type=service | grep -q '^ssh\.service'; then
      systemctl reload ssh || systemctl restart ssh
    else
      echo "WARN: ssh service unit not found; skipped reload" >&2
    fi
  else
    echo "WARN: ${sshd_config} not found; skipped SSH hardening" >&2
  fi

  # Ensure SSH is reachable over WireGuard when ufw is active.
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qi "active"; then
      local wg_subnet
      wg_subnet="$(detect_wg_subnet || true)"
      if [[ -n "${wg_subnet}" ]]; then
        ufw allow from "${wg_subnet}" to any port 22 proto tcp
      else
        echo "WARN: could not detect WG subnet; skipped ufw SSH rule" >&2
      fi
    fi
  fi

  # Post-install verification (best-effort, fail on critical issues)
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

  # Run once and verify authorized_keys got content
  if ! systemctl start "${service_name}"; then
    echo "ERROR: failed to start service: ${service_name}" >&2
    exit 1
  fi
  if [[ ! -s "${auth_keys}" ]]; then
    echo "ERROR: ${auth_keys} is empty after sync" >&2
    exit 1
  fi
  # Verify content matches GitHub keys payload.
  local verify_tmp
  verify_tmp="$(mktemp)"
  if ! curl -fsSL "https://github.com/${gh_user}.keys" > "${verify_tmp}"; then
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

  echo "OK: ${service_name} + ${timer_name} installed and verified (GH_USER=${gh_user}, USERNAME=${target_user}, INTERVAL_MIN=${interval_min})"
}
