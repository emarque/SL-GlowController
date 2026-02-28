# SL-GlowController

GlowController is an add-on to the ScheduledVisibility set of scripts for saving glow settings on hide and reapplying on show.

## Features

- Saves per-face glow values across all child prims in a linkset
- Restores glow exactly as it was when the object is shown again
- Persists data to a cloud REST API keyed by the object's UUID
- Integrates seamlessly with the ScheduledVisibility script
- Supports touch-to-check status
- Full error handling and retry-friendly HTTP design

## Repository Structure

```
SL-GlowController/
├── scripts/
│   └── GlowController.lsl        # LSL script — drop into your SL object
├── api/
│   └── GlowPersistenceAPI/
│       ├── Program.cs             # ASP.NET Core 8 app entry point
│       ├── Controllers/
│       │   └── GlowController.cs  # REST endpoints + EF Core DbContext
│       ├── GlowPersistenceAPI.csproj
│       └── appsettings.json       # Connection string & Kestrel config
├── deployment/
│   ├── glowpersistence-api.service  # systemd unit file
│   └── setup.sh                     # One-command server setup
├── configs/
│   └── GlowController_Config.txt    # Example _ScheduleCfg notecard
└── docs/
    ├── API_README.md       # Detailed API & server setup guide
    └── LSL_INTEGRATION.md  # LSL integration guide
```

## Quick Start

### 1 — Deploy the API server

```bash
# On a Debian/Ubuntu server (requires root)
sudo bash deployment/setup.sh
```

See [docs/API_README.md](docs/API_README.md) for full manual installation
instructions, including MySQL database provisioning.

### 2 — Configure the LSL script

Open `scripts/GlowController.lsl` and set `API_BASE_URL` to your server:

```lsl
string API_BASE_URL = "http://YOUR_SERVER_IP:5000/api/glow";
```

### 3 — Add scripts to your Second Life object

1. Drop `GlowController.lsl` into the object's inventory.
2. Drop `ScheduledVisibility` (from that project) into the same object.
3. Add a `_ScheduleCfg` notecard using the example in
   `configs/GlowController_Config.txt`.

See [docs/LSL_INTEGRATION.md](docs/LSL_INTEGRATION.md) for the full guide.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/glow/{objectId}` | Retrieve saved glow data |
| `POST` | `/api/glow/{objectId}` | Save or update glow data |
| `DELETE` | `/api/glow/{objectId}` | Delete glow data |
| `GET` | `/api/glow/health` | API health check |
| `GET` | `/health` | Application health check (includes DB) |

`{objectId}` must be a valid Second Life UUID (e.g. `550e8400-e29b-41d4-a716-446655440000`).

### POST body format

```json
{ "data": "4|6|8;0.5|0.3|0.0|0.1|0.0|0.0|0.2|0.0|0.0" }
```

The `data` field is a semicolon-separated string:
- **Left of `;`** — pipe-delimited face counts per child prim (e.g. `4|6|8`)
- **Right of `;`** — pipe-delimited glow float values in prim/face order

## Database

The API uses **MySQL** (via Pomelo Entity Framework Core provider).  
Entity Framework migrations are applied automatically on startup.

See [docs/API_README.md](docs/API_README.md) for provisioning steps.

## License

MIT
