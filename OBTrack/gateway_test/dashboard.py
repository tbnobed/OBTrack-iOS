#!/usr/bin/env python3
"""
dashboard.py — OBTrack Real-Time Graphical Dashboard
=====================================================
Receives UDP tracking data from OBTrack iOS and displays live charts
in your browser — no extra GUI frameworks needed.

Install:
    pip install dash plotly

Run:
    python3 dashboard.py

Then open:  http://127.0.0.1:8050
"""

import socket
import json
import threading
import math
import argparse
from collections import deque
from datetime import datetime

from dash import Dash, dcc, html, Input, Output
import plotly.graph_objects as go

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MAX_HISTORY = 400   # frames kept in memory  (~13 sec at 30 fps)
UDP_PORT    = 5005

# ---------------------------------------------------------------------------
# Thread-safe telemetry buffers
# ---------------------------------------------------------------------------
_lock         = threading.Lock()
_ts           = deque(maxlen=MAX_HISTORY)   # relative timestamp (s)
_px           = deque(maxlen=MAX_HISTORY)   # position metres
_py           = deque(maxlen=MAX_HISTORY)
_pz           = deque(maxlen=MAX_HISTORY)
_roll         = deque(maxlen=MAX_HISTORY)   # Euler degrees
_pitch        = deque(maxlen=MAX_HISTORY)
_yaw          = deque(maxlen=MAX_HISTORY)
_state        = "Waiting for data…"
_packet_count = 0
_rate_window  = deque(maxlen=60)            # wall-clock times for rate calc

# ---------------------------------------------------------------------------
# Quaternion → Euler angles (degrees)
# Convention: roll=X, pitch=Y (tilt), yaw=Z (pan)
# ---------------------------------------------------------------------------
def quat_to_euler(qx, qy, qz, qw):
    # Roll — rotation around X axis
    sinr = 2.0 * (qw * qx + qy * qz)
    cosr = 1.0 - 2.0 * (qx * qx + qy * qy)
    roll = math.degrees(math.atan2(sinr, cosr))

    # Pitch — rotation around Y axis
    sinp = 2.0 * (qw * qy - qz * qx)
    pitch = math.copysign(90.0, sinp) if abs(sinp) >= 1.0 \
            else math.degrees(math.asin(sinp))

    # Yaw — rotation around Z axis
    siny = 2.0 * (qw * qz + qx * qy)
    cosy = 1.0 - 2.0 * (qy * qy + qz * qz)
    yaw = math.degrees(math.atan2(siny, cosy))

    return roll, pitch, yaw

# ---------------------------------------------------------------------------
# UDP listener — runs in a background daemon thread
# ---------------------------------------------------------------------------
def _udp_listener(port: int):
    global _state, _packet_count

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", port))
    except OSError as e:
        print(f"[ERROR] Cannot bind UDP port {port}: {e}")
        return

    t0 = None   # anchor for relative timestamps

    while True:
        try:
            raw, _ = sock.recvfrom(4096)
            pkt    = json.loads(raw.decode("utf-8"))

            pos  = pkt.get("position", {})
            rot  = pkt.get("rotation", {})
            roll, pitch, yaw = quat_to_euler(
                rot.get("qx", 0), rot.get("qy", 0),
                rot.get("qz", 0), rot.get("qw", 1),
            )

            pkt_ts = pkt.get("timestamp", datetime.now().timestamp())
            if t0 is None:
                t0 = pkt_ts
            rel = pkt_ts - t0

            with _lock:
                _ts.append(rel)
                _px.append(pos.get("x", 0))
                _py.append(pos.get("y", 0))
                _pz.append(pos.get("z", 0))
                _roll.append(roll)
                _pitch.append(pitch)
                _yaw.append(yaw)
                _state = pkt.get("trackingState", "?")
                _packet_count += 1
                _rate_window.append(datetime.now().timestamp())

        except (json.JSONDecodeError, UnicodeDecodeError):
            pass   # silently drop malformed packets
        except Exception:
            pass

# ---------------------------------------------------------------------------
# Theme colours
# ---------------------------------------------------------------------------
BG      = "#0f172a"
CARD    = "#1e293b"
TEXT    = "#f1f5f9"
MUTED   = "#64748b"
GREEN   = "#22c55e"
BLUE    = "#3b82f6"
ORANGE  = "#f59e0b"
RED     = "#ef4444"
PURPLE  = "#a855f7"
AXIS    = dict(gridcolor="#334155", zerolinecolor="#475569",
               color=TEXT, linecolor="#334155")

