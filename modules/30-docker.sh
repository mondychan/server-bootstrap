#!/usr/bin/env bash
set -euo pipefail

module_id="docker"
module_desc="Install Docker Engine + Compose plugin (Ubuntu via official repo)"

module_run() {
  local hello="${DOCKER_HELLO:-0}"
  local os_id=""
  local codename=""

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

  echo "Removing conflicting packages (if any)"
  dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null \
    | awk '{print $1}' \
    | xargs -r apt-get -y remove

  echo "Adding Docker APT repository"
  apt-get -qq update
  apt-get -y -qq install ca-certificates curl >/dev/null
  # Remove legacy/conflicting Docker repo entries and keys.
  rm -f /etc/apt/sources.list.d/docker.list
  rm -f /etc/apt/sources.list.d/docker.list.save
  rm -f /etc/apt/sources.list.d/docker.sources
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i '/download\.docker\.com\/linux\/ubuntu/d' /etc/apt/sources.list
  fi
  rm -f /usr/share/keyrings/docker-archive-keyring.gpg
  rm -f /usr/share/keyrings/download.docker.com.gpg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  echo "Installing Docker packages"
  apt-get -qq update
  apt-get -y -o Dpkg::Progress-Fancy=1 install \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  if ! systemctl is-active --quiet docker; then
    echo "ERROR: docker service is not active" >&2
    exit 1
  fi

  if [[ "${hello}" == "1" ]]; then
    echo "Running hello-world test"
    docker run --rm hello-world
  fi

  echo "OK: Docker installed (docker, compose plugin)"
}
