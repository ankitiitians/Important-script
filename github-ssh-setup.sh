#!/bin/bash
# =============================================================================
#  github-ssh-setup.sh
#  Full GitHub SSH Setup Script — works on any fresh Linux/macOS server
#  Usage: bash github-ssh-setup.sh [--token YOUR_GITHUB_PAT] [--email you@example.com]
# =============================================================================

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"; }

# ─── Defaults ─────────────────────────────────────────────────────────────────
GITHUB_TOKEN=""
GIT_EMAIL=""
GIT_NAME=""
KEY_TYPE="ed25519"
KEY_FILE="$HOME/.ssh/id_${KEY_TYPE}"
SSH_DIR="$HOME/.ssh"
SKIP_AGENT=false

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)   GITHUB_TOKEN="$2"; shift 2 ;;
    --email)   GIT_EMAIL="$2";    shift 2 ;;
    --name)    GIT_NAME="$2";     shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--token GITHUB_PAT] [--email you@example.com] [--name 'Your Name']"
      echo ""
      echo "Options:"
      echo "  --token   GitHub Personal Access Token (for auto-adding SSH key via API)"
      echo "  --email   Git commit email"
      echo "  --name    Git commit name"
      echo "  --help    Show this help"
      exit 0
      ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ██████  ██ ████████ ██   ██ ██    ██ ██████      ███████ ███████ ██   ██"
echo " ██       ██    ██    ██   ██ ██    ██ ██   ██     ██      ██      ██   ██"
echo " ██   ███ ██    ██    ███████ ██    ██ ██████      ███████ ███████ ███████"
echo " ██    ██ ██    ██    ██   ██ ██    ██ ██   ██          ██      ██ ██   ██"
echo "  ██████  ██    ██    ██   ██  ██████  ██████      ███████ ███████ ██   ██"
echo -e "${RESET}"
echo -e "  ${BOLD}GitHub SSH Setup Script${RESET} — Secure server↔GitHub connection"
echo -e "  $(date '+%Y-%m-%d %H:%M:%S')  |  Host: $(hostname)  |  User: $USER"
echo ""

# ─── Pre-flight checks ────────────────────────────────────────────────────────
header "Pre-flight Checks"

# OS Detection
OS="unknown"
if [[ "$(uname)" == "Darwin" ]]; then
  OS="macos"
elif [[ -f /etc/os-release ]]; then
  OS="linux"
fi
info "Detected OS: ${OS}"

# Check git
if ! command -v git &>/dev/null; then
  error "git is not installed. Install it first:"
  echo "  Ubuntu/Debian: sudo apt-get install -y git"
  echo "  CentOS/RHEL:   sudo yum install -y git"
  echo "  macOS:         xcode-select --install"
  exit 1
fi
success "git found: $(git --version)"

# Check openssh
if ! command -v ssh-keygen &>/dev/null; then
  error "ssh-keygen not found. Install openssh-client."
  exit 1
fi
success "ssh-keygen found"

# Check curl (needed for API key upload)
CURL_AVAILABLE=false
if command -v curl &>/dev/null; then
  CURL_AVAILABLE=true
  success "curl found"
else
  warn "curl not found — automatic GitHub key upload will be skipped"
fi

# ─── Step 1: SSH Directory ────────────────────────────────────────────────────
header "Step 1 — SSH Directory"

if [[ ! -d "$SSH_DIR" ]]; then
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  success "Created $SSH_DIR with correct permissions (700)"
else
  chmod 700 "$SSH_DIR"
  success "$SSH_DIR exists — permissions enforced (700)"
fi

# ─── Step 2: SSH Key Generation ───────────────────────────────────────────────
header "Step 2 — SSH Key"

if [[ -f "$KEY_FILE" ]]; then
  warn "SSH key already exists: $KEY_FILE"
  read -rp "$(echo -e "${YELLOW}Overwrite existing key? (y/N): ${RESET}")" OVERWRITE
  if [[ "${OVERWRITE,,}" != "y" ]]; then
    info "Keeping existing key."
  else
    rm -f "$KEY_FILE" "${KEY_FILE}.pub"
    info "Removed old key. Generating new one..."
    _generate_key=true
  fi
else
  _generate_key=true
fi

if [[ "${_generate_key:-false}" == "true" ]]; then
  # Collect email if not provided
  if [[ -z "$GIT_EMAIL" ]]; then
    read -rp "$(echo -e "${CYAN}Enter your GitHub email address: ${RESET}")" GIT_EMAIL
  fi

  ssh-keygen -t ed25519 -C "${GIT_EMAIL}" -f "$KEY_FILE" -N ""
  success "SSH key generated: $KEY_FILE"
