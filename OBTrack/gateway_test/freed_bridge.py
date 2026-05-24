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
import time


# ===========================================================================
# Coordinate frame: ARKit → Unreal
#
# ARKit world:   +X right,   +Y up,    -Z forward   (right-handed)
# Unreal world:  +X forward, +Y right, +Z up        (left-handed)
#
# A single basis-change matrix M is used for BOTH position and rotation so
# the two can never drift into different frames.
#
#   M = [[ 0, 0,-1],     so that  (ue_x, ue_y, ue_z) = M · (ar_x, ar_y, ar_z)
#        [ 1, 0, 0],              = (-ar_z, ar_x, ar_y)
#        [ 0, 1, 0]]
#
# For rotations:  R_ue = M · R_arkit · Mᵀ
# ===========================================================================
M = [
    [0.0, 0.0, -1.0],
    [1.0, 0.0,  0.0],
    [0.0, 1.0,  0.0],
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

# Per-axis position sign knobs, applied AFTER the basis change. Use these
# to fix axis inversions discovered on set without touching the matrix M.
POS_X_SIGN  =  1      # UE +X = forward
POS_Y_SIGN  =  1      # UE +Y = right
POS_Z_SIGN  = -1      # UE +Z = up     (verified: height was inverted, flipped)


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
# FreeD D1 packet (29 bytes) — unchanged scaling/checksum
# ---------------------------------------------------------------------------
ANGLE_SCALE = 32768.0          # FreeD units per degree
POS_SCALE_PER_M = 64_000.0     # FreeD units per metre (1 mm = 64 units)


def build_freed_packet(camera_id, pan_deg, tilt_deg, roll_deg,
                       x_m, y_m, z_m, zoom=0, focus=0):
    pkt = bytearray()
    pkt.append(0xD1)
    pkt.append(camera_id & 0xFF)
    pkt += pack_int24_be(pan_deg  * ANGLE_SCALE)
    pkt += pack_int24_be(tilt_deg * ANGLE_SCALE)
    pkt += pack_int24_be(roll_deg * ANGLE_SCALE)
    pkt += pack_int24_be(x_m * POS_SCALE_PER_M)
    pkt += pack_int24_be(y_m * POS_SCALE_PER_M)
    pkt += pack_int24_be(z_m * POS_SCALE_PER_M)
    pkt += pack_uint24_be(zoom)
    pkt += pack_uint24_be(focus)
    pkt += b"\x00\x00"
    checksum = (0x40 - sum(pkt)) & 0xFF
    pkt.append(checksum)
    assert len(pkt) == 29, len(pkt)
    return bytes(pkt)


# ---------------------------------------------------------------------------
# Unified ARKit → Unreal pose conversion
# ---------------------------------------------------------------------------
M_T = mat3_transpose(M)


def convert_pose(arkit_pos, arkit_quat):
    """
    arkit_pos:  (x, y, z) in metres, ARKit world frame
    arkit_quat: (qx, qy, qz, qw)

    Returns:
        (ue_x, ue_y, ue_z, yaw_deg, pitch_deg, roll_deg)
        — in Unreal's left-handed frame, with calibration signs applied.
    """
    # Position: single matrix application, then per-axis calibration signs
    ue_x, ue_y, ue_z = mat3_vec(M, arkit_pos)

    # Rotation: same basis change, then extract Euler from R_ue
    R_ar = quat_to_R(*arkit_quat)
    R_ue = mat3_mul(mat3_mul(M, R_ar), M_T)
    yaw_raw, pitch_raw, roll_raw = euler_from_R(R_ue, EULER_ORDER)

    return (
        POS_X_SIGN * ue_x,
        POS_Y_SIGN * ue_y,
        POS_Z_SIGN * ue_z,
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
    args = p.parse_args()

    preset_host, preset_port, preset_label = PRESETS[args.preset]
    out_host = args.out_host or preset_host
    out_port = args.out_port or preset_port

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
    print(f"  Euler order      : {EULER_ORDER}  "
          f"(rot signs Y/P/R = {YAW_SIGN:+d}/{PITCH_SIGN:+d}/{ROLL_SIGN:+d})")
    print(f"  Position signs   : X/Y/Z = "
          f"{POS_X_SIGN:+d}/{POS_Y_SIGN:+d}/{POS_Z_SIGN:+d}")
    if fwd_sock:
        print(f"  Mirroring JSON to: 127.0.0.1:{args.forward_port}  "
              "(for dashboard.py)")
    print("Press Ctrl-C to stop.\n")

    count = 0
    last_log = time.time()

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

            freed = build_freed_packet(
                args.camera_id, yaw, pitch, roll, ue_x, ue_y, ue_z)
            out_sock.sendto(freed, (out_host, out_port))

            if fwd_sock:
                fwd_sock.sendto(data, ("127.0.0.1", args.forward_port))

            count += 1
            now = time.time()
            if now - last_log >= 1.0:
                print(f"  {count:>4d} pkt/s   "
                      f"pos=({ue_x:+.3f},{ue_y:+.3f},{ue_z:+.3f}) m   "
                      f"rot=({yaw:+6.1f},{pitch:+6.1f},{roll:+6.1f})°   "
                      f"state={pkt.get('trackingState', '?')}")
                last_log = now
                count = 0
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
