#!/usr/bin/env bash
set -euo pipefail

module_id="ssh-keys"
module_desc="Sync authorized_keys from GitHub via systemd timer (root by default)"

module_run() {
  local gh_user="${GH_USER:-}"
  local target_user="${USERNAME:-root}"
  local interval_min="${INTERVAL_MIN:-15}"

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

  echo "OK: ${service_name} + ${timer_name} installed (GH_USER=${gh_user}, USERNAME=${target_user}, INTERVAL_MIN=${interval_min})"
  echo "Check: journalctl -u ${service_name} -n 50 --no-pager"
}
