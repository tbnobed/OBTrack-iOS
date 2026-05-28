#!/usr/bin/env python3
"""
udp_receiver.py — OBTrack Phase 1 Gateway Test
================================================
Listens for UDP packets on port 5005 and prints the JSON tracking data
sent by the OBTrack iOS app.

Usage:
    python3 udp_receiver.py [--port PORT] [--host HOST]

Defaults:
    host: 0.0.0.0  (listen on all interfaces)
    port: 5005

Press Ctrl+C to stop.
"""

import socket
import json
import argparse
import sys
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="OBTrack UDP Receiver")
    parser.add_argument("--host", default="0.0.0.0",
                        help="Interface to listen on (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=5005,
                        help="UDP port to listen on (default: 5005)")
    return parser.parse_args()


def format_packet(data: dict) -> str:
    """Return a compact, human-readable summary of a tracking packet."""
    pos = data.get("position", {})
    rot = data.get("rotation", {})
    return (
        f"[Frame {data.get('frame', '?'):>6}] "
        f"state={data.get('trackingState', '?'):<20} "
        f"pos=({pos.get('x', 0):+.4f}, {pos.get('y', 0):+.4f}, {pos.get('z', 0):+.4f})  "
        f"quat=({rot.get('qx', 0):+.4f}, {rot.get('qy', 0):+.4f}, "
        f"{rot.get('qz', 0):+.4f}, {rot.get('qw', 0):+.4f})"
    )


def main():
    args = parse_args()

    # Create a UDP socket bound to the specified host and port
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        sock.bind((args.host, args.port))
    except OSError as e:
        print(f"ERROR: Cannot bind to {args.host}:{args.port} — {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OBTrack UDP Receiver listening on {args.host}:{args.port}")
    print("Waiting for packets from the iOS app … (Ctrl+C to stop)\n")

    packet_count = 0
    try:
        while True:
            # Receive up to 4096 bytes per packet
            try:
                raw_data, addr = sock.recvfrom(4096)
            except OSError as e:
                print(f"Socket error: {e}", file=sys.stderr)
                continue

            packet_count += 1
            timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]

            # Attempt to decode and parse the JSON payload
            try:
                text = raw_data.decode("utf-8")
                data = json.loads(text)
                print(f"{timestamp}  {format_packet(data)}")
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                # Handle malformed or non-JSON packets gracefully
                print(f"{timestamp}  [MALFORMED from {addr}] ({len(raw_data)} bytes) — {e}")
            except Exception as e:
                # Catch-all: never crash the receiver
                print(f"{timestamp}  [ERROR] {e}")

    except KeyboardInterrupt:
        print(f"\n\nStopped. Received {packet_count} total packets.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
