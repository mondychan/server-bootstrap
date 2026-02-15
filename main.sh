#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_VERSION="0.2.6"
BOOTSTRAP_GIT_HASH="${BOOTSTRAP_GIT_HASH:-dev}"
PINNED_REPO_TARBALL_URL="https://github.com/mondychan/server-bootstrap/archive/refs/tags/v${BOOTSTRAP_VERSION}.tar.gz"
FALLBACK_REPO_TARBALL_URL="https://github.com/mondychan/server-bootstrap/archive/refs/heads/main.tar.gz"

# --- Remote/stdin mode bootstrap ---
if [[ "${BOOTSTRAP_EXTRACTED:-0}" != "1" ]] && [[ -z "${BASH_SOURCE[0]:-}" ]]; then
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT

  TARBALL="${TMPDIR}/bootstrap.tar.gz"
  USER_REPO_TARBALL_URL="${REPO_TARBALL_URL:-}"
  RESOLVED_REPO_TARBALL_URL="${USER_REPO_TARBALL_URL:-${PINNED_REPO_TARBALL_URL}}"

  if ! curl -fsSL "${RESOLVED_REPO_TARBALL_URL}" -o "${TARBALL}" 2>/dev/null; then
    if [[ -z "${USER_REPO_TARBALL_URL}" ]]; then
      echo "WARN: failed pinned tarball (${PINNED_REPO_TARBALL_URL}), falling back to main." >&2
      curl -fsSL "${FALLBACK_REPO_TARBALL_URL}" -o "${TARBALL}" 2>/dev/null
    else
      echo "ERROR: failed to download REPO_TARBALL_URL=${USER_REPO_TARBALL_URL}" >&2
      exit 1
    fi
  fi

  tar -xzf "${TARBALL}" -C "$TMPDIR"
  EXTRACTED_DIR="$(find "$TMPDIR" -maxdepth 1 -type d -name 'server-bootstrap-*' | head -n1)"
  if [[ -z "$EXTRACTED_DIR" ]]; then
    echo "ERROR: could not find extracted repo directory in $TMPDIR" >&2
    exit 1
  fi

  export BOOTSTRAP_EXTRACTED=1
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    exec bash "$EXTRACTED_DIR/main.sh" "$@"
  fi
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E bash "$EXTRACTED_DIR/main.sh" "$@"
  fi

  echo "ERROR: sudo is required when not running as root." >&2
  exit 1
fi

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${BOOTSTRAP_DIR}/modules"
PROFILE_DIR="${BOOTSTRAP_DIR}/profiles"
LIB_DIR="${BOOTSTRAP_DIR}/lib"

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

ACTION="apply"
INTERACTIVE="${BOOTSTRAP_INTERACTIVE:-1}"
USE_TUI="${BOOTSTRAP_TUI:-auto}"
LIST_ONLY=0
LIST_JSON=0
LIST_PROFILES=0
LIST_PROFILES_JSON=0
PROFILE_NAME=""
MODULES_CSV=""
WIZARD_INTRO_SHOWN=0

declare -a POSITIONAL_IDS=()
declare -a MODULE_PATHS=()
declare -a MODULE_IDS=()
declare -a SELECTED_IDS=()
declare -a ORDERED_IDS=()

declare -A MODULE_PATH_BY_ID=()
declare -A MODULE_DESC_BY_ID=()
declare -A MODULE_DEPS_BY_ID=()
declare -A MODULE_ENV_BY_ID=()
declare -A RUN_STATUS_BY_ID=()
declare -A RUN_DETAILS_BY_ID=()

RUN_ID="run-$(date +%Y%m%d%H%M%S)-$$"
RUN_STARTED_AT="$(sb_timestamp_utc)"
LOG_FILE=""
EVENT_LOG_FILE=""
STATE_FILE=""
LOCK_FILE=""
LOCK_HELD=0
LOCK_DIR=""

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./main.sh [module ...]
  sudo ./main.sh --modules docker,wireguard
  sudo ./main.sh --profile prod --modules ssh-keys,webmin
  sudo ./main.sh --plan [module ...]
  sudo ./main.sh --verify [module ...]
  sudo ./main.sh --list
  sudo ./main.sh --list-json
  sudo ./main.sh --list-profiles

Behavior:
  - No modules + interactive mode => prompt selection
  - No modules + BOOTSTRAP_INTERACTIVE=0 => all modules
  - With modules => selected modules + auto dependencies
  - Action defaults to apply (plan -> apply -> verify)

Options:
  --apply                apply selected modules (default)
  --plan                 print planned actions only
  --verify               run verify stage only
  --modules <csv>        comma-separated module IDs
  --profile <name>       load profiles/<name>.env
  --tui                  force TUI selector (gum/whiptail)
  --no-interactive       disable prompts and interactive selection
  --list                 list modules in text format
  --list-json            list modules as JSON
  --list-profiles        list available profiles
  --list-profiles-json   list profiles as JSON
  --help, -h             show this help

