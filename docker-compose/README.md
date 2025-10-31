# Quick Start

This guide shows how to deploy **glkvm-cloud** using the provided Docker Compose environment template.

## Installation Methods

### Method 1: One-Line Installer (Recommended)

The easiest way to install GLKVM Cloud is using our automated installer script. This script will:
- Install Docker and Docker Compose if needed
- Clone the repository automatically
- Guide you through configuration with interactive prompts
- Check port availability
- Start all services
- Verify container health

**Run as root:**

```bash
curl -fsSL https://raw.githubusercontent.com/Admonstrator/glkvm-cloud/main/install.sh | sudo bash
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/Admonstrator/glkvm-cloud/main/install.sh | sudo bash
```

The installer will ask you:
1. Whether to use Caddy for automatic HTTPS (requires a domain name)
2. If using Caddy: your domain name and email for Let's Encrypt
3. Generate secure passwords automatically

**That's it!** The script handles everything and provides you with access credentials at the end.

### Method 2: Manual Docker Installation

If you prefer manual control or need to customize the installation:

1. **Clone the repository and prepare the environment template**

   ```bash
   git clone https://github.com/Admonstrator/glkvm-cloud.git
   cd glkvm-cloud/docker-compose/
   cp .env.example .env
   ```

2. **Configure environment variables**

   Edit `.env` and update the required parameters: 

   - `RTTYS_TOKEN`: device connection token (leave empty to use the default)
   - `RTTYS_PASS`: web management password (leave empty to use the default **StrongP@ssw0rd**)
   - `TURN_USER` / `TURN_PASS`: coturn authentication credentials (leave empty to use the default)
   - `GLKVM_ACCESS_IP`: glkvm cloud access address (leave empty to auto-detect at startup)

   **LDAP Authentication (Optional):**
   
   - `LDAP_ENABLED`: set to `true` to enable LDAP authentication (default: `false`)
   - `LDAP_SERVER`: LDAP server hostname or IP address
   - `LDAP_PORT`: LDAP server port (default: `389`, for TLS use `636`)
   - `LDAP_USE_TLS`: set to `true` to enable TLS encryption (default: `false`)
   - `LDAP_BIND_DN`: service account distinguished name
   - `LDAP_BIND_PASSWORD`: service account password
   - `LDAP_BASE_DN`: search base for user queries
   - `LDAP_USER_FILTER`: LDAP query filter (default: `(uid=%s)`)
   - `LDAP_ALLOWED_GROUPS`: comma-separated list of authorized groups (optional)
   - `LDAP_ALLOWED_USERS`: comma-separated list of authorized users (optional)

   ⚠️ **Note:** All configuration should be done in the `.env` file.
    You don’t need to modify `docker-compose.yml`, templates, or scripts directly.

3. **Start the services**

   ```bash
   docker-compose up -d
   ```

   If you modify `.env` or template files, make sure to apply the updates:

   ```bash
   docker-compose down && docker-compose up -d
   ```

4. **Platform Access**

   Once the installation is complete, access the platform via: 

    ```bash
    https://<your_server_public_ip>
    ```

## Caddy Setup (Automatic HTTPS with Let's Encrypt)

For production deployments with a custom domain, you can enable Caddy to automatically obtain and manage SSL/TLS certificates from Let's Encrypt.

### Prerequisites

- A domain name pointing to your server's public IP address
- Ports 80 and 443 must be accessible from the internet for Let's Encrypt validation
- Valid email address for certificate expiration notifications

### Configuration

#### Method 1: Using docker-compose.override.yml (Recommended)

This is the simplest method as Docker Compose automatically applies override files.

1. **Copy the override file template:**

   ```bash
   cd /path/to/glkvm-cloud
   cp docker-compose.override.yml.example docker-compose.override.yml
   ```

2. **Edit `docker-compose/.env` and configure domain settings:**

   ```bash
   cd docker-compose
   cp .env.example .env
   nano .env  # or use your preferred editor
   ```

   Set the following variables:
   ```bash
   # Set your domain name
   DOMAIN=kvm.example.com
   
   # Set your email for Let's Encrypt notifications
   ACME_EMAIL=admin@example.com
   ```

3. **Start services:**

   ```bash
   docker compose up -d
   ```

   Docker Compose will automatically use `docker-compose.override.yml` to enable Caddy and configure rttys appropriately.

#### Method 2: Using Docker Compose Profiles

