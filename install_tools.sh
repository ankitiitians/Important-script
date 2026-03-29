#!/bin/bash
# =============================================================================
# Script Name : install_tools.sh
# Description : Installs Docker, Kind (v0.31.0), and kubectl on a Debian/Ubuntu
#               based Linux system. Detects system architecture automatically
#               and handles both x86_64 and aarch64 (ARM64) platforms.
#
# Usage       : chmod +x install_tools.sh && ./install_tools.sh
#
# Requirements:
#   - Debian/Ubuntu-based Linux distribution
#   - sudo privileges
#   - Internet access
#
# Notes:
#   - Kind version is pinned to v0.31.0 as specified.
#   - kubectl is installed at the latest stable release automatically.
#   - After Docker installation, a logout/login (or newgrp docker) is required
#     for the docker group membership to take effect in the current shell.
# =============================================================================

set -e          # Exit immediately if any command exits with a non-zero status
set -o pipefail # Treat pipeline errors as fatal (catches failures mid-pipe)
set -u          # Treat unset variables as errors

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

KIND_VERSION="v0.31.0"
KIND_INSTALL_PATH="/usr/local/bin/kind"
KUBECTL_INSTALL_PATH="/usr/local/bin/kubectl"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# Print a section header for visual separation in log output
print_section() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
}

# Print an informational message with a consistent prefix
info() {
    echo "[INFO]  $1"
}

# Print an error message and exit with a non-zero status
error_exit() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Detect the system architecture and return the normalized value.
# Supported values: x86_64, aarch64
# Exits with an error if the architecture is not supported.
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64 | arm64)
            echo "aarch64"
            ;;
        *)
            error_exit "Unsupported architecture: ${arch}. Only x86_64 and aarch64 are supported."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Section 1: Install Docker
# -----------------------------------------------------------------------------
# Installs the docker.io package from the distribution's default package
# repository. Adds the current user to the 'docker' group so that Docker
# commands can be run without sudo. A re-login is required for this change
# to take effect in the current shell session.
# -----------------------------------------------------------------------------

print_section "Step 1 of 3 -- Docker Installation"

if command -v docker &>/dev/null; then
    info "Docker is already installed. Skipping installation."
    docker --version
else
    info "Docker not found. Proceeding with installation..."

    info "Updating package index..."
    sudo apt-get update -y

    info "Installing docker.io package..."
    sudo apt-get install -y docker.io

    info "Adding current user '${USER}' to the 'docker' group..."
    sudo usermod -aG docker "$USER"

    info "Enabling and starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl start docker

    info "Docker installation complete."
    info "NOTE: You must log out and log back in (or run 'newgrp docker') for"
    info "      the group membership change to take effect in the current shell."
fi

# -----------------------------------------------------------------------------
# Section 2: Install Kind v0.31.0
# -----------------------------------------------------------------------------
# Kind (Kubernetes IN Docker) is used to run local Kubernetes clusters using
# Docker containers as nodes. The binary is downloaded directly from the
# official Kind GitHub releases and placed in /usr/local/bin.
#
# Release page: https://github.com/kubernetes-sigs/kind/releases/tag/v0.31.0
# -----------------------------------------------------------------------------

print_section "Step 2 of 3 -- Kind ${KIND_VERSION} Installation"

if command -v kind &>/dev/null; then
    info "Kind is already installed. Skipping installation."
    kind --version
else
    info "Kind not found. Proceeding with installation of ${KIND_VERSION}..."

    ARCH=$(detect_arch)
    info "Detected architecture: ${ARCH}"

    # Construct the download URL based on architecture
    if [ "$ARCH" = "x86_64" ]; then
        KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-arm64"
    fi

    info "Downloading Kind from: ${KIND_URL}"
    curl --fail --location --progress-bar --output ./kind "$KIND_URL"

    info "Setting executable permissions on Kind binary..."
    chmod +x ./kind

    info "Moving Kind binary to ${KIND_INSTALL_PATH}..."
    sudo mv ./kind "$KIND_INSTALL_PATH"

    info "Kind ${KIND_VERSION} installation complete."
fi

# -----------------------------------------------------------------------------
# Section 3: Install kubectl (latest stable)
# -----------------------------------------------------------------------------
# kubectl is the Kubernetes command-line tool used to communicate with cluster
# control planes. The latest stable release version is resolved dynamically at
# runtime from the official Kubernetes release channel endpoint, ensuring the
# most current stable version is always installed.
# -----------------------------------------------------------------------------

print_section "Step 3 of 3 -- kubectl Installation"

if command -v kubectl &>/dev/null; then
    info "kubectl is already installed. Skipping installation."
    kubectl version --client --output=yaml
else
    info "kubectl not found. Resolving latest stable version..."

    # Fetch the latest stable release version string (e.g., "v1.32.1")
    KUBECTL_VERSION=$(curl --fail --silent --location https://dl.k8s.io/release/stable.txt)

    if [ -z "$KUBECTL_VERSION" ]; then
        error_exit "Failed to resolve the latest stable kubectl version. Check your internet connection."
    fi

    info "Latest stable kubectl version: ${KUBECTL_VERSION}"

    ARCH=$(detect_arch)
    info "Detected architecture: ${ARCH}"

    # Construct the download URL based on architecture
    if [ "$ARCH" = "x86_64" ]; then
        KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    elif [ "$ARCH" = "aarch64" ]; then
        KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
    fi

    info "Downloading kubectl from: ${KUBECTL_URL}"
    curl --fail --location --progress-bar --output ./kubectl "$KUBECTL_URL"

    info "Setting executable permissions on kubectl binary..."
    chmod +x ./kubectl

    info "Moving kubectl binary to ${KUBECTL_INSTALL_PATH}..."
    sudo mv ./kubectl "$KUBECTL_INSTALL_PATH"

    info "kubectl ${KUBECTL_VERSION} installation complete."
fi

# -----------------------------------------------------------------------------
# Summary: Confirm Installed Versions
# -----------------------------------------------------------------------------
# Print the installed versions of all three tools to confirm successful
# installation and provide a baseline record of the environment state.
# -----------------------------------------------------------------------------

print_section "Installation Summary"

info "Verifying installed tool versions..."
echo ""

echo "  Docker:"
docker --version

echo ""
echo "  Kind:"
kind --version

echo ""
echo "  kubectl:"
kubectl version --client --output=yaml

echo ""
info "All tools have been installed and verified successfully."
info "Installation complete."
echo ""