Env vars (global):
  BOOTSTRAP_DRY_RUN=1        skip apply stage, keep planning
  BOOTSTRAP_VERBOSE=1        verbose logs
  BOOTSTRAP_INTERACTIVE=0    disable interactive selection
  BOOTSTRAP_TUI=auto|1|0     auto-detect TUI (prefers whiptail), force on/off
  BOOTSTRAP_LOG_DIR=<path>   override log directory
  BOOTSTRAP_STATE_DIR=<path> override state directory
  BOOTSTRAP_LOCK_FILE=<path> override lock file
EOF
}

log_line() {
  local level="$1"
  local message="$2"
  local ts line
  ts="$(sb_timestamp_utc)"
  line="[${ts}] [${level}] ${message}"
  echo "$line"
  if [[ -n "${LOG_FILE}" ]]; then
    printf '%s\n' "$line" >>"${LOG_FILE}" || true
  fi
}

log() { log_line "INFO" "$*"; }
# shellcheck disable=SC2317
warn() { log_line "WARN" "$*"; }
err() { log_line "ERROR" "$*"; }
vlog() {
  if [[ "${BOOTSTRAP_VERBOSE:-0}" == "1" ]]; then
    log_line "VERBOSE" "$*"
  fi
}

emit_event() {
  local event="$1"
  local module_id="${2:-}"
  local status="${3:-}"
  local details="${4:-}"
  local ts
  ts="$(sb_timestamp_utc)"
  [[ -n "${EVENT_LOG_FILE}" ]] || return 0

  printf '{"ts":"%s","run_id":"%s","event":"%s","action":"%s","module":"%s","status":"%s","details":"%s"}\n' \
    "$(json_escape "$ts")" \
    "$(json_escape "$RUN_ID")" \
    "$(json_escape "$event")" \
    "$(json_escape "$ACTION")" \
    "$(json_escape "$module_id")" \
    "$(json_escape "$status")" \
    "$(json_escape "$details")" >>"${EVENT_LOG_FILE}" || true
}

