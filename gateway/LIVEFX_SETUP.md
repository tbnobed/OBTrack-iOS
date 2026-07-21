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

1. Open **Live FX Settings → Live Links Manager** (older versions:
   **Tracking** / **Camera Tracking** panel).
2. Select **FreeD Tracker** and switch it **On** (or **Add Source →
   FreeD**).
3. Configure:
   - **Listen IP**: `0.0.0.0` (any interface) or the PC's LAN IP
   - **Listen Port**: `6301` (must match `--out-port` in step 1)
   - **Tracker / Camera ID**: `1` (must match `--camera-id`, default 1)
   - **Encoder**: `Generic` — we send standard FreeD D1 packets
4. Save / Apply. The source should immediately show an incoming packet
   rate of ~30 Hz with a green status indicator.

## 3. Bind the FreeD source to your CG camera

1. In LiveFX's scene / shot setup, select the camera you want to drive.
2. Set its **Tracking Source** to the FreeD source you just added.
3. Enable **Use Position** and **Use Rotation**. Leave **Use Lens** /
   **Use Focal Length** off unless you have set up lens mapping (see
   section 5 below).

Move the iPhone — the CG camera should follow in real time.

## 4. If positions are off by exactly 10×

FreeD implementations split into two camps on position units:

| Convention | Units | Used by |
|---|---|---|
| BBC / Mo-Sys (original spec) | 64 per mm | Unreal Live Link FreeD, most trackers — **our default** |
| Vizrt | 640 per mm | Vizrt Tracking Hub, some PTZ cameras |

If moving the iPhone 1 m moves the CG camera 10 m (or 10 cm), the two
sides disagree. Fix on the bridge side:

```bash
python3 freed_bridge.py --preset livefx --pos-scale 640
```

The startup banner prints which scale is active. Angles are never
affected — every implementation agrees on degrees × 32768.

## 5. Lens data & LiveFX camera calibration

**What FreeD can carry:** 8 axes — pan, tilt, roll, X, Y, Z, plus two
*raw* lens-encoder counters (zoom, focus). FreeD has **no** fields for
focal length, film back, distortion or nodal offset — those are always
configured inside LiveFX itself.

**What LiveFX needs from you (inside LiveFX, one-time):**

- **Film back / sensor size** of the virtual camera — set it to match
  the cinema camera you are compositing for.
- **Focal length** — set manually per lens, or derived via LiveFX's
  built-in **Virtual Camera Calibration** (Live FX Studio), which also
  solves **lens distortion** and **nodal-point offset** from a chart.
  See Assimilate's tutorial: assimilateinc.com/camera-calibration-lfx
- **Nodal offset** — the FreeD position we send is the *lens entrance
  pupil* if you filled in the phone→lens offset in the OBTrack
  calibration wizard; otherwise it is the phone body. Small residual
  offsets can be zeroed with LiveFX's tracker offset fields.

**What the bridge can send (optional):** raw zoom/focus values for
LiveFX's lens mapping table. With a fixed prime lens, send constants:

```bash
python3 freed_bridge.py --preset livefx --zoom 2048 --focus 2048
```

If a future lens encoder feeds the gateway, JSON packets may include
`"zoom"` and `"focus"` fields — they override the static flags
automatically, no restart needed.

## 6. Calibrating axes & rotation

If position or rotation looks mirrored / rotated 90°, that is expected:
ARKit, Unreal and LiveFX all use different conventions. Fix it in this
order:

- **On the iPhone (recommended)** — tap **Live Trim** in the OBTrack app
  (below Start/Stop). It has Invert Pan / Tilt / Roll, Mirror X / Y / Z,
  and per‑axis position nudges in cm. Changes ride inside every packet
  and take effect on the next frame — no bridge restart, no server
  access. Settings are saved on the phone and survive app restarts.
- **Inside LiveFX** — most FreeD source panels also expose per‑axis
  invert toggles (Invert Pan / Tilt / Roll, Mirror X / Y / Z).
- **In the bridge** (last resort, normally never needed) — the sign
  constants near the top of `freed_bridge.py` (`YAW_SIGN`, `PITCH_SIGN`,
  `ROLL_SIGN`). Do NOT edit the matrix maths underneath.

A simple calibration drill (all from the phone):

1. Place the iPhone flat on a table, screen up, top edge pointing away
   from you. Press Start.
2. Note the CG camera's resting orientation in LiveFX.
3. Slowly **yaw** the iPhone left — the CG camera should yaw the same
   direction. If not, open **Live Trim** and turn on **Invert pan**.
4. Repeat for **pitch** (nose up/down → Invert tilt) and **roll**
   (lean left/right → Invert roll).
5. Walk right / forward / crouch — if the CG camera moves the wrong way
   on an axis, turn on the matching **Mirror X / Y / Z** toggle.

## 7. Running the dashboard alongside LiveFX

Only one program can bind UDP 5005, so let the bridge listen and have it
mirror the raw JSON to a second port for the dashboard:

```bash
# terminal 1 — bridge + mirror
python3 freed_bridge.py --preset livefx --forward-port 5006

# terminal 2 — dashboard listens on the mirrored port
python3 dashboard.py --udp-port 5006
```

## 8. Network checklist

- iPhone and PC on the same Wi‑Fi network (or USB-tethered).
- iPhone app: **Host IP** = the PC's IP, **Port** = `5005`.
- macOS firewall: **System Settings → Network → Firewall** — allow
  incoming connections for `python3`.
- Windows firewall: allow inbound UDP on ports `5005` and `6301` for
  `python.exe` and the LiveFX executable.
- If LiveFX shows "no packets" but the bridge prints normal rates, the
  firewall on the LiveFX machine is the most likely culprit.
