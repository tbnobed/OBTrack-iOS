# OBTrack → Unreal Engine setup

> Using Assimilate LiveFX instead? See **LIVEFX_SETUP.md** — same bridge,
> different target.

End‑to‑end signal flow:

```
iPhone (OBTrack app)
   │  JSON / UDP  port 5005
   ▼
PC running freed_bridge.py
   │  FreeD / UDP  port 6301
   ▼
Unreal Engine  (Live Link FreeD source)
   │
   ▼
CineCameraActor in the level
```

## 1. Start the bridge on the PC

```bash
cd OBTrack/gateway
python3 freed_bridge.py --preset unreal
```

The terminal should print `Listening JSON : 0.0.0.0:5005` and, once the
iPhone is sending, a per‑second status line with pkt/s, position and
rotation.

### Running the dashboard at the same time

Only one program can listen on UDP 5005, so let the bridge listen and have
it mirror the JSON to a second port for the dashboard:

```bash
# terminal 1
python3 freed_bridge.py --forward-port 5006
# terminal 2
python3 dashboard.py --udp-port 5006
```

### Sending to a different machine

```bash
python3 freed_bridge.py --preset unreal --out-host 192.168.1.50 --out-port 6301
```

## 2. Enable the Live Link FreeD plugin in Unreal

1. **Edit → Plugins**
2. Search for **Live Link** — enable **Live Link** and **Live Link FreeD
   Tracking** (both ship with Unreal 5).
3. Restart the editor.

## 3. Add a FreeD source

1. **Window → Virtual Production → Live Link**
2. **+ Source → FreeD Tracking**
3. Settings:
   - **IP Address**: `0.0.0.0` (listen on all interfaces)
   - **UDP Port**: `6301`
   - **Default Subject Name**: `Camera1`
   - **Send Extra Meta Data**: optional
4. Click **Add**.

You should immediately see `Camera1` appear in the subject list with a
green dot. If the dot is grey/red, the PC firewall is most likely
blocking inbound UDP 6301.

## 4. Drive a CineCamera with it

1. In the level, place a **Cine Camera Actor**.
2. Select it → **Add Component → Live Link Controller**.
3. In the Live Link Controller details:
   - **Subject Representation**: `Camera1` (role: *Camera*)
   - **Use Location / Rotation**: enabled
   - **Use Camera Focal Length / Aperture**: disabled (we don't send
     those yet)
4. Pilot the camera (or set it as the active view) and move the iPhone —
   the camera in the viewport will follow.

## 5. If the axes feel wrong

The bridge uses this default mapping (ARKit → Unreal):

| Unreal axis | Source |
|-------------|--------|
| +X forward  | ARKit −Z |
| +Y right    | ARKit +X |
| +Z up       | ARKit +Y |

Two easy ways to adjust without editing Python:

- On the **Live Link Controller** component, toggle the individual
  **Use Rotation X / Y / Z** or **Use Location X / Y / Z** axes.
- Parent the CineCameraActor to an empty actor and rotate the parent
  90° around Z (or whichever axis is off).

If a deeper change is needed, edit `remap_position()` and the Euler
ordering inside `quat_to_euler_deg()` at the top of `freed_bridge.py`.

## 6. Network checklist

- iPhone and PC must be on the same Wi‑Fi network (or USB tethered).
- In the iPhone app, set **Host IP** to the PC's IP and **Port** to 5005.
- macOS firewall: **System Settings → Network → Firewall** — allow
  incoming connections for `python3` (or temporarily turn the firewall
  off while testing).
- Windows firewall: allow inbound UDP on ports 5005 and 6301 for
  `python.exe` and `UnrealEditor.exe`.