fi

chmod 600 "$KEY_FILE"
chmod 644 "${KEY_FILE}.pub"
success "Key file permissions set correctly"

# ─── Step 3: SSH Agent ────────────────────────────────────────────────────────
header "Step 3 — SSH Agent"

# Detect if running in a non-interactive environment (e.g. CI/cron)
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  info "Starting ssh-agent..."
  eval "$(ssh-agent -s)" >/dev/null
  success "ssh-agent started (PID: $SSH_AGENT_PID)"
else
  success "ssh-agent already running"
fi

ssh-add "$KEY_FILE" 2>/dev/null && success "Key added to ssh-agent" || warn "Could not add key to agent (may already be loaded)"

# Persist agent across sessions — add to shell profile if not already there
AGENT_BLOCK='# GitHub SSH agent
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add ~/.ssh/id_ed25519 2>/dev/null
fi'

for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
  if [[ -f "$PROFILE" ]] && ! grep -q "GitHub SSH agent" "$PROFILE"; then
    echo "" >> "$PROFILE"
    echo "$AGENT_BLOCK" >> "$PROFILE"
    success "Added agent persistence to $PROFILE"
  fi
done

# ─── Step 4: SSH Config ───────────────────────────────────────────────────────
header "Step 4 — SSH Config (~/.ssh/config)"

SSH_CONFIG="$SSH_DIR/config"
GITHUB_CONFIG_BLOCK="Host github.com
  HostName github.com
  User git
  IdentityFile $KEY_FILE
  IdentitiesOnly yes
  ServerAliveInterval 60
  ServerAliveCountMax 3"

if [[ ! -f "$SSH_CONFIG" ]] || ! grep -q "Host github.com" "$SSH_CONFIG"; then
  echo "" >> "$SSH_CONFIG"
  echo "$GITHUB_CONFIG_BLOCK" >> "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  success "GitHub SSH config block added to $SSH_CONFIG"
else
  success "GitHub entry already exists in $SSH_CONFIG"
fi

# ─── Step 5: Display Public Key ───────────────────────────────────────────────
header "Step 5 — Your Public Key"

PUB_KEY=$(cat "${KEY_FILE}.pub")
echo ""
echo -e "${BOLD}${GREEN}┌─────────────────────────────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}${GREEN}│ COPY THIS KEY AND ADD IT TO GITHUB                              │${RESET}"
echo -e "${BOLD}${GREEN}└─────────────────────────────────────────────────────────────────┘${RESET}"
echo ""
echo "$PUB_KEY"
echo ""

# ─── Step 6: Auto-upload via GitHub API (if token provided) ───────────────────
header "Step 6 — Add SSH Key to GitHub"

if [[ -n "$GITHUB_TOKEN" ]] && [[ "$CURL_AVAILABLE" == "true" ]]; then
  info "Attempting to auto-upload SSH key via GitHub API..."

  KEY_TITLE="server-$(hostname)-$(date '+%Y%m%d')"

  HTTP_STATUS=$(curl -s -o /tmp/gh_api_response.json -w "%{http_code}" \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/user/keys \
    -d "{\"title\":\"${KEY_TITLE}\",\"key\":\"${PUB_KEY}\"}")

  if [[ "$HTTP_STATUS" == "201" ]]; then
    success "SSH key automatically added to GitHub as: ${KEY_TITLE}"
  elif [[ "$HTTP_STATUS" == "422" ]]; then
    warn "Key already exists on GitHub (HTTP 422 — Unprocessable Entity)"
  else
    error "GitHub API returned HTTP $HTTP_STATUS:"
    cat /tmp/gh_api_response.json 2>/dev/null || true
    echo ""
    warn "Falling back to manual instructions below."
  fi
else
  echo -e "${YELLOW}Manual steps to add your key to GitHub:${RESET}"
  echo ""
  echo "  1. Go to: https://github.com/settings/ssh/new"
  echo "  2. Title: server-$(hostname)"
  echo "  3. Key type: Authentication Key"
  echo "  4. Paste the public key shown above"
  echo "  5. Click 'Add SSH key'"
  echo ""
  if [[ -n "$GITHUB_TOKEN" ]] && [[ "$CURL_AVAILABLE" == "false" ]]; then
    warn "curl is not installed — cannot use GitHub API to auto-upload."
  else
    echo -e "${CYAN}TIP: Re-run with --token flag to auto-upload:${RESET}"
    echo "  bash $0 --token YOUR_GITHUB_PAT"
    echo ""
    echo "  Generate a token at: https://github.com/settings/tokens"
    echo "  Required scope: write:public_key (or admin:public_key)"
  fi
