# OBTrack iOS

**OBTrack** is a hybrid iPhone + UWB camera-tracking system for virtual
production. The iPhone reads ARKit 6DOF pose, applies on-stage calibration,
and streams it over UDP to a PC gateway. The gateway converts to FreeD and
feeds Unreal Engine (Live Link FreeD) or Assimilate LiveFX. A live dashboard
shows what's happening end-to-end.

---

## Requirements

| Item            | Minimum version                                     |
|-----------------|-----------------------------------------------------|
| Mac with Xcode  | Xcode 15+                                           |
| iPhone          | iPhone 16 Pro Max (or any ARKit-capable device)     |
| iOS             | 18.0+                                               |
| PC receiver     | Python 3.9+, or Ubuntu 22.04+ (one-shot installer)  |

> ARKit needs a physical device — the iOS Simulator does not work.

---

## Repository layout

```
OBTrack/
├── OBTrack/                            # iOS app source
│   ├── OBTrackApp.swift                # @main entry point
│   ├── ContentView.swift               # Main SwiftUI screen
│   ├── ARTrackingManager.swift         # ARKit session + per-frame pipeline
│   ├── UDPClient.swift                 # Network.framework UDP sender
│   ├── TrackingPacket.swift            # JSON packet schema
│   ├── Calibration.swift               # Calibration math + profile storage
│   ├── CalibrationView.swift           # 5-step on-set wizard
│   ├── BrandMark.swift                 # OBTrack logo + brand palette
│   ├── ARCameraView.swift              # ARKit preview + depth heat-map
│   └── Assets.xcassets / Info.plist
├── OBTrack.xcodeproj/                  # Xcode project
├── gateway_test/                       # PC gateway (Python)
│   ├── freed_bridge.py                 # JSON → FreeD bridge
│   ├── dashboard.py                    # Live web dashboard (Dash/Plotly)
│   ├── udp_receiver.py                 # Simple JSON sniffer for testing
│   ├── setup_ubuntu.sh                 # One-shot Ubuntu installer
│   ├── requirements.txt
│   ├── UNREAL_SETUP.md                 # Live Link FreeD configuration
│   └── LIVEFX_SETUP.md                 # Assimilate LiveFX configuration
└── docs/
    └── ESP32_UWB_INTEGRATION_PLAN.md   # Phase-3 roadmap (UWB + encoders)
```

---

## Quick start

### 1. Build and install the iOS app

1. Open `OBTrack.xcodeproj` in Xcode.
2. Select the **OBTrack** target → **Signing & Capabilities** → set your **Team**.
3. Change the **Bundle Identifier** if needed (default `com.obtrack.ios`).
4. Plug in the iPhone, select it as the run destination, press **⌘R**.
5. On the phone: **Settings → General → VPN & Device Management** → trust the
   developer certificate.
6. Launch the app, accept the camera permission, accept local network access.

### 2. Run the gateway

**Ubuntu (recommended — auto-installs as systemd services):**

```bash
cd OBTrack/gateway_test
sudo FREED_HOST=<unreal-pc-ip> FREED_PRESET=unreal bash setup_ubuntu.sh
```

The bridge and dashboard come up immediately and auto-start on every boot.
Dashboard at `http://<server-ip>:8050`.

**Mac / Windows / ad-hoc:**

```bash
cd gateway_test
pip3 install -r requirements.txt

# terminal 1 — bridge: JSON → FreeD (also mirrors JSON to :5006 for the dashboard)
python3 freed_bridge.py --preset unreal --out-host 127.0.0.1 --forward-port 5006

# terminal 2 — dashboard
python3 dashboard.py --udp-port 5006 --host 0.0.0.0
```

### 3. Point the iPhone at the gateway

In the OBTrack app, type the gateway's IP, leave port `5005`, pick `60 Hz`,
turn on **Lite (shooting) mode**, hit **Start**.

---

## Calibration — on stage

The iPhone is a sensor; Unreal needs to track the **lens centre**, not the
phone. The Calibration wizard handles that.

Tap the **scope** icon in the top bar (next to the gear). 5 cards:

