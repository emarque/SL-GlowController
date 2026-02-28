#!/usr/bin/env bash
# setup.sh - Automated deployment script for Glow Persistence API
# Tested on Debian 12 / Ubuntu 22.04 LTS
set -euo pipefail

# ─────────────────────────────────────────────
# Configuration — edit these before running
# ─────────────────────────────────────────────
DB_NAME="glowpersistence"
DB_USER="glowapi"
DB_PASS="CHANGE_ME_STRONG_PASSWORD"   # ← change this
APP_DIR="/opt/glowpersistenceapi"
SERVICE_NAME="glowpersistence-api"
APP_PORT="5005"
DOMAIN="your-domain.example.com"      # ← set your public domain for SSL
EMAIL="admin@example.com"             # ← set your email for Let's Encrypt

echo "=== Glow Persistence API Setup ==="
echo "Database : ${DB_NAME}"
echo "App dir  : ${APP_DIR}"
echo ""

# ─────────────────────────────────────────────
# Validate required configuration
# ─────────────────────────────────────────────
if [[ "${DB_PASS}" == "CHANGE_ME_STRONG_PASSWORD" ]]; then
    echo "ERROR: DB_PASS is still set to the default placeholder. Edit setup.sh before running." >&2
    exit 1
fi
if [[ "${DOMAIN}" == "your-domain.example.com" ]]; then
    echo "ERROR: DOMAIN is still set to the default placeholder. Edit setup.sh before running." >&2
    exit 1
fi
if [[ "${EMAIL}" == "admin@example.com" ]]; then
    echo "ERROR: EMAIL is still set to the default placeholder. Edit setup.sh before running." >&2
    exit 1
fi

# ─────────────────────────────────────────────
# 1. Install .NET 8 SDK
# ─────────────────────────────────────────────
echo "[1/8] Installing .NET 8 SDK..."
if ! command -v dotnet &>/dev/null; then
    # Use the Microsoft package feed
    wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
        -O /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb
    rm /tmp/packages-microsoft-prod.deb
    apt-get update -qq
    apt-get install -y dotnet-sdk-8.0
else
    echo "  .NET already installed: $(dotnet --version)"
fi

# ─────────────────────────────────────────────
# 2. Install MySQL Server
# ─────────────────────────────────────────────
echo "[2/8] Installing MySQL Server..."
if ! command -v mysql &>/dev/null; then
    apt-get install -y mysql-server
    systemctl enable mysql
    systemctl start mysql
else
    echo "  MySQL already installed: $(mysql --version)"
fi

# ─────────────────────────────────────────────
# 3. Provision MySQL database and user
# ─────────────────────────────────────────────
echo "[3/8] Provisioning MySQL database '${DB_NAME}' and user '${DB_USER}'..."
mysql --user=root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
    ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF
echo "  Database provisioned."

# ─────────────────────────────────────────────
# 4. Build and publish the application
# ─────────────────────────────────────────────
echo "[4/8] Building and publishing application..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../api/GlowPersistenceAPI"

dotnet publish "${PROJECT_DIR}/GlowPersistenceAPI.csproj" \
    --configuration Release \
    --output "${APP_DIR}" \
    --runtime linux-x64 \
    --self-contained false

# Write the production connection string into the deployed appsettings
CONNECTION_STRING="Server=localhost;Port=3306;Database=${DB_NAME};User=${DB_USER};Password=${DB_PASS};"
cat > "${APP_DIR}/appsettings.json" <<JSON
{
  "ConnectionStrings": {
    "DefaultConnection": "${CONNECTION_STRING}"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://127.0.0.1:${APP_PORT}"
      }
    }
  }
}
JSON
echo "  Application published to ${APP_DIR}."

# ─────────────────────────────────────────────
# 5. Install systemd service
# ─────────────────────────────────────────────
echo "[5/8] Installing systemd service '${SERVICE_NAME}'..."
cp "${SCRIPT_DIR}/glowpersistence-api.service" \
    "/etc/systemd/system/${SERVICE_NAME}.service"

# Patch the ExecStart path in the installed service file
sed -i "s|/opt/glowpersistenceapi|${APP_DIR}|g" \
    "/etc/systemd/system/${SERVICE_NAME}.service"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

# ─────────────────────────────────────────────
# 6. Install and configure nginx
# ─────────────────────────────────────────────
echo "[6/8] Installing and configuring nginx..."
apt-get install -y nginx

NGINX_CONF="/etc/nginx/sites-available/${SERVICE_NAME}"
cp "${SCRIPT_DIR}/glowpersistence-api.nginx" "${NGINX_CONF}"
sed -i "s/server_name _;/server_name ${DOMAIN};/" "${NGINX_CONF}"
ln -sf "${NGINX_CONF}" "/etc/nginx/sites-enabled/${SERVICE_NAME}"
rm -f /etc/nginx/sites-enabled/default

nginx -t  # aborts the script on invalid config (set -e)
systemctl enable nginx
systemctl restart nginx
echo "  nginx configured and running."

# ─────────────────────────────────────────────
# 7. Obtain SSL certificate with certbot
# ─────────────────────────────────────────────
echo "[7/8] Obtaining SSL certificate with certbot..."
apt-get install -y certbot python3-certbot-nginx
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --domains "${DOMAIN}" \
    --redirect
echo "  SSL certificate installed. Auto-renewal is handled by certbot's systemd timer."

# ─────────────────────────────────────────────
# 8. Start the service
# ─────────────────────────────────────────────
echo "[8/8] Starting service..."
systemctl restart "${SERVICE_NAME}"
sleep 2
systemctl status "${SERVICE_NAME}" --no-pager

echo ""
echo "=== Setup complete ==="
echo "API is available at https://${DOMAIN}"
echo "Health check : curl https://${DOMAIN}/health"
echo "Swagger UI   : https://${DOMAIN}/swagger  (development mode only)"
echo ""
echo "Useful commands:"
echo "  systemctl status  ${SERVICE_NAME}"
echo "  systemctl restart ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -f"
