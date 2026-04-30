#!/bin/bash

clear
echo "================================================="
echo "      Nextcloud Interactive Manager              "
echo "================================================="
echo "1) Install & Configure Nextcloud"
echo "2) Remove Nextcloud Completely"
echo "3) Exit"
echo "================================================="
read -p "Select an option [1-3]: " MENU_OPTION

# ---------------------------------------------------
# OPTION 2: REMOVE NEXTCLOUD
# ---------------------------------------------------
if [ "$MENU_OPTION" == "2" ]; then
    echo ""
    echo "================================================="
    echo "               DANGER ZONE                       "
    echo "================================================="
    read -p "Are you absolutely sure you want to remove Nextcloud? (y/n): " CONFIRM_REMOVE

    if [[ "$CONFIRM_REMOVE" =~ ^[Yy]$ ]]; then
        read -p "Do you want to PERMANENTLY DELETE all user data and files too? (y/n): " PURGE_DATA

        if [[ "$PURGE_DATA" =~ ^[Yy]$ ]]; then
            echo "--> Removing Nextcloud and purging ALL data..."
            snap remove nextcloud --purge
            echo "--> Done. Nextcloud and all data have been permanently deleted."
        else
            echo "--> Removing Nextcloud (Creating a backup snapshot of your data)..."
            snap remove nextcloud
            echo "--> Done. Nextcloud software removed, but data snapshot was saved."
        fi

        # Optional: Remove firewall rules added by the script
        ufw delete allow 80/tcp > /dev/null 2>&1
        ufw delete allow 443/tcp > /dev/null 2>&1
        echo "--> Web firewall rules removed."

    else
        echo "Removal canceled. Exiting."
    fi
    exit 0

# ---------------------------------------------------
# OPTION 3: EXIT
# ---------------------------------------------------
elif [ "$MENU_OPTION" == "3" ]; then
    echo "Exiting."
    exit 0

# ---------------------------------------------------
# OPTION 1: INSTALL NEXTCLOUD (If not 2 or 3)
# ---------------------------------------------------
elif [ "$MENU_OPTION" == "1" ]; then
    echo ""
    echo "--- INITIAL SETUP ---"
    read -p "Enter your Server's Public IP (e.g., 45.79.215.171): " SERVER_IP
    read -p "Create a Nextcloud Admin Username: " NC_ADMIN_USER
    read -s -p "Create a Nextcloud Admin Password: " NC_ADMIN_PASS
    echo ""
    echo ""

    read -p "Do you have a domain name pointing to this server? (y/n): " SETUP_SSL
    if [[ "$SETUP_SSL" =~ ^[Yy]$ ]]; then
        read -p "Enter your Domain Name (e.g., cloud.yourdomain.com): " DOMAIN_NAME
        read -p "Enter an Email Address for the SSL Certificate: " LETS_ENCRYPT_EMAIL
    else
        DOMAIN_NAME=""
    fi

    echo ""
    echo "================================================="
    echo "   Configuration Saved. Starting Installation!   "
    echo "   Please wait, this will take a few minutes...  "
    echo "================================================="
    echo ""

    echo "--> [1/5] Updating system and configuring firewall..."
    apt update -y > /dev/null 2>&1
    ufw allow OpenSSH > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo "--> [2/5] Downloading and Installing Nextcloud Snap..."
    snap install nextcloud
    sleep 10

    echo "--> [3/5] Setting up your Admin Account..."
    nextcloud.manual-install "$NC_ADMIN_USER" "$NC_ADMIN_PASS"

    echo "--> [4/5] Whitelisting IP and Domains..."
    nextcloud.occ config:system:set trusted_domains 1 --value="$SERVER_IP"
    if [ -n "$DOMAIN_NAME" ]; then
        nextcloud.occ config:system:set trusted_domains 2 --value="$DOMAIN_NAME"
    fi

    echo "--> [5/5] Checking SSL requirements..."
    if [ -n "$DOMAIN_NAME" ] && [ -n "$LETS_ENCRYPT_EMAIL" ]; then
        echo "--> Generating free SSL Certificate from Let's Encrypt..."
        nextcloud.enable-https lets-encrypt -y -d "$DOMAIN_NAME" -e "$LETS_ENCRYPT_EMAIL"
    else
        echo "--> No domain provided. Skipping SSL setup."
    fi

    snap set nextcloud php.memory-limit=512M

    echo ""
    echo "================================================="
    echo "               SETUP COMPLETE!                   "
    echo "================================================="
    if [ -n "$DOMAIN_NAME" ]; then
        echo "Access your cloud at: https://$DOMAIN_NAME"
    else
        echo "Access your cloud at: http://$SERVER_IP"
    fi
    echo "Username: $NC_ADMIN_USER"
    echo "================================================="

else
    echo "Invalid option. Exiting."
    exit 1
fi
