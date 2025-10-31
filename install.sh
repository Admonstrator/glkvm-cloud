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

# Check if required commands are available
info "Checking required tools..."
if ! command -v openssl &> /dev/null; then
    warning "openssl not found. Installing openssl..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y openssl
    elif command -v yum &> /dev/null; then
        yum install -y openssl
    elif command -v dnf &> /dev/null; then
        dnf install -y openssl
    else
        error "Cannot install openssl. Please install it manually."
        exit 1
    fi
    success "openssl installed successfully"
fi

# Function to check if a port is in use
check_port() {
    local port=$1
    local service=$2
    if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        warning "Port ${port} (${service}) is already in use. This may cause conflicts."
        return 1
    fi
    return 0
}

# Check critical ports
info "Checking if required ports are available..."
PORTS_OK=true
check_port 5912 "Device connection" || PORTS_OK=false
check_port 3478 "TURN server" || PORTS_OK=false

if [ "$PORTS_OK" = false ]; then
    echo ""
    warning "Some required ports are already in use."
    read -p "Do you want to continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        error "Installation aborted. Please free up the required ports and try again."
        exit 1
    fi
fi

# Create installation directory
INSTALL_DIR="${HOME}/glkvm_cloud"
info "Creating installation directory at ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"

# Clone or update repository
if [ -d "${INSTALL_DIR}/.git" ]; then
    info "Updating existing installation..."
    cd "${INSTALL_DIR}"
    git pull
else
    info "Cloning GLKVM Cloud repository..."
    if ! command -v git &> /dev/null; then
        warning "Git not found. Installing Git..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y git
        elif command -v yum &> /dev/null; then
            yum install -y git
        elif command -v dnf &> /dev/null; then
            dnf install -y git
        else
            error "Cannot install git. Please install git manually and run the script again."
            exit 1
        fi
        success "Git installed successfully"
    fi
    
    git clone https://github.com/Admonstrator/glkvm-cloud.git "${INSTALL_DIR}"
    if [ $? -ne 0 ]; then
        error "Failed to clone repository. Please check your internet connection."
        exit 1
    fi
    success "Repository cloned successfully"
fi

# Navigate to installation directory
cd "${INSTALL_DIR}" || exit 1

# Check if docker-compose directory exists
if [ ! -d "docker-compose" ]; then
    error "docker-compose directory not found in ${INSTALL_DIR}"
    exit 1
fi

cd docker-compose

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
    
    # Check Caddy-specific ports early
    info "Checking Caddy-specific ports..."
    CADDY_PORTS_OK=true
    check_port 80 "HTTP (Caddy)" || CADDY_PORTS_OK=false
    check_port 443 "HTTPS (Caddy)" || CADDY_PORTS_OK=false
    check_port 10443 "HTTP Proxy (Caddy)" || CADDY_PORTS_OK=false
    
    if [ "$CADDY_PORTS_OK" = false ]; then
        error "Required Caddy ports (80, 443, 10443) are in use. Cannot continue with Caddy setup."
        read -p "Do you want to continue WITHOUT Caddy (self-signed certificates)? (y/N): " use_no_caddy
        if [[ "$use_no_caddy" =~ ^[Yy]$ ]]; then
            USE_CADDY=false
            warning "Continuing without Caddy. Self-signed certificates will be used."
        else
            error "Installation aborted. Please free up ports 80, 443, and 10443 or choose not to use Caddy."
            exit 1
        fi
    fi
fi

if [ "$USE_CADDY" = true ]; then
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

# Wait for containers to be healthy
echo ""
info "Checking container health (this may take a moment)..."
sleep 5

# Check if containers are running
RTTYS_RUNNING=$(docker ps --filter "name=glkvm_cloud" --filter "status=running" --format "{{.Names}}")
COTURN_RUNNING=$(docker ps --filter "name=glkvm_coturn" --filter "status=running" --format "{{.Names}}")

if [ -z "$RTTYS_RUNNING" ]; then
    error "GLKVM Cloud container (glkvm_cloud) is not running!"
    echo "Check logs with: docker logs glkvm_cloud"
    exit 1
fi
success "GLKVM Cloud container is running"

if [ -z "$COTURN_RUNNING" ]; then
    warning "TURN server container (glkvm_coturn) is not running"
    warning "WebRTC functionality may not work properly"
else
    success "TURN server container is running"
fi

if [ "$USE_CADDY" = true ]; then
    CADDY_RUNNING=$(docker ps --filter "name=glkvm_caddy" --filter "status=running" --format "{{.Names}}")
    if [ -z "$CADDY_RUNNING" ]; then
        error "Caddy container (glkvm_caddy) is not running!"
        echo "Check logs with: docker logs glkvm_caddy"
        exit 1
    fi
    success "Caddy container is running"
    
    # Check if Caddy can reach rttys
    info "Verifying Caddy can communicate with GLKVM Cloud..."
    sleep 3
    CADDY_LOGS=$(docker logs glkvm_caddy 2>&1 | tail -20)
    if echo "$CADDY_LOGS" | grep -qi "error\|failed\|refused"; then
        warning "Detected potential connection issues in Caddy logs:"
        echo "$CADDY_LOGS" | grep -i "error\|failed\|refused"
        warning "Please check: docker logs glkvm_caddy"
    else
        success "Caddy is communicating with GLKVM Cloud successfully"
    fi
fi

# Check container logs for any startup errors
info "Checking for startup errors..."
RTTYS_ERRORS=$(docker logs glkvm_cloud 2>&1 | grep -i "error\|fatal" | tail -5)
if [ -n "$RTTYS_ERRORS" ]; then
    warning "Detected errors in GLKVM Cloud logs:"
    echo "$RTTYS_ERRORS"
    warning "Check full logs with: docker logs glkvm_cloud"
else
    success "No critical errors detected in logs"
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
