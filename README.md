# server-bootstrap

Bootstrap for fresh Ubuntu servers. Provides a modular CLI to install and
configure core services (SSH keys, Webmin, Docker, WireGuard) with interactive
selection by default.

## Highlights

- Run from a local clone or directly via curl
- Interactive module selection (default)
- Run specific modules by ID when you know what you want

## Quick start (interactive)

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --
```

Short form (interactive only, no extra args):

```bash
sudo bash -c "$(curl -fsSL https://bootstrap.cocoit.cz)"
```

## Requirements

- Ubuntu + systemd
- `sudo` access
- Internet access for package installs

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

## Module overview

| Module ID | Purpose | Key env vars |
| --- | --- | --- |
| `ssh-keys` | Sync `authorized_keys` from GitHub via systemd timer. | `GH_USER`, `USERNAME`, `INTERVAL_MIN` |
| `webmin` | Install Webmin and verify service is running. | `WEBMIN_PORT` |
| `docker` | Install Docker Engine + Compose plugin and run hello-world by default. | `DOCKER_HELLO=0` |
| `wireguard` | Interactive WireGuard client to `vpn.cocoit.cz`. | `WG_ADDRESS`, `WG_INTERFACE` |

## Module details

### ssh-keys

Sync authorized_keys from GitHub and keep them updated via systemd timer.

- Default GitHub user is `mondychan`
- Override with `GH_USER=yourname`
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

Prompts for server IP address in the tunnel, prints the public key for the VPN
concentrator, and optionally pings the gateway to test the connection.

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
- Modules are designed for Ubuntu and systemd.
