#!/usr/bin/env python3
"""
freed_bridge.py — OBTrack JSON → FreeD UDP bridge for Unreal Engine.

Listens for OBTrack JSON packets from the iPhone, converts each one to a
29-byte FreeD "D1" packet, and forwards it to Unreal Engine's built-in
Live Link FreeD source.

Quick start:
    python3 freed_bridge.py
    python3 freed_bridge.py --ue-host 127.0.0.1 --ue-port 6301

Run the dashboard at the same time:
    # terminal 1
    python3 freed_bridge.py --forward-port 5006
    # terminal 2
    python3 dashboard.py --udp-port 5006

Defaults:
    listen port  : 5005   (matches the iPhone app)
    UE host:port : 127.0.0.1:6301
    camera id    : 1
"""

import argparse
import json
import math
import os
import socket
import sys
import time


# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------
def quat_to_euler_deg(qx, qy, qz, qw):
    """
    Convert quaternion to (yaw, pitch, roll) in degrees.
    Intrinsic Tait–Bryan Y-X-Z order (yaw around Y, pitch around X, roll around Z),
    which matches the way ARKit's camera transform is normally interpreted.
    """
    # pitch (X)
    sinp = 2.0 * (qw * qx - qy * qz)
    sinp = max(-1.0, min(1.0, sinp))
    pitch = math.asin(sinp)
    # yaw (Y)
    yaw = math.atan2(2.0 * (qw * qy + qx * qz),
                     1.0 - 2.0 * (qx * qx + qy * qy))
    # roll (Z)
    roll = math.atan2(2.0 * (qw * qz + qx * qy),
                      1.0 - 2.0 * (qx * qx + qz * qz))
    return math.degrees(yaw), math.degrees(pitch), math.degrees(roll)


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
#
#   [0]      0xD1  message type
#   [1]      camera id
#   [2:5]    pan   (yaw)   int24, scale = 32768  units per degree
#   [5:8]    tilt  (pitch) int24, scale = 32768  units per degree
#   [8:11]   roll          int24, scale = 32768  units per degree
#   [11:14]  X position    int24, scale = 64     units per millimetre
#   [14:17]  Y position    int24, scale = 64     units per millimetre
#   [17:20]  Z position    int24, scale = 64     units per millimetre
#   [20:23]  zoom          uint24
#   [23:26]  focus         uint24
#   [26:28]  reserved      uint16
#   [28]     checksum = (0x40 - sum(bytes[0..27])) & 0xFF
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
# Coordinate mapping ARKit → Unreal
#
# ARKit world:   +X right, +Y up,  -Z forward   (right-handed)
# Unreal world:  +X forward, +Y right, +Z up    (left-handed)
#
# The mapping below is a reasonable default. If the camera moves the wrong
# way in Unreal you can flip individual axes via the Live Link Controller
# component on the CineCameraActor (Transform → Use Rotation X / Y / Z).
# ---------------------------------------------------------------------------
def remap_position(x, y, z):
    return (-z, x, y)   # (UE_X, UE_Y, UE_Z)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(
        description="OBTrack JSON → FreeD bridge for Unreal Engine")
    p.add_argument("--listen-port", type=int,
                   default=int(os.environ.get("OBTRACK_PORT", 5005)),
                   help="UDP port to receive OBTrack JSON (default 5005)")
    p.add_argument("--ue-host", type=str,
                   default=os.environ.get("UE_HOST", "127.0.0.1"),
                   help="Unreal Engine host (default 127.0.0.1)")
    p.add_argument("--ue-port", type=int,
                   default=int(os.environ.get("UE_PORT", 6301)),
                   help="Unreal Engine FreeD port (default 6301)")
    p.add_argument("--camera-id", type=int,
                   default=int(os.environ.get("CAMERA_ID", 1)),
                   help="FreeD camera ID byte (default 1)")
    p.add_argument("--forward-port", type=int,
                   default=int(os.environ.get("FORWARD_PORT", 0)),
                   help="If set, also re-emit the raw JSON to "
                        "127.0.0.1:<port> so dashboard.py can run "
                        "simultaneously.")
    args = p.parse_args()

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
    print(f"  Listening JSON   : 0.0.0.0:{args.listen_port}")
    print(f"  Sending FreeD to : {args.ue_host}:{args.ue_port}  "
          f"(camera id={args.camera_id})")
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

            yaw, pitch, roll = quat_to_euler_deg(
                rot["qx"], rot["qy"], rot["qz"], rot["qw"])
            ue_x, ue_y, ue_z = remap_position(pos["x"], pos["y"], pos["z"])

            freed = build_freed_packet(
                args.camera_id, yaw, pitch, roll, ue_x, ue_y, ue_z)
            out_sock.sendto(freed, (args.ue_host, args.ue_port))

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
