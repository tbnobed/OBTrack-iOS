#!/usr/bin/env python3
"""
freed_bridge.py — OBTrack JSON → FreeD UDP bridge.

Listens for OBTrack JSON packets from the iPhone, converts each one to a
29-byte FreeD "D1" packet, and forwards it to any tool that accepts FreeD:

    • Unreal Engine          (Live Link FreeD plugin)
    • Assimilate LiveFX      (FreeD tracking source)
    • Any other FreeD-compatible consumer

Quick start:
    python3 freed_bridge.py                              # default → 127.0.0.1:6301
    python3 freed_bridge.py --preset unreal
    python3 freed_bridge.py --preset livefx --out-host 192.168.1.50
    python3 freed_bridge.py --out-host 10.0.0.5 --out-port 6301

Run the dashboard at the same time:
    # terminal 1
    python3 freed_bridge.py --forward-port 5006
    # terminal 2
    python3 dashboard.py --udp-port 5006

Defaults:
    listen port      : 5005   (matches the iPhone app)
    output host:port : 127.0.0.1:6301
    camera id        : 1

Backwards-compat: `--ue-host` / `--ue-port` are still accepted as aliases
for `--out-host` / `--out-port`.
"""

import argparse
import json
import math
import os
import socket
import sys
import threading
import time


# ===========================================================================
# Coordinate frames: ARKit → FreeD → Unreal / LiveFX
#
# ARKit world:   +X right,   +Y up,    -Z forward   (right-handed)
# Unreal world:  +X forward, +Y right, +Z up        (left-handed)
#
# FreeD itself is broadcast convention: position fields are X=east (right),
# Y=north (forward), Z=up; rotation fields are pan around Z, tilt around Y,
# roll around X. Unreal's Live Link FreeD plugin honours that for position
# but applies rotation in Unreal's own axes — so position and rotation
# legitimately use DIFFERENT basis matrices. They are kept side-by-side
# below so it is impossible to change one without seeing the other.
#
# P_BASIS — used for POSITION:
#     FreeD X (right)   ←  ARKit +X
#     FreeD Y (forward) ←  ARKit -Z
#     FreeD Z (up)      ←  ARKit +Y
#
# R_BASIS — used for ROTATION:
#     UE X (forward)    ←  ARKit -Z
#     UE Y (right)      ←  ARKit +X
#     UE Z (up)         ←  ARKit +Y
#   Yaw / pitch / roll are then extracted from R_ue = R_BASIS · R_arkit · R_BASISᵀ.
# ===========================================================================
P_BASIS = [
    [1.0, 0.0,  0.0],   # FreeD X (right)   ←  ARKit +X
    [0.0, 0.0, -1.0],   # FreeD Y (forward) ←  ARKit -Z
    [0.0, 1.0,  0.0],   # FreeD Z (up)      ←  ARKit +Y
]

R_BASIS = [
    [0.0, 0.0, -1.0],   # UE X (forward) ← ARKit -Z
    [1.0, 0.0,  0.0],   # UE Y (right)   ← ARKit +X
    [0.0, 1.0,  0.0],   # UE Z (up)      ← ARKit +Y
]

# ---------------------------------------------------------------------------
# EMPIRICAL CALIBRATION KNOBS — VERIFY IN UNREAL.
#
# The Euler extraction order/signs that Unreal's FreeD rotator interprets
# correctly have NOT been verified for this pipeline. Defaults below are a
# reasonable starting guess. On set, point the iPhone at a known orientation
# (e.g. flat on a table, camera facing +X) and flip these constants until the
# CineCameraActor in Unreal matches what the phone is doing. Do NOT modify
# the maths in quat_to_R / euler_from_R unless you really know why.
# ---------------------------------------------------------------------------
EULER_ORDER = "ZYX"   # extraction order applied to the UE-basis rotation matrix
YAW_SIGN    =  1      # pan         (verified: left/right correct in Unreal/LiveFX)
PITCH_SIGN  = -1      # tilt        (verified: was inverted, flipped)
ROLL_SIGN   =  1      # roll        (unverified — flip if camera leans wrong way)

# Per-axis position sign knobs, applied AFTER P_BASIS. Use these to fix
# axis inversions discovered on set without touching the matrices.
POS_X_SIGN  =  1      # FreeD X (right)
POS_Y_SIGN  =  1      # FreeD Y (forward)
POS_Z_SIGN  =  1      # FreeD Z (up)     — flip to -1 if camera height is inverted