| # | Step                          | What you do                                                          |
|---|-------------------------------|----------------------------------------------------------------------|
| 1 | **Set Origin**                | Place phone at stage zero, tap Capture. Becomes (0,0,0) in Unreal.   |
| 2 | **Set Forward Direction**     | Capture start → walk 2 m forward → Capture end. Walked dir = +X.     |
| 3 | **Set Camera Height**         | Capture floor + lens height, or type the lens height in metres.      |
| 4 | **Phone-to-Lens Offset**      | mm offsets from phone IMU to lens entrance pupil. Presets available. |
| 5 | **Save / Load Profile**       | Name the rig (e.g. *ALEXA + 50mm top-mount*) and save.               |

Profiles live in the app's `Documents/profiles/` and can be shared between
phones via the iOS share sheet. The active profile name is broadcast in
every UDP packet so the gateway and dashboard can show which calibration
is in use.

**Verify on stage:** walk a known 1 m square. Unreal's CineCameraActor
should move 1 m in matching directions. If a sign is wrong, flip the
corresponding constant at the top of `freed_bridge.py` (`POS_*_SIGN`,
`YAW_SIGN`, `PITCH_SIGN`, `ROLL_SIGN`) and restart the bridge.

### Gateway-side offset overrides

For last-second tweaks without re-running the wizard, the bridge accepts:

```bash
python3 freed_bridge.py --phone-offset-x 0.0 --phone-offset-y -0.15 --phone-offset-z 0.12
```

Units are **metres in FreeD axes** (X = right, Y = forward, Z = up). These
are additive on top of whatever calibration the iPhone is already applying.

---

## UDP packet format

One JSON object per UDP datagram, UTF-8 encoded:

```json
{
  "device": "iphone16promax",
  "timestamp": 1716124921.456,
  "frame": 1234,
  "position": { "x": 0.12, "y": 1.45, "z": -0.83 },
  "rotation": { "qx": 0.0, "qy": 0.2, "qz": 0.0, "qw": 0.98 },
  "trackingState": "normal",
  "profile": "ALEXA + 50mm top-mount"
}
```

| Field           | Meaning                                                            |
|-----------------|--------------------------------------------------------------------|
| `device`        | Always `"iphone16promax"`                                          |
| `timestamp`     | ARKit capture time (monotonic, seconds)                            |
| `frame`         | Monotonically increasing counter                                   |
| `position`      | **Lens-centre** position in metres, stage frame (or raw ARKit if no profile is active) |
| `rotation`      | Lens orientation as a unit quaternion                              |
| `trackingState` | `"normal"`, `"limited (…)"`, or `"notAvailable"`                   |
| `profile`       | Name of the active calibration profile, or `null` for raw pose     |

**Stage / ARKit axes:** +X right, +Y up, −Z forward. The FreeD bridge
re-maps these to the broadcast/Unreal conventions; you should not need to
think about it on stage.

---

## Phase roadmap

| Phase | Scope                                                              | Status   |
|-------|--------------------------------------------------------------------|----------|
|   1   | iPhone ARKit → JSON over UDP                                       | **Done** |
|   2a  | FreeD bridge + Unreal Live Link / LiveFX                           | **Done** |
|   2b  | On-iPhone calibration wizard + profile persistence                 | **Done** |
|   2c  | Dashboard shows active profile + UWB-ready status                  | **Done** |
|   3   | ESP32 + UWB anchor fusion (absolute correction)                    | planned  |
|   4   | ESP32 zoom / focus encoders → FreeD lens fields                    | planned  |

Phase 3 design — anchor placement, packet schema, fusion math, milestones —
is in [`docs/ESP32_UWB_INTEGRATION_PLAN.md`](docs/ESP32_UWB_INTEGRATION_PLAN.md).

---

## Troubleshooting

| Problem                                | Fix                                                                       |
|----------------------------------------|---------------------------------------------------------------------------|
| No packets at gateway                  | Same Wi-Fi? Firewall? Try `python3 udp_receiver.py` to sniff.             |
| Unreal Live Link source stays grey     | Check `freed_bridge.py` `--out-host` matches the Unreal machine IP.       |
| Camera up/down inverted in Unreal      | Set `POS_Z_SIGN = -1` at the top of `freed_bridge.py`, restart bridge.    |
| "limited (initializing)" never clears  | Move the phone slowly through a well-lit, textured area.                  |
| Profile field always `null`            | iPhone has no active profile loaded — open Calibrate → Profiles → pick.   |
| Build fails with signing error         | Set your Team in Xcode → Signing & Capabilities.                          |
