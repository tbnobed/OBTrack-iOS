#!/usr/bin/env python3
"""
set_freed_target.py — retarget the OBTrack FreeD bridge without restarting.

Sends a single UDP JSON message to the bridge's control port. The bridge
swaps its FreeD destination atomically on the next packet.

Usage:
    python3 set_freed_target.py 192.168.1.50              # default port 6301
    python3 set_freed_target.py 192.168.1.50 6301
    python3 set_freed_target.py 10.0.0.5 6301 --bridge-host gateway.local
    python3 set_freed_target.py 10.0.0.5 6301 --control-port 5007

Defaults:
    bridge host   : 127.0.0.1   (the machine running freed_bridge.py)
    control port  : 5007        (matches freed_bridge.py default)
"""
import argparse
import json
import socket
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("host", help="New FreeD destination host (Unreal / LiveFX PC)")
    p.add_argument("port", nargs="?", type=int, default=6301,
                   help="New FreeD destination UDP port (default 6301)")
    p.add_argument("--bridge-host", default="127.0.0.1",
                   help="Where freed_bridge.py is running (default 127.0.0.1)")
    p.add_argument("--control-port", type=int, default=5007,
                   help="Bridge's control UDP port (default 5007)")
    args = p.parse_args()

    if not (0 < args.port < 65536):
        print(f"error: port {args.port} out of range", file=sys.stderr)
        sys.exit(2)

    msg = json.dumps({"out_host": args.host, "out_port": args.port}).encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(msg, (args.bridge_host, args.control_port))
    print(f"✓ sent retarget to {args.bridge_host}:{args.control_port} → "
          f"FreeD output now goes to {args.host}:{args.port}")
    print("  (check the bridge terminal — it will print a confirmation line)")


if __name__ == "__main__":
    main()