# ---------------------------------------------------------------------------
# 3×3 matrix helpers (plain Python — no numpy dependency)
# ---------------------------------------------------------------------------
def mat3_mul(A, B):
    return [
        [sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)]
        for i in range(3)
    ]


def mat3_transpose(A):
    return [[A[j][i] for j in range(3)] for i in range(3)]


def mat3_vec(A, v):
    return tuple(sum(A[i][k] * v[k] for k in range(3)) for i in range(3))


def quat_to_R(qx, qy, qz, qw):
    """Standard right-handed rotation matrix from a unit quaternion."""
    xx, yy, zz = qx * qx, qy * qy, qz * qz
    xy, xz, yz = qx * qy, qx * qz, qy * qz
    wx, wy, wz = qw * qx, qw * qy, qw * qz
    return [
        [1 - 2 * (yy + zz),     2 * (xy - wz),     2 * (xz + wy)],
        [    2 * (xy + wz), 1 - 2 * (xx + zz),     2 * (yz - wx)],
        [    2 * (xz - wy),     2 * (yz + wx), 1 - 2 * (xx + yy)],
    ]


def euler_from_R(R, order=EULER_ORDER):
    """
    Extract (yaw, pitch, roll) in degrees from a 3×3 rotation matrix.

    Default order ZYX (yaw around Z, pitch around Y, roll around X) is the
    convention Unreal's FRotator uses. THIS HAS NOT BEEN EMPIRICALLY VERIFIED
    against Live Link FreeD — if a single axis behaves wrong, flip the
    corresponding *_SIGN constant at the top of this file rather than touching
    the formulas below.
    """
    if order == "ZYX":
        sy = -R[2][0]
        sy = max(-1.0, min(1.0, sy))
        pitch = math.asin(sy)
        if abs(R[2][0]) < 0.99999:
            yaw  = math.atan2(R[1][0], R[0][0])
            roll = math.atan2(R[2][1], R[2][2])
        else:
            # gimbal-lock fallback
            yaw  = math.atan2(-R[0][1], R[1][1])
            roll = 0.0
        return math.degrees(yaw), math.degrees(pitch), math.degrees(roll)
    raise ValueError(f"Unsupported EULER_ORDER: {order!r}")


