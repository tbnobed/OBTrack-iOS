# ESP32 / UWB Integration Plan

Phase-3 roadmap for adding ESP32 + ultra-wideband (UWB) ranging to OBTrack.
**Hardware is not yet on hand** — this document fixes the protocol, anchor
plan, fusion strategy, and milestone order so firmware can be built against
a known target. The gateway's calibration path (Phase 2) already works with
iPhone-only ARKit and is **not** blocked by anything in this document.

---

## 1. System architecture (target)

```
┌───────────────┐                       ┌──────────────────────────┐
│ iPhone ARKit  │── 6DOF JSON (UDP) ───▶│                          │
└───────────────┘     :5005             │                          │
                                        │      PC / Ubuntu         │── FreeD ──▶ Unreal /
┌───────────────┐                       │        Gateway           │   :6301     LiveFX
│ ESP32 UWB tag │── tag JSON (UDP) ────▶│                          │
│ on camera rig │     :5010             │  • receives both streams │
└───────────────┘                       │  • fuses ARKit (smooth)  │
                                        │    with UWB (absolute)   │
┌───────────────┐                       │  • outputs FreeD         │
│ ESP32 anchors │── ranging packets ───▶│                          │
│ (4–6, fixed)  │  (to tag, not gateway)│                          │
└───────────────┘                       └──────────────────────────┘
```

The **camera-tag ESP32** does the multilateration locally from anchor
ranges and sends an absolute (x, y, z) position to the gateway. Anchors
talk only to the tag over UWB; they do not need to know about the gateway
(except optionally a Wi-Fi heartbeat for status).

---

## 2. Hardware

| Role        | Recommended part                          | Notes                                       |
|-------------|-------------------------------------------|---------------------------------------------|
| Camera tag  | ESP32-S3 + Qorvo DWM3000 (or DW1000)      | One per camera rig. Mounted near the lens.  |
| Anchors     | ESP32-S3 + DWM3000, ≥ 4 units             | Fixed, surveyed positions around the stage. |
| Power (tag) | USB-PD power bank (5 V)                   | Same source as the iPhone.                  |
| Power (anc) | PoE injector or 5 V wall PSU              | Each anchor draws ~250 mA.                  |
| Optional    | ICM-42688 IMU on tag                      | Sub-30 ms fast motion fill, future phase.   |
| Optional    | AS5048 rotary encoders for zoom / focus   | Per-lens; documented separately below.      |

DWM3000 chosen over DW1000 because: (1) lower power, (2) better narrow-pulse
support → cleaner ranges in metal-rich studios, (3) Apple U1 / future
iPhone-native ranging interop is on the DWM3000 family.

---

## 3. Anchor placement on stage

**Minimum: 4 anchors. Better: 6.** UWB position solves degrade fast below 4
and quietly produce ambiguous Z if all anchors are coplanar.

Rules of thumb:

* **One per corner** of the tracking volume, mounted high — 8–12 ft (2.5–3.6 m).
* **Vary the heights.** Two anchors high, two low is dramatically better
  for vertical accuracy than four at the same height.
* **Line of sight.** UWB tolerates partial obstruction but degrades through
  bodies and metal. Aim for direct LOS from the camera operating area.
* **Avoid mounting directly behind LED walls, lighting trusses with diagonal
  bracing, or large flats** — strong multipath kills repeatability.
* **Measure each anchor position carefully** (laser distance meter, ±1 cm).
  Anchor survey error sets the floor for all downstream accuracy.

Typical small-set layout:

```
       ▲ stage forward (+Y after iPhone calibration)
       │
   A4 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ A2     (high, ~3 m)
       │      ◎  camera     │
       │      tracking      │
       │      volume        │
   A3 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ A1     (low,  ~1 m)
       │
       └──────────────▶  +X (stage right)
```

---

## 4. Wire protocol

All packets are UTF-8 JSON, one JSON object per UDP datagram. Same style
as the iPhone packets, so the gateway can sniff with `udp_receiver.py`.

### 4.1 Tag → Gateway  (UDP :5010)

```json
{
  "type": "uwb_tag",
  "device_id": "camA_tag",
  "timestamp": 123456.789,
  "position": { "x": 1.25, "y": 0.82, "z": 1.55 },
  "quality": {
    "anchors_used": 4,
    "rssi": -71,
    "confidence": 0.86
  }
}
```

* `position` is in **metres**, in the stage frame after the tag has been
  surveyed against the anchors. No extra calibration is applied by the tag.
* `confidence` ∈ [0, 1]. The gateway uses this to weight the blend (a low
  value reduces UWB influence even if `blend_alpha` is set high).
