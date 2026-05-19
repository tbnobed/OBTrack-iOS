# OBTrack iOS — Phase 1

**OBTrack** is an iOS app that reads ARKit 6DOF position and rotation data from an iPhone 16 Pro Max and streams it over UDP to a PC. This is Phase 1 — proving the iPhone can reliably send ARKit tracking data over the network. FreeD / Unreal Engine Live Link conversion will be added in a future phase.

---

## Requirements

| Item | Minimum version |
|------|----------------|
| Mac with Xcode | Xcode 15+ |
| iPhone | iPhone 16 Pro Max (or any ARKit-capable device) |
| iOS | 18.0+ |
| PC receiver | Python 3.7+ |

> **Important:** ARKit requires a physical iPhone. The iOS Simulator does not support ARKit.

---

## Project structure

```
OBTrack/
├── OBTrack/
│   ├── OBTrackApp.swift          # App entry point (@main)
│   ├── ContentView.swift         # Main SwiftUI screen
│   ├── ARTrackingManager.swift   # ARKit session + tracking logic
│   ├── UDPClient.swift           # Network.framework UDP sender
│   ├── TrackingPacket.swift      # Codable data model + JSON serialization
│   └── Info.plist                # Camera & local network permissions
├── OBTrack.xcodeproj/            # Xcode project
└── gateway_test/
    └── udp_receiver.py           # Python test receiver for the PC
```

---

## How to open and build in Xcode

1. Clone or download this repository to your Mac.
2. Open `OBTrack.xcodeproj` in Xcode (double-click it in Finder or `open OBTrack.xcodeproj` in Terminal).
3. In the **Project Navigator**, select the **OBTrack** project at the top, then select the **OBTrack** target.
4. Under **Signing & Capabilities**, set your **Team** (your Apple Developer account). Xcode will manage provisioning automatically.
5. Change the **Bundle Identifier** if needed (default: `com.obtrack.ios`).
6. Select your iPhone as the run destination in the toolbar (it must be plugged in or on the same Wi-Fi for wireless debugging).
7. Press **Run (⌘R)**. Accept the camera permission prompt when the app launches on the phone.

---

## How to run on your iPhone

1. Plug in your iPhone (or use wireless pairing in Xcode → Window → Devices and Simulators).
2. On your iPhone, go to **Settings → Privacy → Developer Mode** and enable Developer Mode (required on iOS 16+).
3. On first launch after installing from Xcode, go to **Settings → General → VPN & Device Management** and trust your developer certificate.
4. Open the app. The camera permission dialog will appear — tap **Allow**.

---

## How to start the Python UDP receiver on your PC

Make sure Python 3 is installed, then:

```bash
cd gateway_test
python3 udp_receiver.py
```

By default it listens on all interfaces on port **5005**. You can override these:

```bash
python3 udp_receiver.py --host 0.0.0.0 --port 5005
```

You will see output like:

```
OBTrack UDP Receiver listening on 0.0.0.0:5005
Waiting for packets from the iOS app … (Ctrl+C to stop)

14:22:01.123  [Frame      1] state=normal               pos=(+0.0000, +0.0000, +0.0000)  quat=(+0.0000, +0.0000, +0.0000, +1.0000)
14:22:01.156  [Frame      2] state=normal               pos=(+0.0012, +1.2201, -0.0034)  quat=(+0.0100, +0.2100, -0.0020, +0.9776)
```

Press **Ctrl+C** to stop.

---

## How to enter the PC IP address in the app

1. On your PC, find its local IP address:
   - **Windows:** `ipconfig` in Command Prompt → look for IPv4 Address
   - **macOS/Linux:** `ifconfig` or `ip addr`
2. Open OBTrack on your iPhone.
3. In the **Network** section, replace `192.168.1.100` with your PC's IP address.
4. Leave the port as `5005` (or change it if you started the receiver on a different port).
5. Make sure your iPhone and PC are on the **same Wi-Fi network**.

---

## UDP packet format

Each packet is a JSON object (UTF-8 encoded):

```json
{
  "device": "iphone16promax",
  "timestamp": 1716124921.456,
  "frame": 1234,
  "position": {
    "x": 0.12,
    "y": 1.45,
    "z": -0.83
  },
  "rotation": {
    "qx": 0.0,
    "qy": 0.2,
    "qz": 0.0,
    "qw": 0.98
  },
  "trackingState": "normal"
}
```

| Field | Description |
|-------|-------------|
| `device` | Always `"iphone16promax"` |
| `timestamp` | Unix timestamp (seconds since epoch) |
| `frame` | Monotonically increasing frame counter |
| `position` | World-space position in meters (ARKit coordinate system) |
| `rotation` | World-space rotation as a unit quaternion |
| `trackingState` | `"normal"`, `"limited"`, or `"notAvailable"` |

**ARKit coordinate system:** +X is right, +Y is up, −Z is forward (into the screen).

---

## Phase 1 scope and limitations

- This version **only sends raw ARKit data**. No FreeD or Unreal Engine conversion yet.
- There is **no error correction** — UDP packets may be dropped on congested networks. This is acceptable for Phase 1 proof-of-concept.
- The app must stay in the **foreground** while tracking. ARKit pauses when the app is backgrounded.
- The tracking quality indicator (`normal` / `limited`) tells you whether ARKit has good environmental lock. Point the phone at a textured surface with good lighting for best results.

---

## Roadmap

- **Phase 2:** Convert ARKit quaternion + position to FreeD protocol binary packets
- **Phase 3:** Unreal Engine Live Link plugin integration
- **Phase 4:** Multi-device support, calibration offsets

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No packets received | Check IP/port, confirm same Wi-Fi, check macOS firewall |
| "limited (initializing)" indefinitely | Move the phone slowly around a well-lit textured area |
| App crashes on start | Make sure camera permission was granted |
| Build fails with signing error | Set your Team in Xcode → Signing & Capabilities |
