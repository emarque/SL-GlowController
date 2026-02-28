# LSL Integration Guide

## Overview

`GlowController.lsl` is a Second Life script that automatically saves and
restores glow values on all child prims of a linkset. It works alongside the
**ScheduledVisibility** script to turn glow off when an object is hidden and
turn it back on — exactly as it was — when the object is shown again.

---

## Adding the Script to an Object

1. Open the object's **Build** panel in Second Life.
2. Go to the **Contents** tab.
3. Drag `GlowController.lsl` from your inventory into the object's contents.
4. The script will print its UUID and confirm it is ready in your local chat.

---

## Configuring with ScheduledVisibility

Place the following settings in your `_ScheduleCfg` notecard (see
`configs/GlowController_Config.txt` for a complete example):

```
actionMode=1
actionScript=GlowController
showFunction=show
hideFunction=hide
```

| Key | Value | Effect |
|-----|-------|--------|
| `actionMode` | `1` | Delegate show/hide actions to a linked script |
| `actionScript` | `GlowController` | Name of the script to message |
| `showFunction` | `show` | Message sent when the object becomes visible |
| `hideFunction` | `hide` | Message sent when the object is hidden |

When ScheduledVisibility sends a `hide` link message, GlowController reads the
current glow on every face of every child prim, saves it to the API, then sets
all glow to `0.0`. When it sends `show`, GlowController fetches the stored
data from the API and restores the original values.

---

## Configuring the API URL

At the top of `GlowController.lsl`, set the base URL of your deployed API:

```lsl
string API_BASE_URL = "http://YOUR_SERVER_IP:5005/api/glow";
```

Replace `YOUR_SERVER_IP` with the public IP or hostname of your server.

---

## Function Reference

### `saveAndDisableGlow()`

- Iterates over all child prims (skips root prim, link number 1).
- Reads the glow value for every face of every child prim.
- Builds a data string: `"faceCounts;glowValues"` (pipe-delimited).
- POSTs the data to `API_BASE_URL/{objectUUID}`.
- Sets all glow values to `0.0`.

### `restoreGlow()`

- GETs data from `API_BASE_URL/{objectUUID}`.
- On a `200` response, calls `restoreGlowFromData(data)`.
- On a `404` response, reports that no saved data exists.

### `restoreGlowFromData(string dataStr)`

- Parses the `"faceCounts;glowValues"` string.
- Applies each stored glow float back to the correct face of the correct
  child prim.

---

## Data Flow

```
ScheduledVisibility          GlowController.lsl         Glow Persistence API
       │                            │                           │
  schedule fires                    │                           │
  (hide time)                       │                           │
       │──── link_message("hide") ──►│                           │
       │                            │─── read all prim glow ───►│
       │                            │─── POST /api/glow/{uuid} ─►│
       │                            │◄── 200 OK ────────────────│
       │                            │─── set all glow = 0.0 ───►│
       │                            │                           │
  schedule fires                    │                           │
  (show time)                       │                           │
       │──── link_message("show") ──►│                           │
       │                            │─── GET /api/glow/{uuid} ──►│
       │                            │◄── 200 {"data":"..."} ────│
       │                            │─── restore glow values ──►│
```

---

## Touch Command (Status Check)

Touch the object as the owner to print a status summary in local chat:

```
GlowController v2.0 Status Check
  Object UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  API URL: http://YOUR_SERVER_IP:5005/api/glow
  Linked prims: N (excluding root)
```

---

## Chat Commands

The script also listens on channel 0 for owner chat commands:

| Command | Action |
|---------|--------|
| `save glow` | Immediately save and disable glow |
| `restore glow` | Immediately restore glow from API |
| `glow status` | Print current configuration |

---

## Testing and Debugging

1. **Touch the object** to confirm the script is running and see the UUID.
2. Say `save glow` in local chat near the object to manually trigger a save.
   Check the API: `curl http://YOUR_SERVER_IP:5005/api/glow/<uuid>`
3. Say `restore glow` to verify values are restored correctly.
4. Check server logs if HTTP requests fail:
   `sudo journalctl -u glowpersistence-api -f`

### Common Issues

| Issue | Fix |
|-------|-----|
| "API error 0" | Second Life cannot reach the server — check firewall / IP |
| "API error 404" on restore | No data was saved yet — run `save glow` first |
| Glow not saved on all prims | Ensure the object is a linkset (multiple prims linked) |
| Script not receiving link messages | Confirm `actionScript=GlowController` matches the script name exactly |
