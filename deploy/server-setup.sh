#!/usr/bin/env bash
# One-time setup for the Ubuntu host (217.77.7.98). Run as a sudo-capable user:
#
#   scp -r deploy you@217.77.7.98:~/polticool-deploy
#   ssh you@217.77.7.98 'sudo bash ~/polticool-deploy/server-setup.sh'
#
# Idempotent: safe to re-run.
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
APP_DIR=/opt/polticool
DOMAIN=polticool.nathanspackman.com
HERE="$(cd "$(dirname "$0")" && pwd)"

# --- Docker Engine + compose plugin (official apt repo) ---------------------
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# --- Deploy user (GitHub Actions SSHes in as this user) ---------------------
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"

# --- App directory -----------------------------------------------------------
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"
cp "$HERE/docker-compose.yml" "$APP_DIR/docker-compose.yml"
if [ ! -f "$APP_DIR/.env" ]; then
  cat > "$APP_DIR/.env" <<EOF
POSTGRES_PASSWORD=$(openssl rand -hex 24)
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')
ANTHROPIC_API_KEY=
EOF
  echo ">> Created $APP_DIR/.env. Add ANTHROPIC_API_KEY to it."
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"
chmod 600 "$APP_DIR/.env"

# --- Apache reverse proxy + TLS ---------------------------------------------
apt-get install -y apache2 certbot python3-certbot-apache
a2enmod proxy proxy_http proxy_wstunnel headers rewrite ssl
cp "$HERE/apache/polticool.conf" /etc/apache2/sites-available/polticool.conf
a2ensite polticool
apache2ctl configtest
systemctl reload apache2

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot --apache -d "$DOMAIN" --non-interactive --agree-tos --redirect \
    --register-unsafely-without-email || \
    echo ">> certbot failed. Check DNS, then run: certbot --apache -d $DOMAIN"
fi

echo
echo "Done. Next steps:"
echo "  1. Add the CI public key to /home/$DEPLOY_USER/.ssh/authorized_keys"
echo "  2. Fill in ANTHROPIC_API_KEY in $APP_DIR/.env"
echo "  3. Push to main (or run the Deploy workflow manually)"
