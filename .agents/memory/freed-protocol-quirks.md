---
name: FreeD protocol quirks
description: FreeD D1 packet unit conventions and consumer-side ambiguities affecting the OBTrack bridge
---

# FreeD D1 unit conventions (verified against Vizrt spec + implementations, Jul 2026)

- Angles: universal agreement — degrees × 32768 (15 fractional bits), signed 24-bit BE. Order: pan (bytes 2–4), tilt (5–7), roll (8–10).
- **Position units are NOT universal.** Two camps:
  - 64 units/mm (1/64 mm) — original BBC/Mo-Sys spec, Unreal Live Link FreeD default. ±131 m range.
  - 640 units/mm (1/640 mm) — Vizrt Tracking Hub and several PTZ vendors. ±13.1 m range.
  - Symptom of mismatch: positions off by exactly 10×. Bridge exposes `--pos-scale {64,640}` (default 64).
- Zoom/focus (bytes 20–25) are unsigned 24-bit *raw encoder counts* (typically 0–4095); consumers map them via their own lens files. Sending 0 disables lens mapping in LiveFX.
- Checksum: 0x40 minus sum of first 28 bytes, mod 256; equivalently sum of all 29 bytes ≡ 0x40 (mod 256).
- LiveFX specifics: FreeD source configured in Live Links Manager (Encoder = "Generic"); film back / focal length / distortion / nodal offset are NEVER carried by FreeD — set inside LiveFX (Virtual Camera Calibration in Live FX Studio, tutorial: assimilateinc.com/camera-calibration-lfx).

**Why:** we hit the 64-vs-640 ambiguity when hardening the bridge for LiveFX; docs from different vendors flatly contradict each other.
**How to apply:** never hardcode a single FreeD position scale; keep it switchable and document the "off by 10×" symptom. When adding new FreeD consumers, verify their expected scale empirically.