* Send rate: 20–50 Hz. Above 50 Hz UWB ranging starts to collide.

### 4.2 Anchor → Gateway  (UDP :5011, optional status only)

The fix-quality data lives in the tag packet; anchors don't need to talk
to the gateway. If you do want anchor heartbeats:

```json
{
  "type": "uwb_anchor",
  "anchor_id": "anchor_01",
  "position_m": { "x": 0.0, "y": 0.0, "z": 2.5 },
  "wifi_rssi": -54,
  "uptime_s": 12345
}
```

### 4.3 Lens encoder → Gateway  (UDP :5012, future phase)

Wired separately so the encoder ESP32 can be a stand-alone unit on the
camera matte box without depending on the UWB tag.

```json
{
  "type": "lens_encoder",
  "device_id": "camA_lens",
  "timestamp": 123456.789,
  "zoom_raw":  12043,
  "focus_raw":  8401
}
```

`zoom_raw` / `focus_raw` are 0–65535 encoder counts. A per-lens calibration
table on the gateway maps these to focal-length (mm) and focus-distance (m)
before they go out in the FreeD `zoom` / `focus` fields.

---

## 5. Fusion plan

> ARKit is **smooth but drifts** over minutes — its world origin slowly
> wanders as new features replace old ones. UWB is **absolute but noisy** —
> jitter on the order of ±2–5 cm even with a clean solve.
>
> The right answer is to take rotation and fast motion from ARKit and use
> UWB only as a slow correction on absolute position.

### 5.1 Algorithm (v1, scalar EMA per axis)

```python
# fused_position = α · arkit + (1 - α) · uwb     # NO — wrong direction
# We want UWB to *correct* ARKit, not replace it. So compute the bias.

bias[t] = α · bias[t-1]  +  (1 - α) · (uwb_pos[t] - arkit_pos[t])
fused_pos[t] = arkit_pos[t] + bias[t]
```

`α = 1 - blend_alpha`, where `blend_alpha` is the per-frame influence of
UWB. Typical starting values:

* `blend_alpha = 0.05` — heavy smoothing, slow drift correction (~3 s)
* `blend_alpha = 0.15` — balanced (~1 s)
* `blend_alpha = 0.40` — fast correction, more visible UWB jitter

Multiply `blend_alpha` by `confidence` from the tag packet so low-quality
UWB fixes get less influence automatically.

Rotation is taken from ARKit unmodified. UWB does not produce rotation.

### 5.2 Where this lives

A future `gateway/fusion.py` module, called from the main loop in
`freed_bridge.py` between `convert_pose()` and `build_freed_packet()`.
**Phase 2 ships without it** — fusion only turns on once a real tag is
sending data.

---

## 6. Calibration interaction

* The iPhone's calibration wizard sets the **stage origin and forward axis**
  for ARKit. After UWB comes online, the UWB tag's surveyed position uses
  the same stage frame (i.e. the operator measures anchor positions in
  the same coordinate system that the iPhone's "set origin / set forward"
  defines). One world, one origin.
* The phone-to-lens offset captured in the iPhone wizard applies to the
  iPhone's ARKit stream. The UWB tag should be mounted **at the same point
  the iPhone profile reports as the lens centre**, so both streams refer
  to the same physical point. If they can't, the tag firmware applies its
  own fixed offset before sending.

---

## 7. Development milestones

| #  | Goal                                                          | Status   |
|----|---------------------------------------------------------------|----------|
| M1 | Calibration works with iPhone-only ARKit                      | **Done** |
| M2 | Dashboard shows active calibration profile + raw vs calibrated| **Done** |
| M3 | ESP32 UWB listener `uwb_receiver.py` receives test JSON       | planned  |
| M4 | Manual fake-tag packets blend through `blend_alpha`           | planned  |
| M5 | Real ESP32 UWB tag sends position from stage anchors          | needs HW |
| M6 | Lens encoder ESP32 sends zoom/focus, populates FreeD fields   | needs HW |

Each milestone has its own deliverable file — M3 ships `uwb_receiver.py`
and a `tools/send_test_uwb_packet.py` fake-tag generator; M6 ships
`encoder_bridge.py` and a per-lens calibration JSON format.

---

## 8. What is **not** in this phase

* No ESP32 firmware. Pick a stack (Arduino-IDE + Qorvo DWM3000 lib, or
  ESP-IDF + makerfabs/sparkfun examples) before M3.
* No anchor auto-survey. The first deployments will use a tape-measured
  anchor map; auto-survey is its own project.
* No Kalman filter. The bias-EMA above is intentionally simple; if it
  proves inadequate on stage we'll move to a 6-state position-velocity KF.
