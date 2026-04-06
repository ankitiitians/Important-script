#!/bin/bash

# ==============================================================================
# Jenkins Lifecycle Management Script (Full Suite)
# Description: Production-ready interactive tool for Jenkins on Linux
# Author: Ankit Srivastav
# Version: 2.1.0 (Added Password Retrieval & Export)
# ==============================================================================

# --- Configuration & Colors ---
LOG_FILE="/var/log/jenkins_manager.log"
exec > >(tee -a "$LOG_FILE") 2>&1

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

JENKINS_HOME="/var/lib/jenkins"
BACKUP_DIR="/opt/jenkins_backups"

# --- Helper Functions ---

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
fatal_error() { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

retry_cmd() {
    local n=1
    local max=3
    local delay=5
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                log_warn "Command failed. Attempt $n/$max in ${delay}s..."
                sleep $delay
            else
                fatal_error "The command has failed after $n attempts."
            fi
        }
    done
}

# --- Validation Checks ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
       fatal_error "This script must be run as root or with sudo."
    fi
}

detect_os() {
    echo -e "\n${CYAN}--- OS Detection / Selection ---${NC}"
    echo -e "  1) Auto-detect OS (Recommended)"
    echo -e "  2) Force Ubuntu / Debian Family"
    echo -e "  3) Force RedHat / CentOS / AlmaLinux Family"
    read -rp "Select your Linux flavor [1-3, Default: 1]: " os_choice
    os_choice=${os_choice:-1}

    case $os_choice in
        1)
            log_info "Auto-detecting Operating System..."
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS=$ID
                log_success "Auto-detected OS: $PRETTY_NAME ($OS)"
            else
                fatal_error "Auto-detection failed. Could not read /etc/os-release. Please run again and select manually."
            fi
            ;;
        2)
            OS="ubuntu"
            log_success "Manually selected: Ubuntu / Debian family"
            ;;
        3)
            OS="centos"
            log_success "Manually selected: RHEL / CentOS family"
            ;;
        *)
            fatal_error "Invalid OS selection."
            ;;
    esac

    if [[ ! "$OS" =~ ^(ubuntu|debian|centos|rhel|almalinux|rocky)$ ]]; then
        fatal_error "The detected or selected OS ($OS) is currently not supported by this script."
    fi
}

is_jenkins_installed() {
    if ! command -v jenkins >/dev/null 2>&1 && [ ! -d "$JENKINS_HOME" ]; then
        return 1
    fi
    return 0
}

# --- 1. Installation Workflow ---