# ---------------------------------------------------------------------------
# Bytewise helpers
# ---------------------------------------------------------------------------
def pack_int24_be(value):
    """Pack a signed integer into 3 big-endian bytes (two's complement)."""
    v = int(round(value))
    if v < 0:
        v = (1 << 24) + v
    v &= 0xFFFFFF
    return bytes([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


def pack_uint24_be(value):
    v = max(0, min(0xFFFFFF, int(round(value))))
    return bytes([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


# ---------------------------------------------------------------------------
# FreeD D1 packet (29 bytes)
# ---------------------------------------------------------------------------
# Angles: every implementation agrees — degrees × 32768 (15 fractional bits).
ANGLE_SCALE = 32768.0          # FreeD units per degree
#
# Position: the FreeD ecosystem split into two camps:
#   * 64  units/mm — original BBC / Mo-Sys spec (1/64 mm resolution,
#                    ±131 m range).  Unreal Live Link FreeD default.
#   * 640 units/mm — Vizrt Tracking Hub & several PTZ vendors
#                    (1/640 mm resolution, ±13.1 m range).
# If the consumer uses the other convention, positions are off by exactly
# 10×.  Select with --pos-scale; default is the BBC/Mo-Sys 64 units/mm.
POS_UNITS_PER_MM_DEFAULT = 64


def build_freed_packet(camera_id, pan_deg, tilt_deg, roll_deg,
                       x_m, y_m, z_m, zoom=0, focus=0,
                       pos_units_per_mm=POS_UNITS_PER_MM_DEFAULT):
    pos_scale_per_m = pos_units_per_mm * 1000.0   # units per metre
    pkt = bytearray()
    pkt.append(0xD1)
    pkt.append(camera_id & 0xFF)
    pkt += pack_int24_be(pan_deg  * ANGLE_SCALE)
    pkt += pack_int24_be(tilt_deg * ANGLE_SCALE)
    pkt += pack_int24_be(roll_deg * ANGLE_SCALE)
    pkt += pack_int24_be(x_m * pos_scale_per_m)
    pkt += pack_int24_be(y_m * pos_scale_per_m)
    pkt += pack_int24_be(z_m * pos_scale_per_m)
    pkt += pack_uint24_be(zoom)
    pkt += pack_uint24_be(focus)
    pkt += b"\x00\x00"
    checksum = (0x40 - sum(pkt)) & 0xFF
    pkt.append(checksum)
    assert len(pkt) == 29, len(pkt)
    return bytes(pkt)


# ---------------------------------------------------------------------------
# ARKit → FreeD pose conversion (separate position vs rotation basis)
# ---------------------------------------------------------------------------
R_BASIS_T = mat3_transpose(R_BASIS)


def convert_pose(arkit_pos, arkit_quat):
    """
    arkit_pos:  (x, y, z) in metres, ARKit world frame
    arkit_quat: (qx, qy, qz, qw)

    Returns:
        (fx, fy, fz, yaw_deg, pitch_deg, roll_deg)
        Position fields are FreeD axes (X=right, Y=forward, Z=up); rotation
        is in Unreal axes. All calibration signs applied.
    """
    # Position: P_BASIS, then per-axis calibration signs
    px, py, pz = mat3_vec(P_BASIS, arkit_pos)

    # Rotation: R_BASIS, extract Euler in R_ue frame
    R_ar = quat_to_R(*arkit_quat)
    R_ue = mat3_mul(mat3_mul(R_BASIS, R_ar), R_BASIS_T)
    yaw_raw, pitch_raw, roll_raw = euler_from_R(R_ue, EULER_ORDER)

    return (
        POS_X_SIGN * px,
        POS_Y_SIGN * py,
        POS_Z_SIGN * pz,
        YAW_SIGN   * yaw_raw,
        PITCH_SIGN * pitch_raw,
        ROLL_SIGN  * roll_raw,
    )


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
PRESETS = {
    # name      : (default host,   default port, label printed at startup)
    "unreal"    : ("127.0.0.1",   6301, "Unreal Engine (Live Link FreeD)"),
    "livefx"    : ("127.0.0.1",   6301, "Assimilate LiveFX (FreeD source)"),
    "generic"   : ("127.0.0.1",   6301, "Generic FreeD consumer"),
}


def main():
    p = argparse.ArgumentParser(
        description="OBTrack JSON → FreeD bridge (Unreal Engine, "
                    "Assimilate LiveFX, or any FreeD consumer)")
    p.add_argument("--listen-port", type=int,
                   default=int(os.environ.get("OBTRACK_PORT", 5005)),
                   help="UDP port to receive OBTrack JSON (default 5005)")
    p.add_argument("--preset", choices=sorted(PRESETS.keys()),
                   default=os.environ.get("PRESET", "generic"),
                   help="Target tool preset — sets sensible defaults and "
                        "labels the output. Override host/port with "
                        "--out-host/--out-port. (default: generic)")
    p.add_argument("--out-host", "--ue-host", dest="out_host", type=str,
                   default=os.environ.get("OUT_HOST",
                          os.environ.get("UE_HOST")),
                   help="Destination host for FreeD packets "
                        "(default: preset value, usually 127.0.0.1)")
    p.add_argument("--out-port", "--ue-port", dest="out_port", type=int,
                   default=int(os.environ.get("OUT_PORT",
                          os.environ.get("UE_PORT", 0))) or None,
                   help="Destination UDP port for FreeD packets "
                        "(default: preset value, usually 6301)")
    p.add_argument("--camera-id", type=int,
                   default=int(os.environ.get("CAMERA_ID", 1)),
                   help="FreeD camera ID byte (default 1)")
    p.add_argument("--forward-port", type=int,
                   default=int(os.environ.get("FORWARD_PORT", 0)),
                   help="If set, also re-emit the raw JSON to "
                        "127.0.0.1:<port> so dashboard.py can run "
                        "simultaneously.")
    # ----- Phone-to-lens offset (override knobs) ---------------------------
    # The primary calibration (origin, forward direction, phone→lens offset)
    # is captured ON THE iPHONE via the Calibration wizard and applied before
    # the packet is sent. These flags add a final translation in the FreeD
    # output frame for last-second tweaks without re-running the wizard, or
    # for cases where the iPhone is sending RAW (uncalibrated) pose. Units
    # are metres in FreeD axes: X = right, Y = forward, Z = up.
    p.add_argument("--phone-offset-x", type=float,
                   default=float(os.environ.get("PHONE_OFFSET_X", 0.0)),
                   help="Override: extra X (right) translation in metres, "
                        "applied to the output FreeD pose. (default 0)")
    p.add_argument("--phone-offset-y", type=float,
                   default=float(os.environ.get("PHONE_OFFSET_Y", 0.0)),
                   help="Override: extra Y (forward) translation in metres. "
                        "(default 0)")
    p.add_argument("--phone-offset-z", type=float,
                   default=float(os.environ.get("PHONE_OFFSET_Z", 0.0)),
                   help="Override: extra Z (up) translation in metres. "
                        "Useful when the iPhone profile sets lens height = 0 "
                        "and you want to shift the rig vertically. (default 0)")
    p.add_argument("--control-port", type=int,
                   default=int(os.environ.get("CONTROL_PORT", 5007)),
                   help="UDP control port for live retargeting. Send a JSON "
                        "object like '{\"out_host\":\"192.168.1.50\",\"out_port\":6301}' "
                        "to change the FreeD destination without restarting. "
                        "Set to 0 to disable. (default 5007)")
    p.add_argument("--pos-scale", type=int, choices=(64, 640),
                   default=int(os.environ.get("POS_SCALE",
                                              POS_UNITS_PER_MM_DEFAULT)),
                   help="FreeD position units per millimetre. 64 = original "
                        "BBC/Mo-Sys spec (Unreal default). 640 = Vizrt "
                        "convention. If positions in the target app are off "
                        "by exactly 10x, switch this. (default 64)")
    p.add_argument("--zoom", type=int,
                   default=int(os.environ.get("FREED_ZOOM", 0)),
                   help="Static raw zoom encoder value (0-16777215) placed "
                        "in the FreeD zoom field. LiveFX/Unreal map this "
                        "through their lens calibration. Overridden by a "
                        "'zoom' field in incoming JSON packets. (default 0)")
    p.add_argument("--focus", type=int,
                   default=int(os.environ.get("FREED_FOCUS", 0)),
                   help="Static raw focus encoder value (0-16777215) placed "
                        "in the FreeD focus field. Overridden by a 'focus' "
                        "field in incoming JSON packets. (default 0)")
    args = p.parse_args()

    # argparse skips `choices` validation for non-string defaults, so a
    # POS_SCALE env var like 100 would slip through — reject it here.
    if args.pos_scale not in (64, 640):
        print(f"[ERROR] --pos-scale / POS_SCALE must be 64 or 640, "
              f"got {args.pos_scale}", file=sys.stderr)
        sys.exit(1)

    preset_host, preset_port, preset_label = PRESETS[args.preset]
    out_host = args.out_host or preset_host
    out_port = args.out_port or preset_port

    # Mutable target holder, swapped atomically by the control thread.
    target_lock = threading.Lock()
    target = {"host": out_host, "port": out_port}

    def _control_listener(port):
        """Listen for JSON retarget messages on a UDP port."""
        csock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        csock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            csock.bind(("0.0.0.0", port))
        except OSError as e:
            print(f"[WARN] control port {port} unavailable: {e}",
                  file=sys.stderr)
            return
        while True:
            try:
                raw, src = csock.recvfrom(4096)
                msg = json.loads(raw.decode("utf-8"))
                new_host = str(msg.get("out_host", "")).strip()
                new_port = int(msg.get("out_port", 0))
                if not new_host or not (0 < new_port < 65536):
                    print(f"  ! control msg from {src[0]} rejected: "
                          f"need 'out_host' and 'out_port' (1-65535)",
                          file=sys.stderr)
                    continue
                with target_lock:
                    old = (target["host"], target["port"])
                    target["host"] = new_host
                    target["port"] = new_port
                print(f"  ⟳ FreeD target changed: "
                      f"{old[0]}:{old[1]} → {new_host}:{new_port} "
                      f"(requested by {src[0]})")
            except (json.JSONDecodeError, UnicodeDecodeError, ValueError) as e:
                print(f"  ! malformed control msg: {e}", file=sys.stderr)
            except Exception as e:
                print(f"  ! control listener error: {e}", file=sys.stderr)

    if args.control_port > 0:
        threading.Thread(
            target=_control_listener, args=(args.control_port,),
            daemon=True, name="freed-control"
        ).start()

    in_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    in_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        in_sock.bind(("0.0.0.0", args.listen_port))
    except OSError as e:
        print(f"[ERROR] Cannot bind UDP port {args.listen_port}: {e}",
              file=sys.stderr)
        print("        Is another script (e.g. dashboard.py) already "
              "listening on it?", file=sys.stderr)
        sys.exit(1)

    out_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    fwd_sock = None
    if args.forward_port > 0:
        fwd_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    print("OBTrack → FreeD bridge")
    print(f"  Target           : {preset_label}")
    print(f"  Listening JSON   : 0.0.0.0:{args.listen_port}")
    print(f"  Sending FreeD to : {out_host}:{out_port}  "
          f"(camera id={args.camera_id})")
    if args.control_port > 0:
        print(f"  Control port     : 0.0.0.0:{args.control_port}  "
              "(send JSON {out_host, out_port} to retarget live)")
    print(f"  Position scale   : {args.pos_scale} units/mm "
          f"({'BBC/Mo-Sys spec' if args.pos_scale == 64 else 'Vizrt convention'})")
    if args.zoom or args.focus:
        print(f"  Lens raw values  : zoom={args.zoom}  focus={args.focus}  "
              "(static, overridden by JSON 'zoom'/'focus')")
    print(f"  Euler order      : {EULER_ORDER}  "
          f"(rot signs Y/P/R = {YAW_SIGN:+d}/{PITCH_SIGN:+d}/{ROLL_SIGN:+d})")
    print(f"  Position signs   : X/Y/Z = "
          f"{POS_X_SIGN:+d}/{POS_Y_SIGN:+d}/{POS_Z_SIGN:+d}")
    if any(abs(o) > 1e-9 for o in
           (args.phone_offset_x, args.phone_offset_y, args.phone_offset_z)):
        print(f"  Phone offset (m) : X/Y/Z = "
              f"{args.phone_offset_x:+.3f}/{args.phone_offset_y:+.3f}/"
              f"{args.phone_offset_z:+.3f}  (FreeD axes — override knobs)")
    if fwd_sock:
        print(f"  Mirroring JSON to: 127.0.0.1:{args.forward_port}  "
              "(for dashboard.py)")
    print("Press Ctrl-C to stop.\n")

    count = 0
    last_log = time.time()
    last_profile = None    # tracks profile-name changes for logging

    try:
        while True:
            data, _src = in_sock.recvfrom(65535)
            try:
                pkt = json.loads(data.decode("utf-8"))
                pos = pkt["position"]
                rot = pkt["rotation"]
            except Exception as e:
                print(f"  ! malformed packet: {e}", file=sys.stderr)
                continue

            ue_x, ue_y, ue_z, yaw, pitch, roll = convert_pose(
                (pos["x"], pos["y"], pos["z"]),
                (rot["qx"], rot["qy"], rot["qz"], rot["qw"]),
            )

            # Apply gateway-side phone-offset override (FreeD axes, metres).
            ue_x += args.phone_offset_x
            ue_y += args.phone_offset_y
            ue_z += args.phone_offset_z

            # Lens raw values: JSON packet fields win over CLI statics.
            # (Ready for a future lens-encoder feed, e.g. the ESP32 add-on.)
            try:
                zoom_raw  = int(pkt.get("zoom",  args.zoom))
                focus_raw = int(pkt.get("focus", args.focus))
            except (TypeError, ValueError):
                zoom_raw, focus_raw = args.zoom, args.focus

            freed = build_freed_packet(
                args.camera_id, yaw, pitch, roll, ue_x, ue_y, ue_z,
                zoom=zoom_raw, focus=focus_raw,
                pos_units_per_mm=args.pos_scale)
            with target_lock:
                dst = (target["host"], target["port"])
            out_sock.sendto(freed, dst)

            if fwd_sock:
                fwd_sock.sendto(data, ("127.0.0.1", args.forward_port))

            # Surface profile-name changes so the operator can see which
            # iPhone calibration is currently active.
            profile = pkt.get("profile")
            if profile != last_profile:
                print(f"  → active iPhone profile: "
                      f"{profile or '(raw — no calibration)'}")
                last_profile = profile

            count += 1
            now = time.time()
            if now - last_log >= 1.0:
                print(f"  {count:>4d} pkt/s   "
                      f"→ {dst[0]}:{dst[1]}   "
                      f"pos=({ue_x:+.3f},{ue_y:+.3f},{ue_z:+.3f}) m   "
                      f"rot=({yaw:+6.1f},{pitch:+6.1f},{roll:+6.1f})°   "
                      f"state={pkt.get('trackingState', '?')}")
                last_log = now
                count = 0
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
