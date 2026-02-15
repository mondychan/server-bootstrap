# TUI and Web GUI Guide

## TUI (Phase A)

Modern TUI is auto-detected by default.

`BOOTSTRAP_TUI` modes:

- `auto` (default): use TUI when available, prefer `whiptail` for compatibility.
- `1`: force TUI mode.
- `0`: force classic prompt mode.

Selection fallback order:

1. `gum`
2. `whiptail`
3. plain prompt

Examples:

```bash
sudo ./main.sh
sudo BOOTSTRAP_TUI=1 ./main.sh
sudo BOOTSTRAP_TUI=0 ./main.sh
sudo ./main.sh --tui --plan
```

When `gum` is available, the wizard provides:

- profile picker
- module browser with details
- multi-select module chooser
- explicit confirmation before execution

If your terminal does not render gum correctly (garbled keys/colors), use:

```bash
sudo BOOTSTRAP_TUI=0 ./main.sh
```

## Web GUI (Phase B)

Local panel backed by the same `main.sh` CLI.

### Start

```bash
python3 gui/server.py --host 127.0.0.1 --port 8089
# open http://127.0.0.1:8089
```

Shortcut script:

```bash
bash gui/start.sh
```

`gui/start.sh` supports:
- `GUI_HOST` (default `127.0.0.1`)
- `GUI_PORT` (default `8089`)

### API endpoints

- `GET /api/health`
- `GET /api/modules`
- `GET /api/profiles`
- `POST /api/run`

`POST /api/run` payload:

```json
{
  "action": "plan",
  "profile": "dev",
  "modules": ["docker", "wireguard"]
}
```

Response includes:
- `ok`
- `exit_code`
- `command`
- `output`

## Security notes

- Keep GUI bound to localhost unless you explicitly secure and reverse-proxy it.
- GUI can trigger `apply`; run with least privilege and controlled access.
