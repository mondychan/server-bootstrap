#!/usr/bin/env bash
set -euo pipefail

HOST="${GUI_HOST:-127.0.0.1}"
PORT="${GUI_PORT:-8089}"

exec python3 "$(dirname "$0")/server.py" --host "$HOST" --port "$PORT"
