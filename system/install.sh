#!/bin/bash
# =============================================================================
# LVA System Installer — linux-voice-assistant-snapcast
# =============================================================================
# הרץ בתור root (sudo). נבדק על Arch Linux עם PipeWire + BlueZ.
# Run as root (sudo). Tested on Arch Linux with PipeWire + BlueZ.
#
# מה הסקריפט עושה / What this installs:
#   1. D-Bus policy  — מאפשר ל-PipeWire לרשום Bluetooth profiles עם BlueZ
#   2. PipeWire      — virtual null sink "lva-snapcast" (22050Hz mono)
#   3. WirePlumber   — תיקון headless, נעילת HFP, default sink
#   4. Scripts       — /usr/local/bin/ (stream, watchdog, BT reconnect)
#   5. Systemd       — 4 services: stream, watcher, watchdog-timer, bt-reconnect
#   6. Snapserver    — הוספת TCP source לקובץ ה-conf
#   7. Linger        — הפעלת user services ללא login (headless)
#
# לפני הרצה / Before running:
#   1. ערוך את המשתנים בבלוק "EDIT THESE" למטה
#   2. ודא שה-BT כבר paired ו-trusted (bluetoothctl)
#   3. ודא ש-snapserver מותקן
#   4. ודא ש-.env קיים (cp .env.example .env && nano .env)
# =============================================================================

set -euo pipefail

# ╔══════════════════════════════════════╗
# ║         EDIT THESE — ערוך כאן        ║
# ╚══════════════════════════════════════╝

USERNAME="Guy008"                      # שם המשתמש שלך
SNAPCAST_HOST="192.168.1.30"           # IP של שרת Snapcast
SNAPCAST_PORT="2509"                   # פורט TCP של Snapcast
BT_DEVICE_MAC="5C:FB:7C:2F:70:4D"     # MAC של רמקול/מיק בלוטוס (עם נקודותיים)
SNAPSERVER_CONF="/etc/snapserver.conf" # נתיב לקובץ הגדרות Snapcast

# ═══════════════════════════════════════
# אל תשנה מכאן למטה / Do not edit below
# ═══════════════════════════════════════

# Auto-derive MAC with underscores for WirePlumber
BT_DEVICE_MAC_UNDER="${BT_DEVICE_MAC//:/_}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME=$(eval echo ~"$USERNAME")
USER_ID=$(id -u "$USERNAME")

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     LVA Snapcast — System Installer      ║"
echo "╚══════════════════════════════════════════╝"
echo "  User:      $USERNAME (uid=$USER_ID)"
echo "  Snapcast:  $SNAPCAST_HOST:$SNAPCAST_PORT"
echo "  BT Device: $BT_DEVICE_MAC"
echo ""

# ── Pre-flight checks ────────────────────────────────────────────────────────

if [ ! -f "$SCRIPT_DIR/../.env" ]; then
    echo "⚠️  לא נמצא קובץ .env"
    echo "   הרץ: cp .env.example .env && nano .env"
    echo "   ואז הרץ את הסקריפט שוב."
    exit 1
fi

if ! bluetoothctl info "$BT_DEVICE_MAC" &>/dev/null; then
    echo "⚠️  רמקול $BT_DEVICE_MAC לא נמצא בbluetooth. המשך בכל זאת..."
fi

# ── 1. D-Bus policy ──────────────────────────────────────────────────────────
echo "[1/7] D-Bus policy (Bluetooth + PipeWire)..."
cp "$SCRIPT_DIR/dbus/pipewire-bluetooth.conf" /etc/dbus-1/system.d/pipewire-bluetooth.conf
systemctl reload dbus 2>/dev/null || true
echo "      ✓ /etc/dbus-1/system.d/pipewire-bluetooth.conf"

# ── 2. PipeWire virtual sink ─────────────────────────────────────────────────
echo "[2/7] PipeWire virtual sink (lva-snapcast)..."
mkdir -p "$USER_HOME/.config/pipewire/pipewire.conf.d"
cp "$SCRIPT_DIR/pipewire/99-lva-snapcast.conf" \
   "$USER_HOME/.config/pipewire/pipewire.conf.d/99-lva-snapcast.conf"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/pipewire"
echo "      ✓ $USER_HOME/.config/pipewire/pipewire.conf.d/99-lva-snapcast.conf"

# ── 3. WirePlumber config ────────────────────────────────────────────────────
echo "[3/7] WirePlumber config (headless fix + HFP lock + default sink)..."
mkdir -p "$USER_HOME/.config/wireplumber/wireplumber.conf.d"

cp "$SCRIPT_DIR/wireplumber/51-disable-seat-monitoring.conf" \
   "$USER_HOME/.config/wireplumber/wireplumber.conf.d/51-disable-seat-monitoring.conf"

sed "s/5C_FB_7C_2F_70_4D/$BT_DEVICE_MAC_UNDER/g" \
    "$SCRIPT_DIR/wireplumber/52-jbl-headset-profile.conf" \
    > "$USER_HOME/.config/wireplumber/wireplumber.conf.d/52-jbl-headset-profile.conf"

