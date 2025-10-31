#!/bin/sh
set -e

# -------- GLKVM access IP resolver (IPv4) --------
resolve_glkvm_access_ip() {
  # 1) Prefer user-provided env
  if [ -n "${GLKVM_ACCESS_IP:-}" ]; then
    echo "${GLKVM_ACCESS_IP}"
    return 0
  fi

  is_ipv4() { echo "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; }
  try_cmd() {
    val="$("$@" 2>/dev/null | tr -d '\r\n')"
    if is_ipv4 "$val"; then
      echo "$val"; return 0
    fi
    return 1
  }

  # 2) Best-effort auto-detection from multiple sources
  if command -v wget >/dev/null 2>&1; then
    try_cmd wget -qO- --timeout=3 https://api.ipify.org && return 0
    try_cmd wget -qO- --timeout=3 https://ifconfig.me && return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    try_cmd curl -fsS --max-time 3 https://api.ipify.org && return 0
    try_cmd curl -fsS --max-time 3 https://ifconfig.me && return 0
  fi
  if command -v dig >/dev/null 2>&1; then
    try_cmd sh -c "dig +short -4 myip.opendns.com @resolver1.opendns.com" && return 0
  fi

  # 3) Fallback
  echo "127.0.0.1"
}

# -------- Minimal template renderer ({{KEY}}) --------
render() {
  in="$1"; out="$2"; shift 2
  cp "$in" "$out"
  for key in "$@"; do
    val="$(printenv "$key" || true)"
    # Special-case: GLKVM_ACCESS_IP prefers env, else auto-detect once
    if [ "$key" = "GLKVM_ACCESS_IP" ] && [ -z "$val" ]; then
      val="$(resolve_glkvm_access_ip)"
    fi
    # Escape '/' and '&' for sed
    esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
    sed -i "s/{{${key}}}/${esc}/g" "$out"
  done
}

# -------- Dispatch by first arg --------
case "$1" in
  rttys)
    : "${RTTYS_DEVICE_PORT:=5912}"
    : "${RTTYS_WEBUI_PORT:=443}"
    : "${RTTYS_HTTP_PROXY_PORT:=10443}"
    : "${TURN_PORT:=3478}"

    render /tpl/rttys.conf.tmpl /home/rttys.conf \
      RTTYS_TOKEN RTTYS_PASS \
      GLKVM_ACCESS_IP TURN_PORT TURN_USER TURN_PASS \
      RTTYS_DEVICE_PORT RTTYS_WEBUI_PORT RTTYS_HTTP_PROXY_PORT \
      LDAP_ENABLED LDAP_SERVER LDAP_PORT LDAP_USE_TLS \
      LDAP_BIND_DN LDAP_BIND_PASSWORD LDAP_BASE_DN \
      LDAP_USER_FILTER LDAP_ALLOWED_GROUPS LDAP_ALLOWED_USERS

    exec rttys -c /home/rttys.conf
    ;;

  coturn)
    : "${TURN_PORT:=3478}"

    mkdir -p /tmp
    render /tpl/turnserver.conf.tmpl /tmp/turnserver.conf \
      GLKVM_ACCESS_IP TURN_PORT TURN_USER TURN_PASS

    exec turnserver -c /tmp/turnserver.conf
    ;;

  caddy)
    : "${RTTYS_WEBUI_INTERNAL_PORT:=8443}"
    : "${RTTYS_HTTP_PROXY_INTERNAL_PORT:=18443}"

    # Check if DOMAIN is set
    if [ -z "${DOMAIN:-}" ]; then
      echo "ERROR: DOMAIN environment variable is required for Caddy"
      echo "Please set DOMAIN in your .env file"
      exit 1
    fi

    # Check if ACME_EMAIL is set
    if [ -z "${ACME_EMAIL:-}" ]; then
      echo "WARNING: ACME_EMAIL not set. Let's Encrypt notifications will be disabled."
      echo "It's recommended to set ACME_EMAIL in your .env file"
    fi

    mkdir -p /etc/caddy
    render /tpl/Caddyfile.tmpl /etc/caddy/Caddyfile \
      DOMAIN ACME_EMAIL RTTYS_WEBUI_INTERNAL_PORT RTTYS_HTTP_PROXY_INTERNAL_PORT

    echo "Starting Caddy with automatic HTTPS for domain: ${DOMAIN}"
    echo "ACME email: ${ACME_EMAIL:-not set}"
    echo "Proxying Web UI from rttys:${RTTYS_WEBUI_INTERNAL_PORT}"
    echo "Proxying HTTP Proxy from rttys:${RTTYS_HTTP_PROXY_INTERNAL_PORT}"
    
    exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
    ;;

  *)
    exec "$@"
    ;;
esac
