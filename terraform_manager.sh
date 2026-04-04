#!/bin/bash

# ==============================================================================
# Script Name : terraform_manager.sh
# Description : Interactive script to install, manage, and configure Terraform 
#               on Linux systems (Ubuntu/Debian & RHEL/CentOS/Amazon Linux).
# Author      : Ankit Srivastava
# Linkedin    : https://www.linkedin.com/in/ankitsrivas/
# Reference   : https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
# ==============================================================================

# --- AUTO-PERMISSION CHECK ---
# If the script is run via 'bash' but doesn't have execute permissions yet, 
# it will add them automatically for future use.
SCRIPT_PATH=$(realpath "$0")
if [ ! -x "$SCRIPT_PATH" ]; then
    echo -e "[INFO] Adding execute permissions to the script for future runs..."
    chmod +x "$SCRIPT_PATH"
    echo -e "[INFO] Permissions updated! In the future, you can just run: ./$(basename "$0")\n"
fi
# -----------------------------

# Function to display the interactive menu
show_menu() {
    echo "==================================================="
    echo "       Terraform Configuration & Management Tool     "
    echo "==================================================="
    echo "Please select an option:"
    echo "  1) Install Terraform (Ubuntu / Debian)"
    echo "  2) Install Terraform (RHEL / CentOS / Amazon Linux)"
    echo "  3) Check Terraform Version"
    echo "  4) Uninstall Terraform"
    echo "  5) Exit"
    echo "==================================================="
    read -p "Enter your choice (1-5): " choice
}

# Function to install Terraform on Ubuntu/Debian
install_ubuntu() {
    echo -e "\n[INFO] Starting Terraform installation for Ubuntu/Debian..."
    
    # Ensure system is up to date and dependencies are installed
    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common wget curl
    
    # Install the HashiCorp GPG key
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | \
        sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    
    # Add the official HashiCorp repository
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    # Update and install Terraform
    sudo apt-get update
    sudo apt-get install terraform -y
    
    echo -e "\n[SUCCESS] Terraform installation completed successfully!"
    terraform -version
}

# Function to install Terraform on RHEL/CentOS/Amazon Linux
install_rhel() {
    echo -e "\n[INFO] Starting Terraform installation for RHEL/CentOS/Amazon Linux..."
    
    # Install yum-utils
    sudo yum install -y yum-utils
    
    # Add HashiCorp repository
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    
    # Install Terraform
    sudo yum -y install terraform
    
    echo -e "\n[SUCCESS] Terraform installation completed successfully!"
    terraform -version
}

# Function to uninstall Terraform
uninstall_terraform() {
    echo -e "\n[INFO] Uninstalling Terraform..."
    
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu uninstallation
        sudo apt-get remove --purge -y terraform
        sudo rm -f /etc/apt/sources.list.d/hashicorp.list
        sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
        sudo apt-get update
        echo -e "[SUCCESS] Terraform removed from Ubuntu/Debian system."
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS uninstallation
        sudo yum remove -y terraform
        sudo rm -f /etc/yum.repos.d/hashicorp.repo
        echo -e "[SUCCESS] Terraform removed from RHEL/CentOS system."
    else
        echo -e "[ERROR] Package manager not found. Please uninstall manually."
    fi
}

# Main script logic
while true; do
    show_menu
    case $choice in
        1) install_ubuntu ;;
        2) install_rhel ;;
        3)
            echo -e "\n[INFO] Checking Terraform version..."
            if command -v terraform &> /dev/null; then
                terraform -version
            else
                echo -e "[WARNING] Terraform is not currently installed on this system."
            fi
            ;;
        4) uninstall_terraform ;;
        5)
            echo -e "\nExiting Terraform Management Tool. Have a great day!"
            exit 0
            ;;
        *) echo -e "\n[ERROR] Invalid option selected. Please choose a valid number (1-5)." ;;
    esac
    echo "" # Blank line for readability
done