# shellcheck disable=SC2317
cleanup_lock() {
  if [[ "$LOCK_HELD" -eq 1 ]]; then
    flock -u 9 || true
    LOCK_HELD=0
  elif [[ "$LOCK_HELD" -eq 2 ]] && [[ -n "$LOCK_DIR" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

# shellcheck disable=SC2317
cleanup() {
  cleanup_lock
}
trap cleanup EXIT

ensure_writable_dir() {
  local dir="$1"
  if install -d -m 0755 "$dir" 2>/dev/null; then
    return 0
  fi
  return 1
}

setup_logging() {
  local default_log_dir
  if is_root; then
    default_log_dir="/var/log/server-bootstrap"
  else
    default_log_dir="/tmp/server-bootstrap"
  fi

  local chosen_log_dir="${BOOTSTRAP_LOG_DIR:-$default_log_dir}"
  if ! ensure_writable_dir "$chosen_log_dir"; then
    chosen_log_dir="/tmp/server-bootstrap"
    ensure_writable_dir "$chosen_log_dir"
  fi

  LOG_FILE="${chosen_log_dir}/server-bootstrap.log"
  EVENT_LOG_FILE="${chosen_log_dir}/events.jsonl"
  : >"$LOG_FILE"
  : >"$EVENT_LOG_FILE"

  emit_event "run-start" "" "started" "version=${BOOTSTRAP_VERSION} git=${BOOTSTRAP_GIT_HASH}"
  log "Version: ${BOOTSTRAP_VERSION} (${BOOTSTRAP_GIT_HASH})"
  log "Run ID: ${RUN_ID}"
  vlog "Log file: ${LOG_FILE}"
  vlog "Event log: ${EVENT_LOG_FILE}"
}

setup_state_file() {
  local default_state_dir
  if is_root; then
    default_state_dir="/var/lib/server-bootstrap"
  else
    default_state_dir="/tmp/server-bootstrap-state"
  fi

  local chosen_state_dir="${BOOTSTRAP_STATE_DIR:-$default_state_dir}"
  if ! ensure_writable_dir "$chosen_state_dir"; then
    chosen_state_dir="/tmp/server-bootstrap-state"
    ensure_writable_dir "$chosen_state_dir"
  fi

  STATE_FILE="${chosen_state_dir}/state.json"
}

write_state() {
  [[ -n "$STATE_FILE" ]] || return 0

  local ended_at tmp file_profile
  ended_at="$(sb_timestamp_utc)"
  file_profile="${PROFILE_NAME:-default}"
  tmp="$(mktemp "$(dirname "$STATE_FILE")/.state.XXXXXX")"

  {
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "started_at": "%s",\n' "$(json_escape "$RUN_STARTED_AT")"
    printf '  "ended_at": "%s",\n' "$(json_escape "$ended_at")"
    printf '  "version": "%s",\n' "$(json_escape "$BOOTSTRAP_VERSION")"
    printf '  "git_hash": "%s",\n' "$(json_escape "$BOOTSTRAP_GIT_HASH")"
    printf '  "action": "%s",\n' "$(json_escape "$ACTION")"
    printf '  "profile": "%s",\n' "$(json_escape "$file_profile")"
    printf '  "dry_run": %s,\n' "$([[ "${BOOTSTRAP_DRY_RUN:-0}" == "1" ]] && echo true || echo false)"
    printf '  "modules": [\n'

    local idx id status details
    for idx in "${!ORDERED_IDS[@]}"; do
      id="${ORDERED_IDS[$idx]}"
      status="${RUN_STATUS_BY_ID[$id]:-pending}"
      details="${RUN_DETAILS_BY_ID[$id]:-}"
      printf '    {"id":"%s","status":"%s","details":"%s"}' \
        "$(json_escape "$id")" \
        "$(json_escape "$status")" \
        "$(json_escape "$details")"
      if ((idx < ${#ORDERED_IDS[@]} - 1)); then
        printf ','
      fi
      printf '\n'
    done

    printf '  ]\n'
    printf '}\n'
  } >"$tmp"

  mv -f "$tmp" "$STATE_FILE"
  vlog "State written: ${STATE_FILE}"
}

acquire_lock() {
  local default_lock
  local lock_parent
  if is_root; then
    default_lock="/var/lock/server-bootstrap.lock"
  else
    default_lock="/tmp/server-bootstrap.lock"
  fi

  LOCK_FILE="${BOOTSTRAP_LOCK_FILE:-$default_lock}"
  lock_parent="$(dirname "$LOCK_FILE")"
  if [[ ! -d "$lock_parent" ]]; then
    install -d -m 0755 "$lock_parent"
  fi
  if [[ ! -w "$lock_parent" ]]; then
    echo "ERROR: lock directory is not writable: $lock_parent" >&2
    exit 1
  fi

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
      echo "ERROR: another bootstrap run is already active (lock: $LOCK_FILE)" >&2
      exit 1
    fi
    LOCK_HELD=1
    vlog "Acquired lock (flock): ${LOCK_FILE}"
  else
    LOCK_DIR="${LOCK_FILE}.dir"
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "ERROR: another bootstrap run is already active (lock dir: $LOCK_DIR)" >&2
      exit 1
    fi
    LOCK_HELD=2
    vlog "Acquired lock (mkdir): ${LOCK_DIR}"
  fi
}

require_root() {
  if ! is_root; then
    echo "ERROR: run as root (use sudo) for this action." >&2
    exit 1
  fi
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --list-json)
      LIST_JSON=1
      shift
      ;;
    --list-profiles)
      LIST_PROFILES=1
      shift
      ;;
    --list-profiles-json)
      LIST_PROFILES_JSON=1
      shift
      ;;
    --apply)
      ACTION="apply"
      shift
      ;;
    --plan)
      ACTION="plan"
      shift
      ;;
    --verify)
      ACTION="verify"
      shift
      ;;
    --modules)
      [[ $# -ge 2 ]] || {
        echo "ERROR: --modules requires a value" >&2
        exit 2
      }
      MODULES_CSV="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || {
        echo "ERROR: --profile requires a value" >&2
        exit 2
      }
      PROFILE_NAME="$2"
      shift 2
      ;;
    --tui)
      USE_TUI=1
      shift
      ;;
    --no-interactive)
      INTERACTIVE=0
      shift
      ;;
    --)
      shift
      while [[ "$#" -gt 0 ]]; do
        POSITIONAL_IDS+=("$1")
        shift
      done
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      exit 2
      ;;
    *)
      POSITIONAL_IDS+=("$1")
      shift
      ;;
    esac
  done
}

normalize_tui_setting() {
  gum_usable() {
    command -v gum >/dev/null 2>&1 || return 1
    [[ -t 1 ]] || return 1
    [[ -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 1
    return 0
  }

  case "${USE_TUI,,}" in
  1 | true | yes | on)
    if command -v whiptail >/dev/null 2>&1; then
      USE_TUI="whiptail"
    elif gum_usable; then
      USE_TUI="gum"
    else
      USE_TUI="0"
    fi
    ;;
  0 | false | no | off)
    USE_TUI="0"
    ;;
  auto | "")
    if command -v whiptail >/dev/null 2>&1; then
      USE_TUI="whiptail"
    elif gum_usable; then
      USE_TUI="gum"
    else
      USE_TUI="0"
    fi
    ;;
  *)
    echo "ERROR: invalid BOOTSTRAP_TUI value: ${USE_TUI}" >&2
    exit 2
    ;;
  esac
}