This method doesn't require an override file but requires specifying the profile each time.

1. **Edit `docker-compose/.env` and configure domain settings** (same as Method 1 step 2)

2. **Start services with Caddy profile:**

   ```bash
   docker compose --profile caddy up -d
   ```

3. **Access your platform via domain:**

   ```
   https://kvm.example.com
   ```

### How Caddy Works

When enabled, Caddy will:

- Automatically obtain SSL/TLS certificates from Let's Encrypt
- Handle HTTP to HTTPS redirects
- Manage certificate renewals automatically (before expiration)
- Serve as a reverse proxy to the rttys container with TLS termination
- Support HTTP/3 (QUIC) for better performance

**Important: Backend Communication**

🔒 **Caddy terminates external TLS and communicates with rttys over internal HTTPS** for both security and performance:
- External clients connect to Caddy via HTTPS with Let's Encrypt certificates (secure)
- Caddy proxies requests to rttys via HTTPS within the Docker network using self-signed certificates
- Internal TLS provides encryption within the Docker network
- All containers communicate over Docker's internal network (isolated from external access)

This architecture is secure because:
1. Docker network is isolated and not accessible from outside
2. All external traffic is encrypted via Caddy's Let's Encrypt TLS certificates
3. Internal traffic between Caddy and rttys is also encrypted using HTTPS with self-signed certificates
4. Caddy is configured to accept self-signed certificates from rttys (tls_insecure_skip_verify)
5. This provides defense-in-depth with encryption at both external and internal boundaries

**Port Configuration:**

When Caddy is enabled, the port mapping changes as follows:

- **External (exposed to internet):**
  - Port 80 (HTTP) → Caddy handles ACME challenges and redirects to HTTPS
  - Port 443 (HTTPS) → Caddy reverse proxy to rttys Web UI (backend: HTTPS with self-signed cert)
  - Port 10443 (HTTPS) → Caddy reverse proxy to rttys HTTP Proxy (backend: HTTPS with self-signed cert)
  - Port 5912 (TCP) → Direct connection to rttys for device connections

- **Internal (within Docker network only):**
  - rttys Web UI runs on port 8443 in HTTPS mode with self-signed certificates (not exposed externally)
  - rttys HTTP Proxy runs on port 18443 in HTTPS mode with self-signed certificates (not exposed externally)
  - Caddy proxies external HTTPS requests to these internal HTTPS ports

This architecture ensures that:
1. All web traffic goes through Caddy for proper SSL/TLS termination with trusted certificates
2. Internal traffic between containers is encrypted for additional security
3. No port conflicts between Caddy and rttys
4. Device connections (port 5912) bypass Caddy for optimal performance
5. **Internal TLS between Caddy and rttys** - HTTPS with self-signed certificates is used for internal communication

### Wildcard Certificates (Optional)

If you need wildcard certificates (e.g., `*.example.com`) for device-specific subdomains:

1. The current Caddyfile template includes a wildcard configuration
2. Wildcard certificates require **DNS-01 challenge** instead of HTTP-01
3. You'll need to configure Caddy with your DNS provider's API credentials
4. See [Caddy DNS Challenge Documentation](https://caddyserver.com/docs/automatic-https#dns-challenge) for details

### Switching Between Modes

**To disable Caddy and use self-signed certificates:**

Method 1 users:
```bash
# Remove or rename the override file
mv docker-compose.override.yml docker-compose.override.yml.disabled
docker compose down
docker compose up -d
```

Method 2 users:
```bash
docker compose down
docker compose up -d
```

**To re-enable Caddy:**

Method 1 users:
```bash
# Restore the override file
mv docker-compose.override.yml.disabled docker-compose.override.yml
docker compose down
docker compose up -d
```

Method 2 users:
```bash
docker compose down
docker compose --profile caddy up -d
```

### Troubleshooting

**Certificate issuance fails:**
- Verify your domain points to the correct server IP
- Ensure ports 80 and 443 are accessible from the internet
- Check Caddy logs: `docker logs glkvm_caddy`
- Verify DOMAIN and ACME_EMAIL are set correctly in `.env`

**Port conflicts:**
- If you have another service using port 80 or 443, you need to stop it first
- Caddy requires both ports for automatic HTTPS

**Certificate not updating:**
- Caddy automatically renews certificates before they expire
- Check logs if you encounter issues: `docker logs glkvm_caddy`