cp "$SCRIPT_DIR/wireplumber/53-lva-output-routing.conf" \
   "$USER_HOME/.config/wireplumber/wireplumber.conf.d/53-lva-output-routing.conf"

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/wireplumber"
echo "      ✓ wireplumber.conf.d/ (51, 52, 53)"

# ── 4. Helper scripts ────────────────────────────────────────────────────────
echo "[4/7] Helper scripts → /usr/local/bin/ ..."
cp "$SCRIPT_DIR/scripts/lva-snapcast-watcher.sh" /usr/local/bin/lva-snapcast-watcher.sh
cp "$SCRIPT_DIR/scripts/lva-audio-watchdog.sh"   /usr/local/bin/lva-audio-watchdog.sh

sed "s/5C:FB:7C:2F:70:4D/$BT_DEVICE_MAC/g" \
    "$SCRIPT_DIR/scripts/bt-reconnect-jbl.sh" \
    > /usr/local/bin/bt-reconnect-jbl.sh

chmod +x /usr/local/bin/lva-snapcast-watcher.sh \
          /usr/local/bin/lva-audio-watchdog.sh \
          /usr/local/bin/bt-reconnect-jbl.sh
echo "      ✓ lva-snapcast-watcher, lva-audio-watchdog, bt-reconnect-jbl"

# ── 5. Systemd services ──────────────────────────────────────────────────────
echo "[5/7] Systemd services..."

sed -e "s/User=Guy008/User=$USERNAME/g" \
    -e "s|/run/user/1000|/run/user/$USER_ID|g" \
    -e "s/192.168.1.30:2509/$SNAPCAST_HOST:$SNAPCAST_PORT/g" \
    "$SCRIPT_DIR/systemd/lva-snapcast-stream.service" \
    > /etc/systemd/system/lva-snapcast-stream.service

cp "$SCRIPT_DIR/systemd/lva-snapcast-watcher.service" /etc/systemd/system/lva-snapcast-watcher.service
cp "$SCRIPT_DIR/systemd/lva-audio-watchdog.service"   /etc/systemd/system/lva-audio-watchdog.service
cp "$SCRIPT_DIR/systemd/lva-audio-watchdog.timer"     /etc/systemd/system/lva-audio-watchdog.timer
cp "$SCRIPT_DIR/systemd/bt-reconnect-jbl.service"     /etc/systemd/system/bt-reconnect-jbl.service

systemctl daemon-reload
systemctl enable --now lva-snapcast-stream
systemctl enable --now lva-snapcast-watcher
systemctl enable --now lva-audio-watchdog.timer
systemctl enable --now bt-reconnect-jbl
echo "      ✓ כל 4 השירותים פעילים"

# ── 6. Snapserver TCP source ─────────────────────────────────────────────────
echo "[6/7] Snapserver config ($SNAPSERVER_CONF)..."
SNAP_SOURCE="source = tcp://0.0.0.0:${SNAPCAST_PORT}?name=LVA&mode=server&sampleformat=22050:16:1"

if [ -f "$SNAPSERVER_CONF" ]; then
    if grep -q "tcp://0.0.0.0:${SNAPCAST_PORT}" "$SNAPSERVER_CONF"; then
        echo "      ✓ TCP source כבר קיים בsnapserver.conf"
    else
        # Add source line after [stream] section
        sed -i "/^\[stream\]/a $SNAP_SOURCE" "$SNAPSERVER_CONF"
        systemctl restart snapserver 2>/dev/null || true
        echo "      ✓ הוספת TCP source לsnapserver.conf"
    fi

    # Set buffer to 500ms if higher
    CURRENT_BUFFER=$(grep -E "^buffer\s*=" "$SNAPSERVER_CONF" | grep -o '[0-9]*' | head -1 || echo "1000")
    if [ "${CURRENT_BUFFER:-1000}" -gt 500 ]; then
        sed -i "s/^buffer\s*=.*/buffer = 500/" "$SNAPSERVER_CONF"
        echo "      ✓ buffer → 500ms"
    fi
else
    echo "      ⚠️  $SNAPSERVER_CONF לא נמצא — הוסף ידנית:"
    echo "         $SNAP_SOURCE"
    echo "         buffer = 500"
fi

# ── 7. Linger (user services without login — headless) ───────────────────────
echo "[7/7] Enabling linger for $USERNAME (user services on boot)..."
loginctl enable-linger "$USERNAME"
echo "      ✓ linger enabled"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅  התקנה הושלמה! / Installation complete!                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  שלב הבא — Next steps:"
echo ""
echo "  1. אתחל PipeWire (כ-user, לא root) / Restart PipeWire (as $USERNAME):"
echo "     su - $USERNAME -c 'systemctl --user restart pipewire pipewire-pulse wireplumber'"
echo ""
echo "  2. הרם את הcontainer / Start the container:"
echo "     cd $(dirname "$SCRIPT_DIR") && docker compose up -d"
echo ""
echo "  3. בדיקה / Verify:"
echo "     systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl"
echo "     ss -tnp | grep $SNAPCAST_PORT"
echo ""