discover_module_paths() {
  if [[ ! -d "$MODULE_DIR" ]]; then
    echo "ERROR: module dir not found: $MODULE_DIR" >&2
    exit 1
  fi

  mapfile -t MODULE_PATHS < <(find "$MODULE_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
}

load_module() {
  local path="$1"

  unset -v module_id module_desc module_env
  unset -v module_deps
  unset -f module_run module_plan module_apply module_verify 2>/dev/null || true

  # shellcheck source=/dev/null
  source "$path"

  if [[ -z "${module_id:-}" || -z "${module_desc:-}" ]]; then
    echo "ERROR: module missing module_id/module_desc: $path" >&2
    exit 1
  fi

  if ! declare -F module_apply >/dev/null 2>&1; then
    if declare -F module_run >/dev/null 2>&1; then
      # shellcheck disable=SC2317
      module_apply() { module_run; }
    else
      echo "ERROR: module must define module_apply() or module_run(): $path" >&2
      exit 1
    fi
  fi

  if ! declare -F module_plan >/dev/null 2>&1; then
    # shellcheck disable=SC2317
    module_plan() {
      echo "Plan: ${module_desc}"
    }
  fi

  if ! declare -F module_verify >/dev/null 2>&1; then
    # shellcheck disable=SC2317
    module_verify() { return 0; }
  fi
}

index_modules() {
  discover_module_paths

  MODULE_IDS=()
  MODULE_PATH_BY_ID=()
  MODULE_DESC_BY_ID=()
  MODULE_DEPS_BY_ID=()
  MODULE_ENV_BY_ID=()

  local path deps_text
  for path in "${MODULE_PATHS[@]}"; do
    load_module "$path"

    if [[ -n "${MODULE_PATH_BY_ID[$module_id]:-}" ]]; then
      echo "ERROR: duplicate module_id detected: $module_id" >&2
      exit 1
    fi

    deps_text=""
    # shellcheck disable=SC2154
    if declare -p module_deps >/dev/null 2>&1; then
      # shellcheck disable=SC2154
      deps_text="${module_deps[*]}"
    fi

    MODULE_IDS+=("$module_id")
    MODULE_PATH_BY_ID["$module_id"]="$path"
    MODULE_DESC_BY_ID["$module_id"]="$module_desc"
    MODULE_DEPS_BY_ID["$module_id"]="$deps_text"
    MODULE_ENV_BY_ID["$module_id"]="${module_env:-}"
  done

  if [[ "${#MODULE_IDS[@]}" -eq 0 ]]; then
    echo "ERROR: no modules found in $MODULE_DIR" >&2
    exit 1
  fi
}

list_modules() {
  local id deps
  for id in "${MODULE_IDS[@]}"; do
    deps="${MODULE_DEPS_BY_ID[$id]:-}"
    if [[ -n "$deps" ]]; then
      printf "%-16s %s [deps: %s]\n" "$id" "${MODULE_DESC_BY_ID[$id]}" "$deps"
    else
      printf "%-16s %s\n" "$id" "${MODULE_DESC_BY_ID[$id]}"
    fi
  done
}

list_modules_json() {
  local first=1
  local id deps

  printf '['
  for id in "${MODULE_IDS[@]}"; do
    deps="${MODULE_DEPS_BY_ID[$id]:-}"
    if [[ "$first" -eq 0 ]]; then
      printf ','
    fi
    first=0

    printf '{"id":"%s","desc":"%s","deps":[' \
      "$(json_escape "$id")" \
      "$(json_escape "${MODULE_DESC_BY_ID[$id]}")"

    local dep_first=1 dep
    for dep in $deps; do
      if [[ "$dep_first" -eq 0 ]]; then
        printf ','
      fi
      dep_first=0
      printf '"%s"' "$(json_escape "$dep")"
    done

    printf '],"env":"%s"}' "$(json_escape "${MODULE_ENV_BY_ID[$id]:-}")"
  done
  printf ']\n'
}

discover_profiles() {
  local -n out_ref=$1
  out_ref=()

  if [[ ! -d "$PROFILE_DIR" ]]; then
    return 0
  fi

  local path name
  while IFS= read -r path; do
    name="$(basename "$path")"
    name="${name%.env}"
    out_ref+=("$name")
  done < <(find "$PROFILE_DIR" -maxdepth 1 -type f -name '*.env' | sort)
}

list_profiles() {
  local profiles=()
  discover_profiles profiles
  printf '%s\n' "${profiles[@]}"
}

list_profiles_json() {
  local profiles=()
  discover_profiles profiles

  local first=1 p
  printf '['
  for p in "${profiles[@]}"; do
    if [[ "$first" -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$p")"
  done
  printf ']\n'
}

load_profile() {
  [[ -n "$PROFILE_NAME" ]] || return 0

  if [[ ! "$PROFILE_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "ERROR: invalid profile name: $PROFILE_NAME" >&2
    exit 2
  fi

  local profile_file="${PROFILE_DIR}/${PROFILE_NAME}.env"
  if [[ ! -f "$profile_file" ]]; then
    echo "ERROR: profile not found: $profile_file" >&2
    exit 2
  fi

  vlog "Loading profile: ${profile_file}"
  set -a
  # shellcheck source=/dev/null
  source "$profile_file"
  set +a
}

prompt() {
  local message="$1"
  local reply=""

  if [[ -t 0 ]]; then
    read -r -p "$message" reply
  elif [[ -r /dev/tty ]]; then
    read -r -p "$message" reply </dev/tty
  else
    return 1
  fi
  printf '%s' "$reply"
}

whiptail_backtitle() {
  local profile_label="${PROFILE_NAME:-none}"
  printf 'Server Bootstrap v%s (%s) | Action: %s | Profile: %s | Run: %s' \
    "$BOOTSTRAP_VERSION" "$BOOTSTRAP_GIT_HASH" "$ACTION" "$profile_label" "$RUN_ID"
}

show_whiptail_intro_once() {
  [[ "$USE_TUI" == "whiptail" ]] || return 0
  command -v whiptail >/dev/null 2>&1 || return 0
  [[ "${WIZARD_INTRO_SHOWN:-0}" == "1" ]] && return 0

  local intro_text
  intro_text="$(
    cat <<'EOF'
Automated provisioning wizard for fresh servers.

What this tool does:
- lets you choose a profile with default values (dev/prod/custom)
- lets you choose modules (ssh-keys, webmin, docker, wireguard)
- executes module lifecycle plan -> apply -> verify

Navigation:
- Arrow keys: move in lists
- Space: toggle modules in checklist
- Tab: switch between buttons
- Enter: confirm selection
EOF
  )"

  whiptail \
    --backtitle "$(whiptail_backtitle)" \
    --title "Server Bootstrap Wizard" \
    --msgbox "$intro_text" 19 90 || true
  WIZARD_INTRO_SHOWN=1
}

choose_profile_interactive() {
  [[ -n "$PROFILE_NAME" ]] && return 0

  local profiles=()
  discover_profiles profiles
  [[ "${#profiles[@]}" -eq 0 ]] && return 0

  if [[ "$USE_TUI" == "gum" ]] && command -v gum >/dev/null 2>&1; then
    local profile_lines=()
    local p picked selected_name
    profile_lines+=("none :: No profile (module defaults)")
    for p in "${profiles[@]}"; do
      profile_lines+=("${p} :: Load profiles/${p}.env")
    done

    picked="$(gum choose --header "Select profile" "${profile_lines[@]}")" || {
      echo "Aborted."
      exit 0
    }
    selected_name="${picked%% :: *}"
    if [[ "$selected_name" != "none" ]]; then
      PROFILE_NAME="$selected_name"
    fi
    return 0
  fi

  if [[ "$USE_TUI" == "whiptail" ]] && command -v whiptail >/dev/null 2>&1; then
    show_whiptail_intro_once

    local options=("none" "No profile")
    local p
    for p in "${profiles[@]}"; do
      options+=("$p" "Profile ${p}")
    done

    local menu_text
    menu_text="$(
      cat <<'EOF'
Select configuration profile.

Profile values become defaults for module inputs.
You can still override anything with CLI args or env vars.
EOF
    )"

    local picked
    if picked="$(whiptail \
      --backtitle "$(whiptail_backtitle)" \
      --title "Bootstrap Profile" \
      --menu "$menu_text" 20 90 10 "${options[@]}" \
      3>&1 1>&2 2>&3)"; then
      if [[ "$picked" != "none" ]]; then
        PROFILE_NAME="$picked"
      fi
      return 0
    fi
  fi

  local answer
  answer="$(prompt "Profile (empty=none, options: ${profiles[*]}): " || true)"
  answer="$(trim "$answer")"
  case "${answer,,}" in
  "" | none | no | n | default)
    PROFILE_NAME=""
    return 0
    ;;
  esac
  if [[ -n "$answer" ]]; then
    PROFILE_NAME="$answer"
  fi
}

module_details_text() {
  local id="$1"
  local deps env path
  deps="${MODULE_DEPS_BY_ID[$id]:-}"
  env="${MODULE_ENV_BY_ID[$id]:-none}"
  path="${MODULE_PATH_BY_ID[$id]:-unknown}"

  if [[ -z "$deps" ]]; then
    deps="none"
  fi

  cat <<EOF
Module: ${id}
Description: ${MODULE_DESC_BY_ID[$id]}
Dependencies: ${deps}
Environment: ${env}
Source: ${path}
EOF
}

browse_modules_gum() {
  local lines=()
  local id
  for id in "${MODULE_IDS[@]}"; do
    lines+=("${id} :: ${MODULE_DESC_BY_ID[$id]}")
  done

  while true; do
    local picked
    picked="$(gum choose --header "Browse modules" "${lines[@]}" "back :: Return to selection")" || return 0
    local selected_id="${picked%% :: *}"
    if [[ "$selected_id" == "back" ]]; then
      return 0
    fi

    gum style --border rounded --padding "1 2" --margin "1 0" \
      "$(module_details_text "$selected_id")"
  done
}

show_wizard_banner_gum() {
  gum style --border double --padding "1 2" --margin "1 0" \
    --foreground 86 "Server Bootstrap Wizard"
  gum style --foreground 244 \
    "Use arrows/enter for navigation. Space toggles multi-select."
}

choose_modules_gum() {
  [[ "$USE_TUI" == "gum" ]] || return 1
  command -v gum >/dev/null 2>&1 || return 1

  show_wizard_banner_gum

  local action
  while true; do
    action="$(gum choose --header "What would you like to do?" \
      "Select modules" \
      "Browse module details" \
      "Select all modules" \
      "Cancel")" || {
      echo "Aborted."
      exit 0
    }

    case "$action" in
    "Browse module details")
      browse_modules_gum
      ;;
    "Select all modules")
      SELECTED_IDS=("${MODULE_IDS[@]}")
      return 0
      ;;
    "Cancel")
      echo "Aborted."
      exit 0
      ;;
    "Select modules")
      local lines=()
      local id
      for id in "${MODULE_IDS[@]}"; do
        lines+=("${id} :: ${MODULE_DESC_BY_ID[$id]}")
      done

      local selection
      selection="$(gum choose --no-limit --height 15 --header "Select one or more modules" "${lines[@]}")" || return 1
      [[ -n "$selection" ]] || {
        gum style --foreground 214 "No module selected. Please select at least one."
        continue
      }

      SELECTED_IDS=()
      local line
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        SELECTED_IDS+=("${line%% :: *}")
      done <<<"$selection"

      gum style --foreground 244 "Selected: ${SELECTED_IDS[*]}"
      if gum confirm "Proceed with selected modules?"; then
        return 0
      fi
      ;;
    esac
  done
}