def card_style(extra=None):
    s = {"backgroundColor": CARD, "borderRadius": "10px", "padding": "14px"}
    if extra:
        s.update(extra)
    return s

# ---------------------------------------------------------------------------
# Dash app
# ---------------------------------------------------------------------------
app = Dash(__name__, title="OBTrack Dashboard")
app.layout = html.Div(
    style={"backgroundColor": BG, "minHeight": "100vh",
           "fontFamily": "'SF Mono', 'Fira Code', monospace",
           "color": TEXT, "padding": "16px"},
    children=[

        # ── Header ──────────────────────────────────────────────────────────
        html.Div(
            style={"display": "flex", "alignItems": "center",
                   "marginBottom": "14px", "gap": "12px"},
            children=[
                html.Span("⬤", style={"color": BLUE, "fontSize": "10px"}),
                html.H1("OBTrack", style={"margin": 0, "fontSize": "22px",
                                          "fontWeight": "700", "color": BLUE}),
                html.Span("Real-Time Camera Tracking Dashboard",
                          style={"color": MUTED, "fontSize": "13px"}),
            ],
        ),

        # ── Status cards ────────────────────────────────────────────────────
        html.Div(id="status-row",
                 style={"display": "grid",
                        "gridTemplateColumns": "repeat(4, 1fr)",
                        "gap": "10px", "marginBottom": "14px"}),

        # ── Main charts (3D trace + position over time) ─────────────────────
        html.Div(
            style={"display": "grid", "gridTemplateColumns": "1fr 1fr",
                   "gap": "14px", "marginBottom": "14px"},
            children=[
                html.Div(card_style(), children=[
                    html.P("3D Position Trace",
                           style={"margin": "0 0 6px", "fontSize": "12px",
                                  "color": MUTED, "textTransform": "uppercase",
                                  "letterSpacing": "0.05em"}),
                    dcc.Graph(id="graph-3d", style={"height": "350px"},
                              config={"displayModeBar": False}),
                ]),
                html.Div(card_style(), children=[
                    html.P("Position over Time (metres)",
                           style={"margin": "0 0 6px", "fontSize": "12px",
                                  "color": MUTED, "textTransform": "uppercase",
                                  "letterSpacing": "0.05em"}),
                    dcc.Graph(id="graph-pos", style={"height": "350px"},
                              config={"displayModeBar": False}),
                ]),
            ],
        ),

        # ── Rotation chart ───────────────────────────────────────────────────
        html.Div(card_style({"marginBottom": "14px"}), children=[
            html.P("Camera Rotation over Time (degrees)",
                   style={"margin": "0 0 6px", "fontSize": "12px",
                          "color": MUTED, "textTransform": "uppercase",
                          "letterSpacing": "0.05em"}),
            dcc.Graph(id="graph-rot", style={"height": "220px"},
                      config={"displayModeBar": False}),
        ]),

        # ── Footer ───────────────────────────────────────────────────────────
        html.Div(
            f"Listening on UDP :{UDP_PORT}  •  OBTrack Phase 1",
            style={"color": MUTED, "fontSize": "11px", "textAlign": "center"},
        ),

        # Refresh interval — 10 Hz
        dcc.Interval(id="tick", interval=100, n_intervals=0),
    ],
)

