#!/bin/bash
#
# GLKVM Cloud Installation Script
# 
# This script automates the installation of GLKVM Cloud with optional Caddy automatic HTTPS
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
    exit 1
fi

# Banner
echo "╔════════════════════════════════════════════════════════╗"
echo "║         GLKVM Cloud Installation Script              ║"
echo "║  Self-Deployed Lightweight Cloud KVM Remote Manager   ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Check Docker installation
info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    warning "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    success "Docker installed successfully"
else
    success "Docker is already installed"
fi

# Check Docker Compose installation
info "Checking Docker Compose installation..."
if ! docker compose version &> /dev/null; then
    if ! docker-compose version &> /dev/null; then
        warning "Docker Compose not found. Installing Docker Compose..."
        # Install docker-compose v2 as a Docker CLI plugin
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        mkdir -p /usr/local/lib/docker/cli-plugins
        curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        success "Docker Compose installed successfully"
    else
        success "Docker Compose (standalone) is already installed"
    fi
else
    success "Docker Compose (CLI plugin) is already installed"
fi

# Create installation directory
INSTALL_DIR="${HOME}/glkvm_cloud"
info "Creating installation directory at ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Clone or update repository
if [ -d "${INSTALL_DIR}/.git" ]; then
    info "Updating existing installation..."
    git pull
else
    info "Cloning GLKVM Cloud repository..."
    # Use the appropriate method to get the files
    # For now, we'll assume the files are already in the docker-compose directory
    if [ ! -f "docker-compose.yml" ]; then
        error "Installation files not found. Please clone the repository manually:"
        echo "  git clone https://github.com/gl-inet/glkvm-cloud.git"
        exit 1
    fi
fi

# Navigate to docker-compose directory
cd "${INSTALL_DIR}" || exit 1
if [ -d "docker-compose" ]; then
    cd docker-compose
fi

# Check if .env file exists
if [ -f ".env" ]; then
    warning ".env file already exists. Backing up to .env.backup"
    cp .env .env.backup
fi

# Copy .env.example to .env
if [ -f ".env.example" ]; then
    cp .env.example .env
    success "Created .env file from template"
else
    error ".env.example not found!"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║             Configuration Options                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Ask about Caddy/Domain setup
echo -e "${BLUE}Do you want to use automatic HTTPS with Let's Encrypt?${NC}"
echo "  - Choose 'yes' if you have a domain name and want automatic SSL certificates"
echo "  - Choose 'no' for IP-based access with self-signed certificates (browser warning)"
echo ""
read -p "Enable automatic HTTPS with Caddy? (y/N): " use_caddy

USE_CADDY=false
DOMAIN=""
ACME_EMAIL=""

if [[ "$use_caddy" =~ ^[Yy]$ ]]; then
    USE_CADDY=true
    echo ""
    info "Great! Let's configure automatic HTTPS with Caddy."
    echo ""
    
    # Prompt for domain
    while [ -z "$DOMAIN" ]; do
        read -p "Enter your domain name (e.g., kvm.example.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            warning "Domain name cannot be empty"
        fi
    done
    
    # Prompt for email
    echo ""
    echo "Let's Encrypt requires an email address for certificate expiration notifications."
    while [ -z "$ACME_EMAIL" ]; do
        read -p "Enter your email address: " ACME_EMAIL
        if [ -z "$ACME_EMAIL" ]; then
            warning "Email address cannot be empty"
        fi
    done
    
    # Update .env file
    sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" .env
    sed -i "s/^ACME_EMAIL=.*/ACME_EMAIL=${ACME_EMAIL}/" .env
    
    success "Domain configured: ${DOMAIN}"
    success "Email configured: ${ACME_EMAIL}"
    
    echo ""
    warning "Important DNS Configuration:"
    echo "  Make sure the following DNS records point to your server IP:"
    echo "    - A record: ${DOMAIN} → $(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")"
    echo "    - A record: *.${DOMAIN} → $(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP") (for device subdomains)"
    echo ""
    warning "Important Firewall Configuration:"
    echo "  Ensure the following ports are open:"
    echo "    - Port 80 (HTTP - for Let's Encrypt validation)"
    echo "    - Port 443 (HTTPS - for web access)"
    echo "    - Port 5912 (TCP - for device connections)"
    echo "    - Port 3478 (TCP/UDP - for TURN/WebRTC)"
    echo ""
    read -p "Press Enter to continue once DNS and firewall are configured..."
