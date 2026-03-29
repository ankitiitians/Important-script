#!/bin/bash

# ==========================================================
# Script: create_user_interactive.sh
# Description: Interactive script to create user with root access
# ==========================================================

set -e

# -------- CHECK ROOT --------
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root"
  exit 1
fi

echo "--------------------------------------"
echo "Linux User Creation (Interactive Mode)"
echo "--------------------------------------"

# -------- USER INPUT --------
read -p "Enter username: " USERNAME

if [ -z "$USERNAME" ]; then
    echo "Username cannot be empty"
    exit 1
fi

# -------- CHECK IF USER EXISTS --------
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists"
    exit 1
fi

# -------- CREATE USER --------
echo "Creating user..."
useradd -m -s /bin/bash "$USERNAME"

# -------- PASSWORD SETUP --------
read -p "Do you want to set a password? (y/n): " SET_PASS

if [[ "$SET_PASS" == "y" || "$SET_PASS" == "Y" ]]; then
    passwd "$USERNAME"
else
    echo "Skipping password setup"
fi

# -------- SUDO ACCESS --------
read -p "Grant sudo (root) access? (y/n): " SUDO_ACCESS

if [[ "$SUDO_ACCESS" == "y" || "$SUDO_ACCESS" == "Y" ]]; then
    
    if grep -qi "ubuntu\|debian" /etc/os-release; then
        usermod -aG sudo "$USERNAME"
        GROUP="sudo"
    else
        usermod -aG wheel "$USERNAME"
        GROUP="wheel"
    fi

    echo "User added to $GROUP group"

    # -------- PASSWORDLESS SUDO --------
    read -p "Enable passwordless sudo? (y/n): " NOPASS

    if [[ "$NOPASS" == "y" || "$NOPASS" == "Y" ]]; then
        SUDO_FILE="/etc/sudoers.d/$USERNAME"
        echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDO_FILE"
        chmod 440 "$SUDO_FILE"
        echo "Passwordless sudo enabled"
    else
        echo "Password will be required for sudo"
    fi
fi

# -------- SSH SETUP --------
read -p "Setup SSH access using root's authorized_keys? (y/n): " SSH_SETUP

if [[ "$SSH_SETUP" == "y" || "$SSH_SETUP" == "Y" ]]; then
    HOME_DIR="/home/$USERNAME"

    mkdir -p "$HOME_DIR/.ssh"
    cp /root/.ssh/authorized_keys "$HOME_DIR/.ssh/" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || true

    echo "SSH access configured"
fi

# -------- FINAL VALIDATION --------
echo "--------------------------------------"
echo "Validating setup..."
su - "$USERNAME" -c "whoami"

if [[ "$SUDO_ACCESS" == "y" || "$SUDO_ACCESS" == "Y" ]]; then
    su - "$USERNAME" -c "sudo whoami"
fi

echo "--------------------------------------"
echo "User setup completed"
echo "Username: $USERNAME"

if [[ "$SUDO_ACCESS" == "y" || "$SUDO_ACCESS" == "Y" ]]; then
    echo "Sudo access: Enabled"
fi

echo "Login using: ssh $USERNAME@<server-ip>"
echo "--------------------------------------"
