# Glow Persistence API — Installation & Reference

## Prerequisites

| Requirement | Version |
|-------------|---------|
| OS | Debian 12 or Ubuntu 22.04 LTS (other Linux distros work with minor adjustments) |
| .NET SDK | 8.0 |
| MySQL Server | 8.0+ |
| nginx | any recent version (installed by setup script) |
| certbot | any recent version (installed by setup script) |
| Domain name | A public DNS A record pointing to your server (required for SSL) |
| Access | `sudo` / root on the server |

---

## Automated Installation

Run the setup script from the repository root on your server:

```bash
sudo bash deployment/setup.sh
```

> **Before running:** edit the `DOMAIN` and `EMAIL` variables at the top of
> `setup.sh` (in addition to `DB_PASS`). `DOMAIN` must resolve to your server's
> public IP so that Let's Encrypt can issue the certificate.

The script will:
1. Install the .NET 8 SDK (if not present)
2. Install MySQL Server (if not present)
3. Create the database, user, and grant privileges
4. Build and publish the application to `/opt/glowpersistenceapi`
5. Install and start the `glowpersistence-api` systemd service
6. Install nginx and deploy the reverse-proxy site config
7. Install certbot and obtain a Let's Encrypt TLS certificate (HTTP → HTTPS redirect enabled)
8. Restart the application service

> **Security note:** Edit the `DB_PASS`, `DOMAIN`, and `EMAIL` variables at the
> top of `setup.sh` before running it. Never use the default placeholder
> password in production.

---

## Manual Installation

### Step 1 — Install .NET 8 SDK

```bash
# Ubuntu 22.04 / Debian 12
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
     -O /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0
dotnet --version   # should print 8.0.x
```

### Step 2 — Install MySQL Server

```bash
sudo apt-get install -y mysql-server
sudo systemctl enable --now mysql
```

### Step 3 — Provision the Database

Log in as the MySQL root user and run the following SQL:

```sql
-- Create the database (UTF-8 full Unicode support)
CREATE DATABASE IF NOT EXISTS `glowpersistence`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Create a dedicated application user
CREATE USER IF NOT EXISTS 'glowapi'@'localhost'
    IDENTIFIED BY 'YOUR_STRONG_PASSWORD_HERE';

-- Grant only the privileges the application needs
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
    ON `glowpersistence`.*
    TO 'glowapi'@'localhost';

FLUSH PRIVILEGES;
```

To run these statements interactively:

```bash
sudo mysql -u root
```

Or as a one-liner (useful in scripts):

```bash
sudo mysql -u root <<'EOF'
CREATE DATABASE IF NOT EXISTS `glowpersistence`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glowapi'@'localhost'
    IDENTIFIED BY 'YOUR_STRONG_PASSWORD_HERE';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES
    ON `glowpersistence`.* TO 'glowapi'@'localhost';
FLUSH PRIVILEGES;
EOF
```

Verify the user and database were created:

```bash
sudo mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User='glowapi';"
sudo mysql -u root -e "SHOW DATABASES LIKE 'glowpersistence';"
```

### Step 4 — Configure the Application

Edit `api/GlowPersistenceAPI/appsettings.json` and update the connection
string with the password you chose above:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Port=3306;Database=glowpersistence;User=glowapi;Password=YOUR_STRONG_PASSWORD_HERE;"
  }
}
```

### Step 5 — Build and Publish

```bash
dotnet publish api/GlowPersistenceAPI/GlowPersistenceAPI.csproj \
    --configuration Release \
    --output /opt/glowpersistenceapi \
    --runtime linux-x64 \
    --self-contained false
```

Copy the production `appsettings.json` (with the real password) to the
publish output directory:

```bash
sudo cp api/GlowPersistenceAPI/appsettings.json /opt/glowpersistenceapi/appsettings.json
```

### Step 6 — Install the systemd Service

```bash
sudo cp deployment/glowpersistence-api.service \
        /etc/systemd/system/glowpersistence-api.service
sudo systemctl daemon-reload
sudo systemctl enable glowpersistence-api
sudo systemctl start  glowpersistence-api
sudo systemctl status glowpersistence-api
```

The application applies Entity Framework migrations automatically on
first start, creating the `GlowRecords` table inside `glowpersistence`.

---

## Verifying the Installation

```bash
# Service health
sudo systemctl status glowpersistence-api

