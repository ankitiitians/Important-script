#!/bin/bash

# ==============================================================================
# Script Name: kind_cluster_ops.sh
# Description: An interactive management tool for local Kubernetes clusters
#              using Kind (Kubernetes in Docker). It includes dependency
#              management, OS detection, and version checking.
# ==============================================================================

# Define color codes for CLI output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration file name
CONFIG_FILE="kind-cluster-config.yaml"

# Print the main header
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}   KIND CLUSTER INTERACTIVE MANAGER       ${NC}"
echo -e "${BLUE}==========================================${NC}"

# Function to display the interactive menu
show_menu() {
    echo -e "\n${GREEN}Please choose an option:${NC}"
    echo "0) Check & Install Dependencies (docker, kind, kubectl)"
    echo "1) Create Cluster (Prompts for Version/Name)"
    echo "2) Delete Cluster"
    echo "3) Check Cluster Status (Nodes)"
    echo "4) List all Kind Clusters"
    echo "5) Check Installed Tool Versions"
    echo "6) Exit"
}

# Function to verify and install required dependencies across Linux flavors
install_dependencies() {
    echo -e "${BLUE}[INFO] Checking system dependencies...${NC}"
    
    # 1. Check and Install Docker across multiple OS flavors
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[INFO] Docker is not installed. Detecting OS using /etc/os-release...${NC}"
        
        # Robust OS Detection
        if [ -f /etc/os-release ]; then
            # Source the OS release file to get $ID and $ID_LIKE variables
            . /etc/os-release
            OS_FLAVOR="${ID:-}"
            OS_LIKE="${ID_LIKE:-}"
        else
            echo -e "${RED}[ERROR] Cannot detect OS flavor. /etc/os-release not found.${NC}"
            exit 1
        fi

        echo -e "${BLUE}[INFO] Detected OS Flavor: $PRETTY_NAME${NC}"

        # Install Docker based on detected OS
        case "$OS_FLAVOR" in
            ubuntu|debian)
                sudo apt-get update -y
                sudo apt-get install docker.io -y
                ;;
            fedora|centos|rhel|rocky|almalinux)
                # Fedora uses dnf, older CentOS/RHEL might use yum
                if command -v dnf &> /dev/null; then
                    sudo dnf install docker -y
                else
                    sudo yum install docker -y
                fi
                ;;
            arch|manjaro)
                sudo pacman -Sy docker --noconfirm
                ;;
            opensuse*|suse)
                sudo zypper install -y docker
                ;;
            *)
                # Fallback check using ID_LIKE
                if [[ "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
                    sudo apt-get update -y
                    sudo apt-get install docker.io -y
                elif [[ "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* || "$OS_LIKE" == *"centos"* ]]; then
                    if command -v dnf &> /dev/null; then
                        sudo dnf install docker -y
                    else
                        sudo yum install docker -y
                    fi
                else
                    echo -e "${RED}[ERROR] OS ($OS_FLAVOR) is not supported by this auto-installer.${NC}"
                    echo -e "Please install Docker manually from https://docs.docker.com/engine/install/"
                    exit 1
                fi
                ;;
        esac

        # Ensure Docker service is enabled and started
        if command -v systemctl &> /dev/null; then
            echo -e "${BLUE}[INFO] Starting and enabling Docker service...${NC}"
            sudo systemctl enable docker
            sudo systemctl start docker
        fi
        
        echo -e "${GREEN}[SUCCESS] Docker installed and started successfully.${NC}"
    else
        echo -e "${GREEN}[OK] Docker is already installed.${NC}"
    fi

    # 1.1 Check Docker Permissions
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${YELLOW}[WARNING] Permission denied when connecting to Docker daemon.${NC}"
        echo -e "${BLUE}[INFO] Adding user $USER to the docker group...${NC}"
        sudo usermod -aG docker "$USER"
        
        echo -e "\n${RED}============================================================${NC}"
        echo -e "${RED}[ACTION REQUIRED] Session Reload Needed${NC}"
        echo -e "${RED}============================================================${NC}"
        echo -e "Your user has been added to the docker group, but your current"
        echo -e "terminal session has not registered this change yet."
        echo -e "\nPlease run the following command in your terminal:"
        echo -e "    ${GREEN}newgrp docker${NC}"
        echo -e "\nAfter running that command, execute this script again."
        echo -e "${RED}============================================================${NC}"
        exit 1
    else
        echo -e "${GREEN}[OK] Docker permissions are properly configured.${NC}"
    fi

    # 2. Check and Install kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${YELLOW}[INFO] kubectl not found. Downloading the latest stable release...${NC}"
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        echo -e "${BLUE}[INFO] Requesting sudo privileges to move kubectl to /usr/local/bin/${NC}"
        sudo mv kubectl /usr/local/bin/
        echo -e "${GREEN}[SUCCESS] kubectl installed successfully.${NC}"
    else
        echo -e "${GREEN}[OK] kubectl is already installed.${NC}"
    fi

    # 3. Check and Install Kind
    if ! command -v kind &> /dev/null; then
        echo -e "${YELLOW}[INFO] kind not found. Downloading the latest release...${NC}"
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
        chmod +x ./kind
        echo -e "${BLUE}[INFO] Requesting sudo privileges to move kind to /usr/local/bin/${NC}"
        sudo mv ./kind /usr/local/bin/kind
        echo -e "${GREEN}[SUCCESS] kind installed successfully.${NC}"
    else
        echo -e "${GREEN}[OK] kind is already installed.${NC}"
    fi
}

# Function to create a new Kind cluster
create_cluster() {
    read -p "Enter a name for your cluster [default: my-kind-cluster]: " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-my-kind-cluster}

    echo -e "${YELLOW}Note: The default Kubernetes version is set to v1.35.0${NC}"
    read -p "Enter Kubernetes version to use [default: v1.35.0]: " K8S_VERSION
    K8S_VERSION=${K8S_VERSION:-v1.35.0}

    echo -e "${BLUE}[INFO] Generating configuration file ($CONFIG_FILE) for Kubernetes version $K8S_VERSION...${NC}"
    
    cat <<EOF > "$CONFIG_FILE"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

nodes:
- role: control-plane
  image: kindest/node:$K8S_VERSION
- role: worker
  image: kindest/node:$K8S_VERSION
- role: worker
  image: kindest/node:$K8S_VERSION
EOF

    echo -e "${BLUE}[INFO] Provisioning cluster '$CLUSTER_NAME'...${NC}"
    kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_FILE"
}

# Function to delete an existing Kind cluster
delete_cluster() {
    read -p "Enter the name of the cluster to delete [default: my-kind-cluster]: " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-my-kind-cluster}

    echo -e "${RED}Are you sure you want to delete the cluster '$CLUSTER_NAME'? (y/n)${NC}"
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
        
        if [ -f "$CONFIG_FILE" ]; then
            rm "$CONFIG_FILE"
            echo -e "${GREEN}[INFO] Cleaned up local configuration file ($CONFIG_FILE).${NC}"
        fi
    else
        echo -e "${YELLOW}Cluster deletion cancelled.${NC}"
    fi
}

# Function to check versions of installed tools
check_versions() {
    echo -e "\n${BLUE}[INFO] Fetching Tool Versions...${NC}"
    
    echo -e "\n${YELLOW}--- Docker ---${NC}"
    if command -v docker &> /dev/null; then
        docker --version
    else
        echo -e "${RED}[ERROR] Docker is not installed.${NC}"
    fi

    echo -e "\n${YELLOW}--- Kind ---${NC}"
    if command -v kind &> /dev/null; then
        kind --version
    else
        echo -e "${RED}[ERROR] Kind is not installed.${NC}"
    fi

    echo -e "\n${YELLOW}--- Kubectl ---${NC}"
    if command -v kubectl &> /dev/null; then
        kubectl version
    else
        echo -e "${RED}[ERROR] Kubectl is not installed.${NC}"
    fi
    echo ""
}

# ==============================================================================
# Main Execution Loop
# ==============================================================================
while true; do
    show_menu
    read -p "Enter choice [0-6]: " choice
    case $choice in
        0) install_dependencies ;;
        1) create_cluster ;;
        2) delete_cluster ;;
        3) kubectl get nodes || echo -e "${RED}[ERROR] Cluster not running or kubectl cannot connect.${NC}" ;;
        4) kind get clusters ;;
        5) check_versions ;;
        6) echo -e "${GREEN}[INFO] Exiting script. Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}[ERROR] Invalid selection. Please try again.${NC}" ;;
    esac
done
