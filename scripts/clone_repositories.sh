#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SSH_DIR="${HOME}/.ssh"
REPOS_DIR="/workspace/repos"

# --- Helper Functions ---

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"
}

install_dependencies() {
  log "Installing dependencies..."
  apt-get update -qq && apt-get install -y -qq jq openssh-client
}

setup_ssh() {
  log "Setting up SSH configuration..."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  # Fetch SSH key from Secret Manager
  gcloud secrets versions access latest --secret="${_SSH_KEY_SECRET}" > "${SSH_DIR}/id_rsa"
  chmod 600 "${SSH_DIR}/id_rsa"

  # Add known hosts
  for host in github.com gitlab.com bitbucket.org; do
    ssh-keyscan -H "$host" >> "${SSH_DIR}/known_hosts" 2>/dev/null || true
  done

  export GIT_SSH_COMMAND="ssh -i ${SSH_DIR}/id_rsa -o StrictHostKeyChecking=no"
}

clone_repositories() {
  mkdir -p "${REPOS_DIR}"

  log "Starting repository cloning..."
  echo "${_REPOSITORIES}" | jq -c '.[]' | while read -r repo; do
    name=$(echo "$repo" | jq -r '.name')
    url=$(echo "$repo" | jq -r '.url')
    branch=$(echo "$repo" | jq -r '.branch')

    log "Cloning: $name (branch: $branch)"
    git clone --branch "$branch" --depth 1 "$url" "${REPOS_DIR}/${name}"
  done
}

# --- Main Execution ---
install_dependencies
setup_ssh
clone_repositories

log "All repositories cloned successfully."