# ---------------------------------------------------------------------------
# Callback — refresh all charts on every tick
# ---------------------------------------------------------------------------
@app.callback(
    Output("status-row",  "children"),
    Output("graph-3d",    "figure"),
    Output("graph-pos",   "figure"),
    Output("graph-rot",   "figure"),
    Input("tick",         "n_intervals"),
)
def refresh(_n):
    with _lock:
        ts      = list(_ts)
        px      = list(_px);  py = list(_py);  pz = list(_pz)
        rolls   = list(_roll); pitches = list(_pitch); yaws = list(_yaw)
        state   = _state
        count   = _packet_count
        window  = list(_rate_window)

    # Packet rate
    rate = 0.0
    if len(window) >= 2:
        span = window[-1] - window[0]
        rate = (len(window) - 1) / span if span > 0 else 0.0

    # ── Status cards ──────────────────────────────────────────────────────
    state_col = GREEN if state == "normal" \
                else (ORANGE if "limited" in state else RED)

    def stat_card(label, value, color=TEXT):
        return html.Div(card_style(), children=[
            html.Div(label, style={"fontSize": "10px", "color": MUTED,
                                   "marginBottom": "6px",
                                   "textTransform": "uppercase",
                                   "letterSpacing": "0.05em"}),
            html.Div(value, style={"fontSize": "18px", "fontWeight": "700",
                                   "color": color}),
        ])

    cur_pos = f"({px[-1]:+.3f}, {py[-1]:+.3f}, {pz[-1]:+.3f})" if px else "—"
    cards = [
        stat_card("Tracking State", state,            state_col),
        stat_card("Packet Rate",    f"{rate:.1f} pps"),
        stat_card("Total Frames",   f"{count:,}"),
        stat_card("Position (m)",   cur_pos),
    ]

    # Shared plot layout helper
    def base(h):
        return dict(
            paper_bgcolor=CARD, plot_bgcolor=CARD,
            font=dict(color=TEXT, size=11, family="SF Mono, Fira Code, monospace"),
            margin=dict(l=44, r=10, t=10, b=36),
            height=h,
            legend=dict(bgcolor="rgba(0,0,0,0)", orientation="h",
                        y=1.12, x=0),
        )

    # ── 3D position trace ────────────────────────────────────────────────
    fig3 = go.Figure()
    if px:
        # Swap ARKit Y↑ → conventional Z↑ for the 3-D view
        fig3.add_trace(go.Scatter3d(
            x=px, y=pz, z=py,
            mode="lines",
            line=dict(color=BLUE, width=3),
            name="Path",
        ))
        fig3.add_trace(go.Scatter3d(
            x=[px[-1]], y=[pz[-1]], z=[py[-1]],
            mode="markers",
            marker=dict(size=7, color=GREEN, symbol="circle"),
            name="Now",
        ))

    axis3 = dict(backgroundcolor=BG, gridcolor="#334155",
                 zerolinecolor="#475569", showbackground=True, color=TEXT)
    fig3.update_layout(
        **base(340),
        scene=dict(
            xaxis=dict(title="X", **axis3),
            yaxis=dict(title="Z", **axis3),
            zaxis=dict(title="Y (up)", **axis3),
            bgcolor=BG,
        ),
    )

    # ── Position over time ───────────────────────────────────────────────
    fig_pos = go.Figure()
    if ts:
        for vals, name, color in [
            (px, "X", RED), (py, "Y (up)", GREEN), (pz, "Z", BLUE)
        ]:
            fig_pos.add_trace(go.Scatter(
                x=ts, y=vals, mode="lines", name=name,
                line=dict(color=color, width=1.8),
            ))
    fig_pos.update_layout(
        **base(340),
        xaxis=dict(title="Time (s)", **AXIS),
        yaxis=dict(title="Metres", **AXIS),
    )

    # ── Rotation over time ───────────────────────────────────────────────
    fig_rot = go.Figure()
    if ts:
        for vals, name, color in [
            (yaws,    "Pan  (Yaw)",   BLUE),
            (pitches, "Tilt (Pitch)", ORANGE),
            (rolls,   "Roll",         PURPLE),
        ]:
            fig_rot.add_trace(go.Scatter(
                x=ts, y=vals, mode="lines", name=name,
                line=dict(color=color, width=1.8),
            ))
    fig_rot.update_layout(
        **base(210),
        xaxis=dict(title="Time (s)", **AXIS),
        yaxis=dict(title="Degrees",  **AXIS),
    )

    return cards, fig3, fig_pos, fig_rot


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="OBTrack Real-Time Dashboard")
    parser.add_argument("--udp-port", type=int, default=5005,
                        help="UDP port to receive tracking data (default 5005)")
    parser.add_argument("--web-port", type=int, default=8050,
                        help="Browser port for the dashboard (default 8050)")
    args = parser.parse_args()

    UDP_PORT = args.udp_port

    # Start UDP listener
    threading.Thread(
        target=_udp_listener, args=(args.udp_port,), daemon=True
    ).start()

    print(f"\n  ┌─────────────────────────────────────────┐")
    print(f"  │  OBTrack Dashboard                      │")
    print(f"  │  UDP  listening on port {args.udp_port:<5}            │")
    print(f"  │  Open http://127.0.0.1:{args.web_port} in browser │")
    print(f"  └─────────────────────────────────────────┘\n")

    app.run(debug=False, port=args.web_port)
