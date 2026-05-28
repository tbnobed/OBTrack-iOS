# OBTrack → Assimilate LiveFX setup

LiveFX accepts the same FreeD UDP stream we already produce for Unreal —
you just point the bridge at LiveFX's listening port instead of Unreal's.

```
iPhone (OBTrack app)
   │  JSON / UDP   port 5005
   ▼
PC running freed_bridge.py --preset livefx
   │  FreeD / UDP   port 6301 (configurable)
   ▼
Assimilate LiveFX
   │
   ▼
Tracked CG camera in the scene
```

## 1. Start the bridge on the PC

Default (LiveFX running on the same machine):

```bash
cd OBTrack/gateway
python3 freed_bridge.py --preset livefx
```

LiveFX running on a different machine:

```bash
python3 freed_bridge.py --preset livefx --out-host 192.168.1.50
```

Non-default port (whatever you set inside LiveFX):

```bash
python3 freed_bridge.py --preset livefx --out-host 192.168.1.50 --out-port 40001
```

You should see, once per second:

```
   30 pkt/s   pos=(+0.123,-0.045,+1.612) m   rot=( +12.4, -3.1, +0.7)°
```

## 2. Add a FreeD tracking source in LiveFX

The exact menu wording can vary slightly between LiveFX versions, but the
shape is the same in all recent releases:

1. Open the **Tracking** (sometimes **Camera Tracking** / **External
   Tracking**) panel.
2. **Add Source → FreeD** (or "FreeD over UDP").
3. Configure:
   - **Listen IP**: `0.0.0.0` (any interface) or the PC's LAN IP
   - **Listen Port**: `6301` (must match `--out-port` in step 1)
   - **Camera ID**: `1` (must match `--camera-id`, default 1)
4. Save / Apply. The source should immediately show an incoming packet
   rate of ~30 Hz with a green status indicator.

## 3. Bind the FreeD source to your CG camera

1. In LiveFX's scene / shot setup, select the camera you want to drive.
2. Set its **Tracking Source** to the FreeD source you just added.
3. Enable **Use Position** and **Use Rotation**. Leave **Use Lens** /
   **Use Focal Length** off — we are not sending lens metadata yet.

Move the iPhone — the CG camera should follow in real time.

## 4. Calibrating axes & rotation

If position or rotation looks mirrored / rotated 90°, that is expected:
ARKit, Unreal and LiveFX all use different conventions. Two ways to fix:

- **Inside LiveFX** — most FreeD source panels expose per‑axis invert
  toggles (Invert Pan / Tilt / Roll, Mirror X / Y / Z). Try those first;
  they survive across bridge restarts.
- **In the bridge** — open `freed_bridge.py` and change the calibration
  knobs near the top:

  ```python
  EULER_ORDER = "ZYX"
  YAW_SIGN    = 1
  PITCH_SIGN  = 1
  ROLL_SIGN   = 1
  ```

  Flip individual sign constants between `+1` and `-1` until movement in
  LiveFX matches the iPhone. Do NOT edit the matrix maths underneath.

A simple calibration drill:

1. Place the iPhone flat on a table, screen up, top edge pointing away
   from you. Press Start.
2. Note the CG camera's resting orientation in LiveFX.
3. Slowly **yaw** the iPhone left — the CG camera should yaw the same
   direction. If not, flip `YAW_SIGN`.
4. Repeat for **pitch** (nose up/down) and **roll** (lean left/right).

## 5. Running the dashboard alongside LiveFX

Only one program can bind UDP 5005, so let the bridge listen and have it
mirror the raw JSON to a second port for the dashboard:

```bash
# terminal 1 — bridge + mirror
python3 freed_bridge.py --preset livefx --forward-port 5006

# terminal 2 — dashboard listens on the mirrored port
python3 dashboard.py --udp-port 5006
```

## 6. Network checklist

- iPhone and PC on the same Wi‑Fi network (or USB-tethered).
- iPhone app: **Host IP** = the PC's IP, **Port** = `5005`.
- macOS firewall: **System Settings → Network → Firewall** — allow
  incoming connections for `python3`.
- Windows firewall: allow inbound UDP on ports `5005` and `6301` for
  `python.exe` and the LiveFX executable.
- If LiveFX shows "no packets" but the bridge prints normal rates, the
  firewall on the LiveFX machine is the most likely culprit.
