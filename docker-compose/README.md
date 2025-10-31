# Quick Start

 This guide shows how to deploy **glkvm-cloud** using the provided Docker Compose environment template. 

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

1. **Edit `.env` file and configure domain settings:**

   ```bash
   # Set your domain name
   DOMAIN=kvm.example.com
   
   # Set your email for Let's Encrypt notifications
   ACME_EMAIL=admin@example.com
   ```

2. **Start services with Caddy enabled:**

   ```bash
   docker-compose -f docker-compose.yml -f docker-compose.caddy.yml up -d
   ```

   Or for subsequent restarts:

   ```bash
   docker-compose -f docker-compose.yml -f docker-compose.caddy.yml down
   docker-compose -f docker-compose.yml -f docker-compose.caddy.yml up -d
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
- Serve as a reverse proxy to the rttys container
- Support HTTP/3 (QUIC) for better performance

### Wildcard Certificates (Optional)

If you need wildcard certificates (e.g., `*.example.com`) for device-specific subdomains:

1. The current Caddyfile template includes a wildcard configuration
2. Wildcard certificates require **DNS-01 challenge** instead of HTTP-01
3. You'll need to configure Caddy with your DNS provider's API credentials
4. See [Caddy DNS Challenge Documentation](https://caddyserver.com/docs/automatic-https#dns-challenge) for details

### Switching Between Modes

**To disable Caddy and use self-signed certificates:**

```bash
docker-compose -f docker-compose.yml down
docker-compose up -d
```

**To re-enable Caddy:**

```bash
docker-compose down
docker-compose -f docker-compose.yml -f docker-compose.caddy.yml up -d
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