choose_modules_whiptail() {
  [[ "$USE_TUI" == "whiptail" ]] || return 1
  command -v whiptail >/dev/null 2>&1 || return 1
  show_whiptail_intro_once

  local options=()
  local id
  for id in "${MODULE_IDS[@]}"; do
    options+=("$id" "${MODULE_DESC_BY_ID[$id]}" "off")
  done

  local checklist_text
  checklist_text="$(
    cat <<EOF
Select one or more modules to execute.

Profile: ${PROFILE_NAME:-none}
Action: ${ACTION}
Available modules: ${#MODULE_IDS[@]}

Tip: Space toggles modules, Tab switches buttons, Enter confirms.
EOF
  )"

  local raw
  raw="$(whiptail \
    --backtitle "$(whiptail_backtitle)" \
    --title "Module Selection" \
    --checklist "$checklist_text" 24 100 14 "${options[@]}" \
    3>&1 1>&2 2>&3)" || return 1
  raw="${raw//\"/}"
  [[ -n "$raw" ]] || return 1

  read -r -a SELECTED_IDS <<<"$raw"
  return 0
}

choose_modules_prompt() {
  local i choice confirm

  echo "Available modules:"
  for i in "${!MODULE_IDS[@]}"; do
    printf "  %2d) %-16s %s\n" "$((i + 1))" "${MODULE_IDS[$i]}" "${MODULE_DESC_BY_ID[${MODULE_IDS[$i]}]}"
  done

  choice="$(prompt "Select modules (comma-separated numbers, 'all', or empty to cancel): " || true)"
  choice="$(trim "$choice")"
  if [[ -z "$choice" ]]; then
    echo "No modules selected."
    exit 0
  fi

  if [[ "${choice,,}" == "all" || "$choice" == "A" || "$choice" == "a" ]]; then
    SELECTED_IDS=("${MODULE_IDS[@]}")
  else
    local -a tokens=()
    IFS=',' read -r -a tokens <<<"$choice"

    local token idx
    for token in "${tokens[@]}"; do
      token="$(trim "$token")"
      [[ -n "$token" ]] || continue
      if [[ "$token" =~ ^[0-9]+$ ]]; then
        idx=$((token - 1))
        if ((idx >= 0 && idx < ${#MODULE_IDS[@]})); then
          SELECTED_IDS+=("${MODULE_IDS[$idx]}")
        else
          echo "ERROR: invalid selection index: $token" >&2
          exit 2
        fi
      elif [[ -n "${MODULE_PATH_BY_ID[$token]:-}" ]]; then
        SELECTED_IDS+=("$token")
      else
        echo "ERROR: invalid token: $token" >&2
        exit 2
      fi
    done
  fi

  echo "Selected modules: ${SELECTED_IDS[*]}"
  confirm="$(prompt "Proceed? [y/N]: " || true)"
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
}

select_modules_interactive() {
  if [[ "$USE_TUI" == "whiptail" ]]; then
    if choose_modules_whiptail; then
      return 0
    fi
    if choose_modules_gum; then
      return 0
    fi
  else
    if choose_modules_gum; then
      return 0
    fi
    if choose_modules_whiptail; then
      return 0
    fi
  fi
  choose_modules_prompt
}

parse_module_csv() {
  local csv="$1"
  [[ -n "$csv" ]] || return 0

  local -a parts=()
  local token
  IFS=',' read -r -a parts <<<"$csv"
  for token in "${parts[@]}"; do
    token="$(trim "$token")"
    [[ -n "$token" ]] || continue
    SELECTED_IDS+=("$token")
  done
}

dedupe_selected_ids() {
  local -A seen=()
  local -a deduped=()
  local id

  for id in "${SELECTED_IDS[@]}"; do
    [[ -n "$id" ]] || continue
    if [[ -z "${seen[$id]:-}" ]]; then
      deduped+=("$id")
      seen[$id]=1
    fi
  done

  SELECTED_IDS=("${deduped[@]}")
}

resolve_selected_ids() {
  SELECTED_IDS=()

  parse_module_csv "$MODULES_CSV"
  if [[ "${#POSITIONAL_IDS[@]}" -gt 0 ]]; then
    SELECTED_IDS+=("${POSITIONAL_IDS[@]}")
  fi

  if [[ "${#SELECTED_IDS[@]}" -eq 0 ]]; then
    if [[ "$INTERACTIVE" == "1" ]]; then
      choose_profile_interactive
      select_modules_interactive
    else
      SELECTED_IDS=("${MODULE_IDS[@]}")
    fi
  fi

  dedupe_selected_ids

  if [[ "${#SELECTED_IDS[@]}" -eq 0 ]]; then
    echo "ERROR: no modules selected" >&2
    exit 2
  fi

  local id
  for id in "${SELECTED_IDS[@]}"; do
    if [[ -z "${MODULE_PATH_BY_ID[$id]:-}" ]]; then
      echo "ERROR: unknown module: $id" >&2
      echo "Use: ./main.sh --list" >&2
      exit 2
    fi
  done
}

declare -A _visit_state=()

visit_module_dep() {
  local id="$1"

  case "${_visit_state[$id]:-0}" in
  1)
    echo "ERROR: dependency cycle detected near module '$id'" >&2
    exit 2
    ;;
  2)
    return 0
    ;;
  esac

  _visit_state["$id"]=1

  local deps dep
  deps="${MODULE_DEPS_BY_ID[$id]:-}"
  for dep in $deps; do
    if [[ -z "${MODULE_PATH_BY_ID[$dep]:-}" ]]; then
      echo "ERROR: module '$id' depends on unknown module '$dep'" >&2
      exit 2
    fi
    visit_module_dep "$dep"
  done

  _visit_state["$id"]=2
  ORDERED_IDS+=("$id")
}

resolve_dependencies() {
  ORDERED_IDS=()
  _visit_state=()

  local id
  for id in "${SELECTED_IDS[@]}"; do
    visit_module_dep "$id"
  done

  dedupe_ordered_ids
}

dedupe_ordered_ids() {
  local -A seen=()
  local -a deduped=()
  local id
  for id in "${ORDERED_IDS[@]}"; do
    if [[ -z "${seen[$id]:-}" ]]; then
      deduped+=("$id")
      seen[$id]=1
    fi
  done
  ORDERED_IDS=("${deduped[@]}")
}

log_module_output_line() {
  local module_id="$1"
  local line="$2"
  local ts out
  ts="$(sb_timestamp_utc)"
  out="[${ts}] [module:${module_id}] ${line}"
  echo "$out"
  if [[ -n "${LOG_FILE}" ]]; then
    printf '%s\n' "$out" >>"${LOG_FILE}" || true
  fi
}

run_module_function() {
  local module_id="$1"
  local stage="$2"
  local function_name="$3"
  local rc

  log "${module_id}: ${stage}"
  emit_event "module-stage-start" "$module_id" "started" "$stage"

  set +e
  "$function_name" 2>&1 | while IFS= read -r line; do
    log_module_output_line "$module_id" "$line"
  done
  rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -ne 0 ]]; then
    emit_event "module-stage-end" "$module_id" "failed" "$stage rc=${rc}"
    return "$rc"
  fi

  emit_event "module-stage-end" "$module_id" "ok" "$stage"
  return 0
}

