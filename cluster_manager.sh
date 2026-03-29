#!/bin/bash

# Colors for better UI
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="my-kind-cluster"
CONFIG_FILE="kind-cluster-config.yaml"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}   🚀 KIND CLUSTER INTERACTIVE MANAGER   ${NC}"
echo -e "${BLUE}==========================================${NC}"

show_menu() {
    echo -e "\n${GREEN}Please choose an option:${NC}"
    echo "1) Create Cluster"
    echo "2) Delete Cluster"
    echo "3) Check Cluster Status (Nodes)"
    echo "4) List all Kind Clusters"
    echo "5) Exit"
}

create_cluster() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: $CONFIG_FILE not found!${NC}"
        return
    fi
    echo -e "${BLUE}Creating cluster: $CLUSTER_NAME...${NC}"
    kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_FILE"
}

delete_cluster() {
    echo -e "${RED}Are you sure you want to delete '$CLUSTER_NAME'? (y/n)${NC}"
    read -r confirm
    if [[ "$confirm" == "y" ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Deletion cancelled."
    fi
}

while true; do
    show_menu
    read -p "Enter choice [1-5]: " choice
    case $choice in
        1) create_cluster ;;
        2) delete_cluster ;;
        3) kubectl get nodes || echo -e "${RED}Cluster not running.${NC}" ;;
        4) kind get clusters ;;
        5) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option, try again.${NC}" ;;
    esac
done
