# server-bootstrap

Bootstrap script for fresh Ubuntu servers. It provides a simple, modular CLI to
install and configure common services (SSH keys, Webmin, Docker, WireGuard).

## What it does

- Runs from a local clone or directly via curl
- Lets you select modules interactively
- Supports running a subset of modules by ID

## Quick start (interactive)

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --
```

Short form:

```bash
sudo bash -c "$(curl -fsSL https://bootstrap.cocoit.cz)"
```

## List modules

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- --list
```

## Run specific modules

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- ssh-keys
```

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- webmin
```

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- docker
```

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s -- wireguard
```

## Run all modules (no prompt)

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo BOOTSTRAP_INTERACTIVE=0 bash -s --
```

## Global environment variables

- `BOOTSTRAP_DRY_RUN=1` print what would run, do not execute
- `BOOTSTRAP_VERBOSE=1` verbose output
- `BOOTSTRAP_INTERACTIVE=0` disable interactive prompt

## Module details

### ssh-keys

Sync authorized_keys from GitHub and keep them updated via systemd timer.

- Default GitHub user is `mondychan`
- Set your own with `GH_USER=yourname`
- Optional: `USERNAME` (default `root`), `INTERVAL_MIN` (default `15`)

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo GH_USER=yourname bash -s -- ssh-keys
```

### webmin

Install Webmin from the official repo and verify the service is running.

Optional:
- `WEBMIN_PORT` (default `10000`)

### docker

Install Docker Engine and Compose plugin from the official repo, and run a
hello-world test by default.

Optional:
- `DOCKER_HELLO=0` to skip hello-world

### wireguard

Interactive WireGuard client setup to `vpn.cocoit.cz`.

Prompts for server IP address in the tunnel. Prints the public key so you can
add it to the VPN concentrator. Optionally pings the gateway to test the
connection.

Optional:
- `WG_ADDRESS` to skip the prompt
- `WG_INTERFACE` (default `wg0`)

## Local usage

```bash
sudo ./main.sh --list
sudo ./main.sh ssh-keys
```

## Notes

- Run as root (`sudo`).
- Script is designed for Ubuntu (Webmin/Docker/WireGuard modules).