run_one_module() {
  local module_id="$1"
  local path
  path="${MODULE_PATH_BY_ID[$module_id]}"

  load_module "$path"

  if ! run_module_function "$module_id" "plan" module_plan; then
    RUN_STATUS_BY_ID["$module_id"]="failed"
    RUN_DETAILS_BY_ID["$module_id"]="plan failed"
    return 1
  fi

  case "$ACTION" in
  plan)
    RUN_STATUS_BY_ID["$module_id"]="planned"
    RUN_DETAILS_BY_ID["$module_id"]="plan complete"
    return 0
    ;;
  apply)
    if [[ "${BOOTSTRAP_DRY_RUN:-0}" == "1" ]]; then
      log "${module_id}: dry-run skip apply/verify"
      RUN_STATUS_BY_ID["$module_id"]="dry-run"
      RUN_DETAILS_BY_ID["$module_id"]="apply skipped"
      emit_event "module-dry-run" "$module_id" "skipped" "apply stage skipped"
      return 0
    fi

    if ! run_module_function "$module_id" "apply" module_apply; then
      RUN_STATUS_BY_ID["$module_id"]="failed"
      RUN_DETAILS_BY_ID["$module_id"]="apply failed"
      return 1
    fi

    if ! run_module_function "$module_id" "verify" module_verify; then
      RUN_STATUS_BY_ID["$module_id"]="failed"
      RUN_DETAILS_BY_ID["$module_id"]="verify failed"
      return 1
    fi

    RUN_STATUS_BY_ID["$module_id"]="ok"
    RUN_DETAILS_BY_ID["$module_id"]="apply+verify complete"
    return 0
    ;;
  verify)
    if ! run_module_function "$module_id" "verify" module_verify; then
      RUN_STATUS_BY_ID["$module_id"]="failed"
      RUN_DETAILS_BY_ID["$module_id"]="verify failed"
      return 1
    fi
    RUN_STATUS_BY_ID["$module_id"]="ok"
    RUN_DETAILS_BY_ID["$module_id"]="verify complete"
    return 0
    ;;
  *)
    echo "ERROR: unsupported action: $ACTION" >&2
    return 2
    ;;
  esac
}