install_workflow() {
    if is_jenkins_installed; then
        log_warn "Jenkins appears to be already installed."
        return
    fi

    log_info "Starting Installation Process..."

    rm -f /etc/apt/sources.list.d/jenkins.list
    rm -f /usr/share/keyrings/jenkins-keyring.asc
    rm -f /etc/apt/keyrings/jenkins-keyring.asc
    rm -f /etc/yum.repos.d/jenkins.repo

    log_info "Installing base dependencies..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get update -y > /dev/null
        apt-get install -y curl gnupg software-properties-common wget fontconfig ca-certificates apt-transport-https > /dev/null
    elif [[ "$OS" =~ ^(centos|rhel|almalinux|rocky)$ ]]; then
        yum install -y curl wget fontconfig ca-certificates > /dev/null
    fi

    read -rp "Install OpenJDK 21 (Official Jenkins Recommendation)? [y/N]: " install_java
    if [[ "$install_java" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Installing OpenJDK 21..."
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            retry_cmd apt-get update
            retry_cmd apt-get install -y openjdk-21-jre
        else
            retry_cmd yum install -y java-21-openjdk
        fi
        log_success "Java installed."
    fi

    echo -e "\n${CYAN}Select Jenkins Release Type:${NC}"
    echo -e "  1) Long-Term Support (LTS) - Stable & Recommended for Production"
    echo -e "  2) Weekly Release - Latest Features & Updates"
    read -rp "Enter choice [1-2, Default: 1]: " REL_CHOICE
    REL_CHOICE=${REL_CHOICE:-1}

    log_info "Configuring Jenkins repository securely..."
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        mkdir -p /etc/apt/keyrings
        if [[ "$REL_CHOICE" == "2" ]]; then
            REPO_URL="https://pkg.jenkins.io/debian"
            KEY_URL="https://pkg.jenkins.io/debian/jenkins.io-2026.key"
            log_info "Selected: Weekly (Latest)"
        else
            REPO_URL="https://pkg.jenkins.io/debian-stable"
            KEY_URL="https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key"
            log_info "Selected: LTS (Stable)"
        fi
        
        wget -O /etc/apt/keyrings/jenkins-keyring.asc "${KEY_URL}"
        echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] ${REPO_URL} binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
        retry_cmd apt-get update -y
        
    elif [[ "$OS" =~ ^(centos|rhel|almalinux|rocky)$ ]]; then
        if [[ "$REL_CHOICE" == "2" ]]; then
            REPO_URL="https://pkg.jenkins.io/redhat"
            log_info "Selected: Weekly (Latest)"
        else
            REPO_URL="https://pkg.jenkins.io/redhat-stable"
            log_info "Selected: LTS (Stable)"
        fi
        
        wget -O /etc/yum.repos.d/jenkins.repo "${REPO_URL}/jenkins.repo"
        retry_cmd yum upgrade -y
    fi

    read -rp "Enter Jenkins HTTP port [Default 8080]: " JENKINS_PORT
    JENKINS_PORT=${JENKINS_PORT:-8080}
    
    log_info "Installing Jenkins package..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        retry_cmd apt-get install -y jenkins
    else
        retry_cmd yum install -y jenkins
    fi

    mkdir -p /etc/systemd/system/jenkins.service.d/
    cat <<EOF > /etc/systemd/system/jenkins.service.d/override.conf
[Service]
Environment="JENKINS_PORT=$JENKINS_PORT"
EOF
    systemctl daemon-reload

    read -rp "Automatically configure firewall for port $JENKINS_PORT? [y/N]: " conf_fw
    if [[ "$conf_fw" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        if command -v ufw >/dev/null; then
            ufw allow "$JENKINS_PORT"/tcp
            log_success "UFW updated."
        elif command -v firewall-cmd >/dev/null; then
            firewall-cmd --permanent --add-port="$JENKINS_PORT"/tcp
            firewall-cmd --reload
            log_success "Firewalld updated."
        fi
    fi

    read -rp "Enable and start Jenkins service now? [y/N]: " start_svc
    if [[ "$start_svc" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        systemctl enable jenkins
        systemctl start jenkins &
        spinner $!
        log_success "Jenkins service is running."
    fi

    # Post-Installation info & Password Retrieval
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}==================================================${NC}"
    echo -e "Jenkins URL: http://$IP_ADDR:$JENKINS_PORT"

    log_info "Waiting for Jenkins to generate the initial admin password (this may take a few seconds)..."
    for i in {1..30}; do
        if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
            break
        fi
        sleep 1
    done
    
    if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
        INIT_PASS=$(cat "$JENKINS_HOME/secrets/initialAdminPassword")
        echo -e "${YELLOW}Initial Admin Password: ${NC}$INIT_PASS"
        echo -e "${GREEN}==================================================${NC}"
        
        read -rp "Would you like to save these credentials to a text file? [y/N]: " save_pass
        if [[ "$save_pass" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            PASS_FILE="$(pwd)/jenkins_credentials.txt"
            echo "Jenkins URL: http://$IP_ADDR:$JENKINS_PORT" > "$PASS_FILE"
            echo "Initial Admin Password: $INIT_PASS" >> "$PASS_FILE"
            log_success "Credentials securely saved to: $PASS_FILE"
        fi
    else
        log_warn "Initial password file not yet generated."
        log_warn "You can manually retrieve it later using Option 9 from the Main Menu."
        echo -e "${GREEN}==================================================${NC}"
    fi
}

# --- 2. Update Workflow ---

update_workflow() {
    if ! is_jenkins_installed; then
        log_error "Jenkins is not installed."
        return
    fi
    
    log_info "Updating Jenkins based on currently configured repository..."
    systemctl stop jenkins
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get update -y
        apt-get --only-upgrade install -y jenkins
    else
        yum update -y jenkins
    fi
    
    systemctl daemon-reload
    systemctl start jenkins &
    spinner $!
    log_success "Jenkins updated successfully."
}

# --- 3. Backup Workflow ---

backup_workflow() {
    if [ ! -d "$JENKINS_HOME" ]; then
        log_error "Jenkins data directory ($JENKINS_HOME) not found."
        return
    fi

    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/jenkins_backup_$TIMESTAMP.tar.gz"

    log_warn "Stopping Jenkins service to prevent data corruption during backup..."
    systemctl stop jenkins

    log_info "Creating backup of $JENKINS_HOME... This may take a while."
    tar -czf "$BACKUP_FILE" -C / var/lib/jenkins &
    spinner $!

    log_info "Restarting Jenkins service..."
    systemctl start jenkins

    log_success "Backup completed successfully: $BACKUP_FILE"
}

# --- 4. Service Status ---

status_workflow() {
    echo -e "\n${CYAN}--- Jenkins Status ---${NC}"
    if systemctl is-active --quiet jenkins; then
        echo -e "Service State : ${GREEN}Running${NC}"
    else
        echo -e "Service State : ${RED}Stopped${NC}"
    fi

    if systemctl is-enabled --quiet jenkins; then
        echo -e "Boot Enabled  : ${GREEN}Yes${NC}"
    else
        echo -e "Boot Enabled  : ${RED}No${NC}"
    fi
    echo -e "${CYAN}----------------------${NC}\n"
}

# --- 5. Version Check Workflow ---

check_versions_workflow() {
    echo -e "\n${CYAN}--- Version Information ---${NC}"
    
    if command -v java >/dev/null 2>&1; then
        JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        echo -e "Java Version    : ${GREEN}$JAVA_VER${NC}"
    else
        echo -e "Java Version    : ${RED}Not Installed${NC}"
    fi

    if is_jenkins_installed; then
        if [ -f /usr/share/java/jenkins.war ]; then
            JENKINS_VER=$(java -jar /usr/share/java/jenkins.war --version 2>/dev/null)
        elif command -v jenkins >/dev/null 2>&1; then
            JENKINS_VER=$(jenkins --version 2>/dev/null)
        else
            JENKINS_VER="Installed (Version Unknown)"
        fi
        echo -e "Jenkins Version : ${GREEN}$JENKINS_VER${NC}"
    else
        echo -e "Jenkins Version : ${RED}Not Installed${NC}"
    fi
    
    echo -e "${CYAN}---------------------------${NC}\n"
}

# --- 6. Restart Workflow ---

restart_workflow() {
    if ! is_jenkins_installed; then
        log_error "Jenkins is not installed."
        return
    fi
    log_info "Restarting Jenkins service..."
    systemctl restart jenkins &
    spinner $!
    log_success "Jenkins has been restarted."
}

# --- 7. Removal Workflow ---

remove_workflow() {
    log_warn "This action will purge Jenkins and ALL its data (jobs, configs, users)."
    read -rp "Confirm complete removal? [y/N]: " confirm_remove
    if [[ ! "$confirm_remove" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Removal aborted."
        return
    fi

    log_info "Stopping Jenkins service..."
    systemctl stop jenkins 2>/dev/null
    systemctl disable jenkins 2>/dev/null

    log_info "Removing packages and repositories..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get purge -y jenkins
        apt-get autoremove -y
        rm -f /etc/apt/sources.list.d/jenkins.list
        rm -f /usr/share/keyrings/jenkins-keyring.asc
        rm -f /etc/apt/keyrings/jenkins-keyring.asc
    else
        yum remove -y jenkins
        rm -f /etc/yum.repos.d/jenkins.repo
    fi

    log_info "Cleaning up leftover files..."
    rm -rf "$JENKINS_HOME"
    rm -rf /var/cache/jenkins
    rm -rf /var/log/jenkins
    rm -rf /etc/systemd/system/jenkins.service.d/

    log_info "Removing Jenkins system user and group..."
    userdel jenkins 2>/dev/null
    groupdel jenkins 2>/dev/null
    
    systemctl daemon-reload
    log_success "Jenkins has been completely removed."
}

# --- 8. Nginx Proxy Workflow ---

nginx_proxy_workflow() {
    if ! is_jenkins_installed; then
        log_error "Jenkins is not installed. Please install Jenkins first."
        return
    fi

    log_info "Starting Nginx Reverse Proxy Setup..."

    log_info "Installing Nginx..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        retry_cmd apt-get install -y nginx
    elif [[ "$OS" =~ ^(centos|rhel|almalinux|rocky)$ ]]; then
        if [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
            yum install -y epel-release >/dev/null 2>&1
        fi
        retry_cmd yum install -y nginx
    fi

    read -rp "Enter the Domain Name or IP address for Jenkins (e.g., jenkins.example.com or 192.168.1.10): " SERVER_NAME
    if [[ -z "$SERVER_NAME" ]]; then
        log_error "Domain/IP cannot be empty."
        return
    fi

    CURRENT_PORT=8080
    if [ -f /etc/systemd/system/jenkins.service.d/override.conf ]; then
        CURRENT_PORT=$(grep "JENKINS_PORT" /etc/systemd/system/jenkins.service.d/override.conf | cut -d'=' -f2 | tr -d '"')
    fi
    CURRENT_PORT=${CURRENT_PORT:-8080}

    log_info "Configuring Nginx server block for Jenkins..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        NGINX_CONF="/etc/nginx/sites-available/jenkins"
        NGINX_LINK="/etc/nginx/sites-enabled/jenkins"
        rm -f /etc/nginx/sites-enabled/default
    else
        NGINX_CONF="/etc/nginx/conf.d/jenkins.conf"
        NGINX_LINK=""
    fi

    cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    server_name $SERVER_NAME;

    location / {
        proxy_pass http://127.0.0.1:$CURRENT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeout and redirect settings
        proxy_read_timeout  90;
        proxy_redirect      http://127.0.0.1:$CURRENT_PORT http://$SERVER_NAME;
    }
}
EOF

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        ln -sf "$NGINX_CONF" "$NGINX_LINK"
    fi

    read -rp "Automatically configure firewall to allow HTTP (Port 80)? [y/N]: " conf_fw
    if [[ "$conf_fw" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        if command -v ufw >/dev/null; then
            ufw allow 'Nginx HTTP' || ufw allow 80/tcp
            log_success "UFW updated for Nginx."
        elif command -v firewall-cmd >/dev/null; then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --reload
            log_success "Firewalld updated for Nginx."
        fi
    fi

    log_info "Testing Nginx configuration..."
    if nginx -t >/dev/null 2>&1; then
        systemctl enable nginx
        systemctl restart nginx &
        spinner $!
        log_success "Nginx reverse proxy configured successfully."
        echo -e "\n${GREEN}==================================================${NC}"
        echo -e "You can now access Jenkins securely at: http://$SERVER_NAME"
        echo -e "${GREEN}==================================================${NC}"
    else
        log_error "Nginx configuration test failed. Please review the configuration in $NGINX_CONF."
    fi
}

# --- 9. Retrieve Password Workflow ---

retrieve_password_workflow() {
    if ! is_jenkins_installed; then
        log_error "Jenkins is not installed."
        return
    fi
    
    if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
        INIT_PASS=$(cat "$JENKINS_HOME/secrets/initialAdminPassword")
        IP_ADDR=$(hostname -I | awk '{print $1}')
        
        CURRENT_PORT=8080
        if [ -f /etc/systemd/system/jenkins.service.d/override.conf ]; then
            CURRENT_PORT=$(grep "JENKINS_PORT" /etc/systemd/system/jenkins.service.d/override.conf | cut -d'=' -f2 | tr -d '"')
        fi
        CURRENT_PORT=${CURRENT_PORT:-8080}
        
        echo -e "\n${GREEN}==================================================${NC}"
        echo -e "Jenkins URL: http://$IP_ADDR:$CURRENT_PORT"
        echo -e "${YELLOW}Initial Admin Password: ${NC}$INIT_PASS"
        echo -e "${GREEN}==================================================${NC}"
        
        read -rp "Would you like to save these credentials to a text file? [y/N]: " save_pass
        if [[ "$save_pass" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            PASS_FILE="$(pwd)/jenkins_credentials.txt"
            echo "Jenkins URL: http://$IP_ADDR:$CURRENT_PORT" > "$PASS_FILE"
            echo "Initial Admin Password: $INIT_PASS" >> "$PASS_FILE"
            log_success "Credentials securely saved to: $PASS_FILE"
        fi
    else
        log_error "Initial password file not found. You may have already completed the setup wizard, or Jenkins has not started properly yet."
    fi
}

# --- Main Menu ---

main() {
    check_root
    
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}       Jenkins Manager - Author: Ankit Srivastav  ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    detect_os
    
    while true; do
        echo -e "\n${BLUE}==================================================${NC}"
        echo -e "  1) Install Jenkins (Choose LTS or Latest)"
        echo -e "  2) Update Jenkins"
        echo -e "  3) Backup Jenkins Data"
        echo -e "  4) Check Jenkins Status"
        echo -e "  5) Check Java & Jenkins Versions"
        echo -e "  6) Restart Jenkins Service"
        echo -e "  7) Remove Jenkins (Complete Purge)"
        echo -e "  8) Configure Nginx Reverse Proxy (Port 80)"
        echo -e "  9) Retrieve & Save Initial Admin Password"
        echo -e " 10) Exit"
        echo -e "--------------------------------------------------"
        read -rp "Choose an option [1-10]: " choice

        case $choice in
            1) install_workflow ;;
            2) update_workflow ;;
            3) backup_workflow ;;
            4) status_workflow ;;
            5) check_versions_workflow ;;
            6) restart_workflow ;;
            7) remove_workflow ;;
            8) nginx_proxy_workflow ;;
            9) retrieve_password_workflow ;;
            10) log_info "Exiting..."; exit 0 ;;
            *) log_error "Invalid selection. Please choose 1-10." ;;
        esac
    done
}

main "$@"
