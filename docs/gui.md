# TUI and Web GUI Guide

## TUI (Phase A)

Use TUI selectors by enabling:

- `--tui`, or
- `BOOTSTRAP_TUI=1`

Selection fallback order:

1. `gum`
2. `whiptail`
3. plain prompt

Examples:

```bash
sudo BOOTSTRAP_TUI=1 ./main.sh
sudo ./main.sh --tui --plan
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