fi

# ─── Step 7: Git Global Config ────────────────────────────────────────────────
header "Step 7 — Git Global Configuration"

if [[ -z "$GIT_NAME" ]]; then
  CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
  if [[ -n "$CURRENT_NAME" ]]; then
    read -rp "$(echo -e "${CYAN}Git name [${CURRENT_NAME}]: ${RESET}")" INPUT_NAME
    GIT_NAME="${INPUT_NAME:-$CURRENT_NAME}"
  else
    read -rp "$(echo -e "${CYAN}Enter your full name for Git commits: ${RESET}")" GIT_NAME
  fi
fi

if [[ -z "$GIT_EMAIL" ]]; then
  CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
  if [[ -n "$CURRENT_EMAIL" ]]; then
    read -rp "$(echo -e "${CYAN}Git email [${CURRENT_EMAIL}]: ${RESET}")" INPUT_EMAIL
    GIT_EMAIL="${INPUT_EMAIL:-$CURRENT_EMAIL}"
  else
    read -rp "$(echo -e "${CYAN}Enter your GitHub email: ${RESET}")" GIT_EMAIL
  fi
fi

git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.autocrlf input
git config --global color.ui auto

success "Git configured:"
echo "    user.name  = $GIT_NAME"
echo "    user.email = $GIT_EMAIL"
echo "    init.defaultBranch = main"

# ─── Step 8: Test SSH Connection ──────────────────────────────────────────────
header "Step 8 — Testing SSH Connection to GitHub"

info "Sending test handshake to github.com (may take a few seconds)..."
echo ""

SSH_OUTPUT=$(ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 || true)

if echo "$SSH_OUTPUT" | grep -q "successfully authenticated"; then
  echo -e "${GREEN}${BOLD}$SSH_OUTPUT${RESET}"
  echo ""
  success "SSH authentication to GitHub is WORKING!"
  GITHUB_USER=$(echo "$SSH_OUTPUT" | grep -oP '(?<=Hi )[^!]+' || echo "unknown")
  success "GitHub username detected: ${GITHUB_USER}"
else
  echo "$SSH_OUTPUT"
  echo ""
  warn "SSH test did not confirm authentication."
  echo ""
  echo "  Possible reasons:"
  echo "  - Key not yet added to GitHub (complete Step 6 above first)"
  echo "  - Token insufficient scope (needs write:public_key)"
  echo "  - Network/firewall blocking port 22"
  echo ""
  echo "  Manual verification command:"
  echo "    ssh -T git@github.com"
fi

# ─── Step 9: Known Hosts ──────────────────────────────────────────────────────
header "Step 9 — GitHub Known Hosts"

KNOWN_HOSTS_FILE="$SSH_DIR/known_hosts"

# Ensure GitHub's fingerprint is trusted
if ! grep -q "github.com" "$KNOWN_HOSTS_FILE" 2>/dev/null; then
  ssh-keyscan -H github.com >> "$KNOWN_HOSTS_FILE" 2>/dev/null
  success "GitHub fingerprint added to known_hosts"
else
  success "GitHub already in known_hosts"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Setup Complete ✅"

echo -e "${BOLD}Summary:${RESET}"
echo ""
echo -e "  ${GREEN}●${RESET} SSH Key:     $KEY_FILE"
echo -e "  ${GREEN}●${RESET} Public Key:  ${KEY_FILE}.pub"
echo -e "  ${GREEN}●${RESET} SSH Config:  $SSH_CONFIG"
echo -e "  ${GREEN}●${RESET} Git Name:    $GIT_NAME"
echo -e "  ${GREEN}●${RESET} Git Email:   $GIT_EMAIL"
echo ""
echo -e "${BOLD}Quick Reference Commands:${RESET}"
echo ""
echo "  # Clone a repo"
echo "  git clone git@github.com:<username>/<repo>.git"
echo ""
echo "  # Push changes"
echo "  git add . && git commit -m 'message' && git push origin main"
echo ""
echo "  # Check remote URLs"
echo "  git remote -v"
echo ""
echo "  # Switch existing HTTPS remote to SSH"
echo "  git remote set-url origin git@github.com:<username>/<repo>.git"
echo ""
echo "  # Re-test SSH anytime"
echo "  ssh -T git@github.com"
echo ""
echo -e "${BOLD}${GREEN}Your public key (save this):${RESET}"
echo ""
cat "${KEY_FILE}.pub"
echo ""
echo -e "  ${CYAN}Add it at: https://github.com/settings/ssh/new${RESET}"
echo ""