fi

# Prompt for other configuration
echo ""
info "Configuring additional settings..."

# Generate random password if not set
RTTYS_PASS=$(grep "^RTTYS_PASS=" .env | cut -d'=' -f2)
if [ "$RTTYS_PASS" = "StrongP@ssw0rd" ] || [ -z "$RTTYS_PASS" ]; then
    RTTYS_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    sed -i "s/^RTTYS_PASS=.*/RTTYS_PASS=${RTTYS_PASS}/" .env
    success "Generated web management password: ${RTTYS_PASS}"
else
    info "Using existing password from .env"
fi

# Generate random device token if not set
RTTYS_TOKEN=$(grep "^RTTYS_TOKEN=" .env | cut -d'=' -f2)
if [ "$RTTYS_TOKEN" = "DeviceTokenYouCanChangeMe" ] || [ -z "$RTTYS_TOKEN" ]; then
    RTTYS_TOKEN=$(openssl rand -hex 16)
    sed -i "s/^RTTYS_TOKEN=.*/RTTYS_TOKEN=${RTTYS_TOKEN}/" .env
    success "Generated device connection token: ${RTTYS_TOKEN}"
else
    info "Using existing device token from .env"
fi

# Start services
echo ""
info "Starting GLKVM Cloud services..."

if [ "$USE_CADDY" = true ]; then
    # Start with Caddy
    if docker compose version &> /dev/null; then
        docker compose -f docker-compose.yml -f docker-compose.caddy.yml down 2>/dev/null || true
        docker compose -f docker-compose.yml -f docker-compose.caddy.yml up -d
    else
        docker-compose -f docker-compose.yml -f docker-compose.caddy.yml down 2>/dev/null || true
        docker-compose -f docker-compose.yml -f docker-compose.caddy.yml up -d
    fi
    success "GLKVM Cloud started with Caddy automatic HTTPS"
else
    # Start without Caddy
    if docker compose version &> /dev/null; then
        docker compose down 2>/dev/null || true
        docker compose up -d
    else
        docker-compose down 2>/dev/null || true
        docker-compose up -d
    fi
    success "GLKVM Cloud started with self-signed certificates"
fi

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║          Installation Complete!                       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

if [ "$USE_CADDY" = true ]; then
    success "Access your GLKVM Cloud at: https://${DOMAIN}"
    info "Note: Initial certificate issuance may take a few moments"
    info "Check Caddy logs if needed: docker logs glkvm_caddy"
else
    success "Access your GLKVM Cloud at: https://$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')"
    warning "You will see a certificate warning in your browser (this is normal with self-signed certificates)"
fi

echo ""
echo "🔐 Login Credentials:"
echo "   Username: (leave empty)"
echo "   Password: ${RTTYS_PASS}"
echo ""
echo "📱 Device Connection Token: ${RTTYS_TOKEN}"
echo ""

info "Installation directory: ${INSTALL_DIR}"
info "To manage services:"
if [ "$USE_CADDY" = true ]; then
    echo "  Start:   cd ${INSTALL_DIR} && docker compose -f docker-compose.yml -f docker-compose.caddy.yml up -d"
    echo "  Stop:    cd ${INSTALL_DIR} && docker compose -f docker-compose.yml -f docker-compose.caddy.yml down"
    echo "  Logs:    docker logs glkvm_cloud / docker logs glkvm_caddy"
else
    echo "  Start:   cd ${INSTALL_DIR} && docker compose up -d"
    echo "  Stop:    cd ${INSTALL_DIR} && docker compose down"
    echo "  Logs:    docker logs glkvm_cloud"
fi

echo ""
info "For more information, visit: https://github.com/gl-inet/glkvm-cloud"
echo ""
