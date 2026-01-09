#!/usr/bin/env bash
set -euo pipefail

# --- Remote/stdin mode bootstrap ---
# When executed via: curl .../main.sh | bash -s -- ...
# BASH_SOURCE can be unset and modules/ directory is not present.
# We fetch the repo tarball into /tmp and re-exec from a real file path.
if [[ "${BOOTSTRAP_EXTRACTED:-0}" != "1" ]]; then
  # If BASH_SOURCE[0] is unavailable or empty, we are likely running from stdin.
  if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    REPO_TARBALL_URL="${REPO_TARBALL_URL:-https://github.com/mondychan/server-bootstrap/archive/refs/heads/main.tar.gz}"
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    curl -fsSL "$REPO_TARBALL_URL" | tar -xz -C "$TMPDIR"

    # The extracted folder is typically: server-bootstrap-main
    EXTRACTED_DIR="$(find "$TMPDIR" -maxdepth 1 -type d -name 'server-bootstrap-*' | head -n1)"
    if [[ -z "$EXTRACTED_DIR" ]]; then
      echo "ERROR: could not find extracted repo directory in $TMPDIR" >&2
      exit 1
    fi

    export BOOTSTRAP_EXTRACTED=1
    exec sudo -E bash "$EXTRACTED_DIR/main.sh" "$@"
  fi
fi

# --- Local file mode continues here ---
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${BOOTSTRAP_DIR}/modules"
BOOTSTRAP_VERSION="2026-01-09.4"
BOOTSTRAP_GIT_HASH="dev"

usage() {
  cat <<'EOF'
Usage:
  sudo ./main.sh [module ...]
  sudo ./main.sh --list
  sudo ./main.sh --help

Behavior:
  - No args      => interactive module selection (default)
  - With args    => runs ONLY selected modules by their ID (e.g. ssh-keys)
  - BOOTSTRAP_INTERACTIVE=0 => run ALL modules (in filename order)

Examples:
  # interactive selection
  curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --

  # run everything (no prompt)
  curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo BOOTSTRAP_INTERACTIVE=0 bash -s --

  # run only ssh-keys
  curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- ssh-keys

  # interactive: select all (type "all" or "A")

Env vars (global):
  BOOTSTRAP_DRY_RUN=1        print what would run, do not execute
  BOOTSTRAP_VERBOSE=1        verbose output
  BOOTSTRAP_INTERACTIVE=0    disable interactive prompt

Module-specific env vars are documented per module (see --list output).
EOF
}

log() { echo "[bootstrap] $*"; }
vlog() { [[ "${BOOTSTRAP_VERBOSE:-0}" == "1" ]] && echo "[bootstrap:verbose] $*" || true; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: run as root (use sudo)." >&2
    exit 1
  fi
}

discover_modules() {
  # outputs absolute paths
  shopt -s nullglob
  local files=("${MODULE_DIR}"/*.sh)
  printf '%s\n' "${files[@]}"
}

# Module interface:
# Each module file, when sourced, must define:
#   module_id, module_desc, module_run
# Where module_run is a function: module_run() { ... }
load_module() {
  local path="$1"

  # reset symbols
  unset -v module_id module_desc
  unset -f module_run 2>/dev/null || true

  # shellcheck source=/dev/null
  source "$path"

  if [[ -z "${module_id:-}" || -z "${module_desc:-}" ]]; then
    echo "ERROR: module missing module_id/module_desc: $path" >&2
    exit 1
  fi
  if ! declare -F module_run >/dev/null; then
    echo "ERROR: module missing module_run(): $path" >&2
    exit 1
  fi
}

list_modules() {
  require_root || true
  local path
  for path in $(discover_modules); do
    load_module "$path"
    printf "%-16s %s\n" "${module_id}" "${module_desc}"
  done
}

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

run_interactive() {
  local -a paths ids descs selected_ids
  local path choice confirm
  local i

  echo "[bootstrap] Version: ${BOOTSTRAP_VERSION} (${BOOTSTRAP_GIT_HASH})"
  for path in $(discover_modules); do
    load_module "$path"
    paths+=("$path")
    ids+=("${module_id}")
    descs+=("${module_desc}")
  done

  if [[ "${#ids[@]}" -eq 0 ]]; then
    echo "ERROR: no modules found" >&2
    exit 1
  fi

  echo "Available modules:"
  for i in "${!ids[@]}"; do
    printf "  %2d) %-16s %s\n" "$((i+1))" "${ids[$i]}" "${descs[$i]}"
  done

  choice="$(prompt "Select modules (comma-separated numbers, 'all', or empty to cancel): ")"
  if [[ -z "${choice}" ]]; then
    echo "No modules selected."
    exit 0
  fi

  if [[ "${choice,,}" == "all" || "${choice}" == "A" || "${choice}" == "a" ]]; then
    selected_ids=("${ids[@]}")
  else
    IFS=', ' read -r -a choice_arr <<< "${choice}"
    for i in "${choice_arr[@]}"; do
      if [[ "$i" =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#ids[@]} )); then
        selected_ids+=("${ids[$((i-1))]}")
      else
        echo "ERROR: invalid selection: ${i}" >&2
        exit 2
      fi
    done
  fi

  echo "Selected modules: ${selected_ids[*]}"
  confirm="$(prompt "Proceed? [y/N]: ")"
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi

  run_selected "${selected_ids[@]}"
}

run_module_by_path() {
  local path="$1"
  load_module "$path"

  if [[ "${BOOTSTRAP_DRY_RUN:-0}" == "1" ]]; then
    log "DRY-RUN: would run '${module_id}' - ${module_desc}"
    return 0
  fi

  log "Running '${module_id}' - ${module_desc}"
  module_run 2>&1 | while IFS= read -r line; do
    echo "[bootstrap:${module_id}] ${line}"
  done
  local rc=${PIPESTATUS[0]}
  if [[ "$rc" -ne 0 ]]; then
    exit "$rc"
  fi
  log "Done '${module_id}'"
}

run_selected() {
  local -a wanted_ids=("$@")
  local found=0
  local path

  for path in $(discover_modules); do
    load_module "$path"
    for wid in "${wanted_ids[@]}"; do
      if [[ "${module_id}" == "$wid" ]]; then
        run_module_by_path "$path"
        found=$((found+1))
      fi
    done
  done

  if [[ "$found" -eq 0 ]]; then
    echo "ERROR: none of requested modules found: ${wanted_ids[*]}" >&2
    echo "Use: sudo ./main.sh --list" >&2
    exit 2
  fi
}

run_all() {
  local path
  for path in $(discover_modules); do
    run_module_by_path "$path"
  done
}

main() {
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --list) list_modules; exit 0 ;;
  esac

  require_root

  if [[ ! -d "$MODULE_DIR" ]]; then
    echo "ERROR: module dir not found: $MODULE_DIR" >&2
    exit 1
  fi

  if [[ "$#" -eq 0 ]]; then
    if [[ "${BOOTSTRAP_INTERACTIVE:-1}" == "1" ]]; then
      run_interactive
    else
      vlog "No module args => run all"
      run_all
    fi
  else
    run_selected "$@"
  fi
}

main "$@"
