#!/bin/bash
# =============================================================================
# LVA System Installer — linux-voice-assistant + Snapcast on Arch Linux
# =============================================================================
# Run as root or with sudo. Tested on Arch Linux with PipeWire + BlueZ.
#
# What this does:
#   1. Copies D-Bus policy for Bluetooth (PipeWire/WirePlumber → BlueZ)
#   2. Copies PipeWire config (lva-snapcast virtual sink)
#   3. Copies WirePlumber config (headless fix, HFP lock, default sink)
#   4. Installs systemd services (stream, watcher, watchdog, BT reconnect)
#   5. Installs helper scripts to /usr/local/bin
#   6. Enables and starts all services
#
# BEFORE RUNNING:
#   - Edit SNAPCAST_HOST, SNAPCAST_PORT, BT_DEVICE_MAC, USERNAME below
#   - Pair and trust your BT device via bluetoothctl first
#   - Make sure snapserver is installed and running
# =============================================================================

set -euo pipefail

# ---- EDIT THESE ----
USERNAME="Guy008"
USER_ID="1000"
SNAPCAST_HOST="192.168.1.30"
SNAPCAST_PORT="2509"
BT_DEVICE_MAC="5C:FB:7C:2F:70:4D"          # colons
BT_DEVICE_MAC_UNDER="5C_FB_7C_2F_70_4D"    # underscores (for WirePlumber)
# --------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME=$(eval echo ~"$USERNAME")

echo "=== LVA System Installer ==="
echo "User: $USERNAME ($USER_ID)"
echo "Snapcast: $SNAPCAST_HOST:$SNAPCAST_PORT"
echo "BT Device: $BT_DEVICE_MAC"
echo ""

# 1. D-Bus policy
echo "[1/6] Installing D-Bus policy..."
cp "$SCRIPT_DIR/dbus/pipewire-bluetooth.conf" /etc/dbus-1/system.d/pipewire-bluetooth.conf
systemctl reload dbus || true

# 2. PipeWire virtual sink
echo "[2/6] Installing PipeWire config (lva-snapcast sink)..."
mkdir -p "$USER_HOME/.config/pipewire/pipewire.conf.d"
cp "$SCRIPT_DIR/pipewire/99-lva-snapcast.conf" \
   "$USER_HOME/.config/pipewire/pipewire.conf.d/99-lva-snapcast.conf"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/pipewire"

# 3. WirePlumber config
echo "[3/6] Installing WirePlumber config..."
mkdir -p "$USER_HOME/.config/wireplumber/wireplumber.conf.d"

cp "$SCRIPT_DIR/wireplumber/51-disable-seat-monitoring.conf" \
   "$USER_HOME/.config/wireplumber/wireplumber.conf.d/51-disable-seat-monitoring.conf"

# Substitute BT MAC in the HFP profile config
sed "s/5C_FB_7C_2F_70_4D/$BT_DEVICE_MAC_UNDER/g" \
    "$SCRIPT_DIR/wireplumber/52-jbl-headset-profile.conf" \
    > "$USER_HOME/.config/wireplumber/wireplumber.conf.d/52-jbl-headset-profile.conf"

cp "$SCRIPT_DIR/wireplumber/53-lva-output-routing.conf" \
   "$USER_HOME/.config/wireplumber/wireplumber.conf.d/53-lva-output-routing.conf"

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/wireplumber"

# 4. Helper scripts
echo "[4/6] Installing helper scripts..."
cp "$SCRIPT_DIR/scripts/lva-snapcast-watcher.sh" /usr/local/bin/lva-snapcast-watcher.sh
cp "$SCRIPT_DIR/scripts/lva-audio-watchdog.sh"   /usr/local/bin/lva-audio-watchdog.sh

# Substitute BT MAC and Snapcast host in bt-reconnect script
sed "s/5C:FB:7C:2F:70:4D/$BT_DEVICE_MAC/g" \
    "$SCRIPT_DIR/scripts/bt-reconnect-jbl.sh" \
    > /usr/local/bin/bt-reconnect-jbl.sh

chmod +x /usr/local/bin/lva-snapcast-watcher.sh \
          /usr/local/bin/lva-audio-watchdog.sh \
          /usr/local/bin/bt-reconnect-jbl.sh

# 5. Systemd services
echo "[5/6] Installing systemd services..."

# Substitute username and Snapcast address in stream service
sed -e "s/User=Guy008/User=$USERNAME/g" \
    -e "s|/run/user/1000|/run/user/$USER_ID|g" \
    -e "s/192.168.1.30:2509/$SNAPCAST_HOST:$SNAPCAST_PORT/g" \
    "$SCRIPT_DIR/systemd/lva-snapcast-stream.service" \
    > /etc/systemd/system/lva-snapcast-stream.service

cp "$SCRIPT_DIR/systemd/lva-snapcast-watcher.service" /etc/systemd/system/lva-snapcast-watcher.service
cp "$SCRIPT_DIR/systemd/lva-audio-watchdog.service"   /etc/systemd/system/lva-audio-watchdog.service
cp "$SCRIPT_DIR/systemd/lva-audio-watchdog.timer"     /etc/systemd/system/lva-audio-watchdog.timer
cp "$SCRIPT_DIR/systemd/bt-reconnect-jbl.service"     /etc/systemd/system/bt-reconnect-jbl.service

# 6. Enable and start
echo "[6/6] Enabling and starting services..."
systemctl daemon-reload

systemctl enable --now lva-snapcast-stream
systemctl enable --now lva-snapcast-watcher
systemctl enable --now lva-audio-watchdog.timer
systemctl enable --now bt-reconnect-jbl

echo ""
echo "=== Done! Restart PipeWire/WirePlumber as $USERNAME: ==="
echo "   systemctl --user restart pipewire pipewire-pulse wireplumber"
echo ""
echo "=== Then bring up the Docker container: ==="
echo "   docker compose up -d"
echo ""
echo "=== Verify: ==="
echo "   systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl"
echo "   ss -tnp | grep $SNAPCAST_PORT   # should show ESTAB with ffmpeg"