should_require_root() {
  case "$ACTION" in
  plan)
    return 1
    ;;
  verify)
    return 0
    ;;
  apply)
    if [[ "${BOOTSTRAP_DRY_RUN:-0}" == "1" ]]; then
      return 1
    fi
    return 0
    ;;
  esac
  return 1
}

run_modules() {
  local module_id
  local failures=0
  local total="${#ORDERED_IDS[@]}"
  local idx=0

  log "Selected modules: ${SELECTED_IDS[*]}"
  log "Execution order: ${ORDERED_IDS[*]}"
  log "Action: ${ACTION}"
  log "Profile: ${PROFILE_NAME:-default}"
  log "Dry-run: ${BOOTSTRAP_DRY_RUN:-0}"

  for module_id in "${ORDERED_IDS[@]}"; do
    idx=$((idx + 1))
    log "Progress: module ${idx}/${total} (${module_id})"
    if ! run_one_module "$module_id"; then
      failures=$((failures + 1))
      if [[ "${BOOTSTRAP_CONTINUE_ON_ERROR:-0}" != "1" ]]; then
        err "Stopping on first failure (${module_id})."
        break
      fi
    fi
  done

  if ((failures > 0)); then
    emit_event "run-end" "" "failed" "failures=${failures}"
    return 1
  fi

  emit_event "run-end" "" "ok" "modules=${#ORDERED_IDS[@]}"
  return 0
}

main() {
  parse_args "$@"
  normalize_tui_setting
  index_modules

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    list_modules
    exit 0
  fi

  if [[ "$LIST_JSON" -eq 1 ]]; then
    list_modules_json
    exit 0
  fi

  if [[ "$LIST_PROFILES" -eq 1 ]]; then
    list_profiles
    exit 0
  fi

  if [[ "$LIST_PROFILES_JSON" -eq 1 ]]; then
    list_profiles_json
    exit 0
  fi

  resolve_selected_ids
  load_profile
  resolve_dependencies

  if should_require_root; then
    require_root
  fi

  setup_logging
  setup_state_file

  if [[ "$ACTION" == "apply" || "$ACTION" == "verify" ]]; then
    acquire_lock
  fi

  if run_modules; then
    write_state
    log "Completed successfully."
    exit 0
  fi

  write_state
  err "Execution failed."
  exit 1
}

main "$@"
