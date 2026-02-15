#!/usr/bin/env bash
set -euo pipefail

module_id="docker"
module_desc="Install Docker Engine + Compose plugin (Ubuntu via official repo)"
module_env="DOCKER_HELLO"
module_deps=()

module_plan() {
  local hello="${DOCKER_HELLO:-1}"
  echo "Plan: remove conflicting Docker packages and legacy repositories"
  echo "Plan: add official Docker APT repo and install docker-ce + compose plugin"
  echo "Plan: run hello-world test=${hello}"
}

module_apply() {
  local hello="${DOCKER_HELLO:-1}"
  local os_id=""
  local codename=""

  if ! validate_bool_01 "$hello"; then
    echo "ERROR: invalid DOCKER_HELLO='$hello' (expected 0 or 1)" >&2
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi

  if [[ "${os_id}" != "ubuntu" ]]; then
    echo "ERROR: docker module currently supports Ubuntu only (ID=${os_id})" >&2
    exit 1
  fi
  if [[ -z "${codename}" ]]; then
    echo "ERROR: could not determine Ubuntu codename" >&2
    exit 1
  fi

  require_cmd apt-get dpkg awk xargs curl systemctl

  echo "Removing conflicting packages (if any)"
  dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null \
    | awk '{print $1}' \
    | xargs -r apt-get -y remove

  echo "Cleaning legacy Docker repo entries"
  rm -f /etc/apt/sources.list.d/docker.list
  rm -f /etc/apt/sources.list.d/docker.list.save
  rm -f /etc/apt/sources.list.d/docker.sources
  rm -f /etc/apt/sources.list.d/download.docker.com.list
  if [[ -d /etc/apt/sources.list.d ]]; then
    find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 \
      | xargs -0 -r grep -l 'download\.docker\.com/linux/ubuntu' \
      | xargs -r rm -f || true
  fi
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i '/download\.docker\.com\/linux\/ubuntu/d' /etc/apt/sources.list
  fi
  rm -f /usr/share/keyrings/docker-archive-keyring.gpg
  rm -f /usr/share/keyrings/download.docker.com.gpg

  echo "Updating package lists"
  apt_update_once
  apt-get -y -qq install ca-certificates curl >/dev/null

  echo "Adding Docker APT repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat <<EOF | safe_write_file /etc/apt/sources.list.d/docker.sources 0644 root root
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  echo "Installing Docker packages"
  SB_APT_UPDATED=0
  apt_update_once

  DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o Dpkg::Progress-Fancy=1 install \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemd_enable_verify docker

  if [[ "${hello}" == "1" ]]; then
    echo "Running hello-world test"
    docker run --rm hello-world
  fi

  echo "OK: Docker installed and running (docker, compose plugin)"
}

module_verify() {
  require_cmd systemctl docker

  if ! systemctl is-active --quiet docker; then
    echo "ERROR: docker service is not active" >&2
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker info check failed" >&2
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin check failed" >&2
    exit 1
  fi

  echo "OK: Docker verify passed"
}
