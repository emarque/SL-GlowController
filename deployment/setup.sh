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

echo "=== Glow Persistence API Setup ==="
echo "Database : ${DB_NAME}"
echo "App dir  : ${APP_DIR}"
echo ""

# ─────────────────────────────────────────────
# 1. Install .NET 8 SDK
# ─────────────────────────────────────────────
echo "[1/7] Installing .NET 8 SDK..."
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
echo "[2/7] Installing MySQL Server..."
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
echo "[3/7] Provisioning MySQL database '${DB_NAME}' and user '${DB_USER}'..."
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
echo "[4/7] Building and publishing application..."
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
        "Url": "http://0.0.0.0:${APP_PORT}"
      }
    }
  }
}
JSON
echo "  Application published to ${APP_DIR}."

# ─────────────────────────────────────────────
# 5. Install systemd service
# ─────────────────────────────────────────────
echo "[5/7] Installing systemd service '${SERVICE_NAME}'..."
cp "${SCRIPT_DIR}/glowpersistence-api.service" \
    "/etc/systemd/system/${SERVICE_NAME}.service"

# Patch the ExecStart path in the installed service file
sed -i "s|/opt/glowpersistenceapi|${APP_DIR}|g" \
    "/etc/systemd/system/${SERVICE_NAME}.service"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

# ─────────────────────────────────────────────
# 6. Start the service
# ─────────────────────────────────────────────
echo "[6/6] Starting service..."
systemctl restart "${SERVICE_NAME}"
sleep 2
systemctl status "${SERVICE_NAME}" --no-pager

echo ""
echo "=== Setup complete ==="
echo "API is listening on http://0.0.0.0:${APP_PORT}"
echo "Health check : curl http://localhost:${APP_PORT}/health"
echo "Swagger UI   : http://<server-ip>:${APP_PORT}/swagger  (development mode only)"
echo ""
echo "Useful commands:"
echo "  systemctl status  ${SERVICE_NAME}"
echo "  systemctl restart ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -f"
