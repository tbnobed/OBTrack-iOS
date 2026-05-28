# OBTrack Gateway

Everything you need on the **PC / Ubuntu server** that sits between the
iPhone and Unreal Engine / Assimilate LiveFX. This is the same code that
ships inside the iOS app tarball — packaged separately here so you can
update the gateway without re-extracting the iOS project every time.

```
OBTrack_Gateway/
├── freed_bridge.py        # JSON → FreeD bridge (Unreal / LiveFX)
├── dashboard.py           # Live web dashboard (Dash/Plotly)
├── udp_receiver.py        # Plain JSON sniffer for debugging
├── setup_ubuntu.sh        # One-shot Ubuntu installer (systemd)
├── requirements.txt       # Python deps for ad-hoc / Mac use
├── UNREAL_SETUP.md        # Live Link FreeD setup
├── LIVEFX_SETUP.md        # Assimilate LiveFX setup
└── docs/
    └── ESP32_UWB_INTEGRATION_PLAN.md
```

---

## Install on Ubuntu (recommended)

Copy the tarball to the server, then:

```bash
tar -xzf OBTrack_Gateway.tar.gz
cd OBTrack_Gateway
sudo FREED_HOST=<unreal-pc-ip> FREED_PRESET=unreal bash setup_ubuntu.sh
```

This installs Python deps, creates two systemd services (`obtrack-bridge`,
`obtrack-dashboard`), starts them, and enables them at boot.

* Bridge listens on UDP **5005** for iPhone JSON, sends FreeD to
  `<unreal-pc-ip>:6301`.
* Dashboard at `http://<server-ip>:8050`.

Useful commands afterwards:

```bash
sudo systemctl status  obtrack-bridge obtrack-dashboard
sudo systemctl restart obtrack-bridge
sudo journalctl -u obtrack-bridge -f          # follow logs
```

---

## Run ad-hoc (Mac, Windows, or no-systemd)

```bash
cd OBTrack_Gateway
pip3 install -r requirements.txt

# terminal 1 — bridge
python3 freed_bridge.py --preset unreal \
                        --out-host 127.0.0.1 \
                        --forward-port 5006

# terminal 2 — dashboard
python3 dashboard.py --udp-port 5006 --host 0.0.0.0
```

Open `http://localhost:8050` for the dashboard.

---

## Common bridge flags

| Flag                      | Default      | Notes                                              |
|---------------------------|--------------|----------------------------------------------------|
| `--listen-port`           | `5005`       | UDP port the iPhone sends to                       |
| `--preset`                | `generic`    | `unreal`, `livefx`, or `generic`                   |
| `--out-host` / `--out-port` | `127.0.0.1:6301` | Destination for FreeD packets                  |
| `--camera-id`             | `1`          | FreeD camera ID byte                               |
| `--forward-port`          | off          | Also mirror raw JSON to `127.0.0.1:<port>` (dashboard) |
| `--phone-offset-x/y/z`    | `0`          | Extra translation (m, FreeD axes) on top of iPhone calibration |

Per-axis sign knobs (`POS_X_SIGN`, `YAW_SIGN`, etc.) live at the top of
`freed_bridge.py` — flip them and restart if Unreal moves the wrong way.

---

## Verifying iPhone packets arrive

```bash
python3 udp_receiver.py            # prints each incoming JSON packet
```

If nothing shows up: same Wi-Fi, firewall, correct gateway IP entered on
the phone.

---

## Updating

When a new gateway tarball lands:

```bash
sudo systemctl stop obtrack-bridge obtrack-dashboard
tar -xzf OBTrack_Gateway.tar.gz -C ~/
sudo bash ~/OBTrack_Gateway/setup_ubuntu.sh
```

`setup_ubuntu.sh` is idempotent — re-running it re-installs deps and
re-writes the service unit files.

---

## Roadmap

Phase 3 adds an ESP32 + UWB anchor receiver and a fusion module. The full
design (anchor placement, packet schemas, fusion math, milestones) is in
[`docs/ESP32_UWB_INTEGRATION_PLAN.md`](docs/ESP32_UWB_INTEGRATION_PLAN.md).