# API health endpoint
curl https://your-domain.example.com/health
# → {"status":"Healthy","results":{"GlowDbContext":{"status":"Healthy",...}}}

# API glow health endpoint
curl https://your-domain.example.com/api/glow/health
# → {"status":"healthy","timestamp":"..."}

# Save a test record (replace UUID with any valid UUID)
curl -X POST https://your-domain.example.com/api/glow/550e8400-e29b-41d4-a716-446655440000 \
     -H "Content-Type: application/json" \
     -d '{"data":"4|6;0.5|0.3|0.0|0.1|0.0|0.0"}'

# Retrieve it back
curl https://your-domain.example.com/api/glow/550e8400-e29b-41d4-a716-446655440000

# Delete it
curl -X DELETE https://your-domain.example.com/api/glow/550e8400-e29b-41d4-a716-446655440000
```

---

## Service Management

| Action | Command |
|--------|---------|
| Check status | `sudo systemctl status glowpersistence-api` |
| Start | `sudo systemctl start glowpersistence-api` |
| Stop | `sudo systemctl stop glowpersistence-api` |
| Restart | `sudo systemctl restart glowpersistence-api` |
| Follow logs | `sudo journalctl -u glowpersistence-api -f` |
| View recent logs | `sudo journalctl -u glowpersistence-api -n 100` |

---

## API Endpoint Reference

### `GET /api/glow/{objectId}`

Retrieve saved glow data for a Second Life object.

**Response 200:**
```json
{
  "objectId": "550e8400-e29b-41d4-a716-446655440000",
  "data": "4|6;0.5|0.3|0.0|0.1|0.0|0.0",
  "updatedAt": "2024-01-15T12:34:56Z"
}
```

**Response 404:** No record found for this UUID.

---

### `POST /api/glow/{objectId}`

Save or update glow data. Creates the record if it doesn't exist; updates
it otherwise.

**Request body:**
```json
{ "data": "4|6;0.5|0.3|0.0|0.1|0.0|0.0" }
```

**Response 200:**
```json
{
  "objectId": "550e8400-e29b-41d4-a716-446655440000",
  "message": "Glow data saved successfully.",
  "updatedAt": "2024-01-15T12:34:56Z"
}
```

---

### `DELETE /api/glow/{objectId}`

Delete glow data for an object.

**Response 200:**
```json
{ "message": "Glow data deleted successfully." }
```

---

### `GET /api/glow/health`

Simple API-level health check (no database query).

**Response 200:**
```json
{ "status": "healthy", "timestamp": "2024-01-15T12:34:56Z" }
```

---

### `GET /health`

Full application health check including database connectivity.

---

## Data Format

```
<faceCounts>;<glowValues>
```

| Part | Description | Example |
|------|-------------|---------|
| `faceCounts` | Pipe-delimited integer face count for each child prim | `4\|6\|8` |
| `glowValues` | Pipe-delimited float glow value per face, in prim order | `0.5\|0.3\|0.0\|...` |

Example combined: `4|6;0.5|0.0|0.0|0.0|0.3|0.1|0.0|0.0|0.0|0.0`

---

## Security Considerations

- Change `DB_PASS` / the connection string password before deploying.
- The Kestrel app binds to `127.0.0.1:5005` and is only reachable via the nginx
  reverse proxy. nginx terminates TLS on port 443 and certbot enforces
  HTTP → HTTPS redirects.
- TLS certificates are issued by Let's Encrypt and auto-renewed by certbot's
  systemd timer.
- The application user `glowapi` is granted only the privileges it needs; avoid
  using the MySQL root account in the connection string.
- CORS is open (`AllowAnyOrigin`) because Second Life simulator IPs are not
  predictable. If your use case allows restricting origins, tighten the CORS
  policy in `Program.cs`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Service fails to start | Wrong DB password in `appsettings.json` | Update password, restart service |
| `Access denied for user 'glowapi'@'localhost'` | User/grant not applied | Re-run Step 3 SQL |
| `Unknown database 'glowpersistence'` | Database not created | Run `CREATE DATABASE` statement |
| HTTP 500 from API | Check `journalctl -u glowpersistence-api` | Fix logged error |
| `dotnet: command not found` | .NET SDK not installed | Re-run Step 1 |
