# LVA Setup Guide — Guy008 Home Server
> תיעוד מלא של כל השלבים שבוצעו להקמת linux-voice-assistant עם Snapcast + רמקול בלוטוס על Arch Linux

---

## סביבה

| רכיב | פרטים |
|------|--------|
| שרת | HP ProLiant DL360 Gen9 — Arch Linux (headless) |
| IP שרת | 192.168.1.30 (br0) |
| רמקול | JBL Flip 4 — MAC: `5C:FB:7C:2F:70:4D` |
| Audio stack | PipeWire + WirePlumber |
| Bluetooth stack | BlueZ |
| Wake words | `agent_smitt` (Agent Smith), `maraa_maraa_sheal_hakir` (Magic Mirror) |
| Audio streaming | Snapcast — TCP port 2509 |
| Voice assistant | [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) |
| Home Assistant | ESPHome integration, port 6053 |

---

## חלק א׳ — תיקון בלוטוס על Arch Linux Headless Server

### הבעיה
רמקול JBL Flip 4 לא הצליח להתחבר — שגיאת `Protocol not available` ומצב `br-connection-key-missing`.

### סיבות השורש
1. **WirePlumber seat-monitoring bug**: על שרת headless, logind מדווח על ה-seat כ-`online` במקום `active`. WirePlumber מצפה ל-`active` ולכן לא מפעיל את ה-Bluetooth monitor בכלל.
2. **D-Bus policy חסרה**: קבצי BlueZ כברירת מחדל מאשרים רק root לרשום Bluetooth profiles (MediaEndpoint1, Profile1). PipeWire/WirePlumber רץ כ-user בקבוצת `audio` ונחסם.
3. **מפתחות pairing ישנים**: מפתחות pairing ישנים על הרמקול גרמו ל-`br-connection-key-missing`.

---

### שלב א1 — D-Bus policy לקבוצת audio

צור קובץ `/etc/dbus-1/system.d/pipewire-bluetooth.conf`:

```xml
<!-- Allow PipeWire/WirePlumber (audio group) to register Bluetooth profiles with BlueZ -->
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy group="audio">
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.AdvertisementMonitor1"/>
    <allow send_interface="org.bluez.Agent1"/>
    <allow send_interface="org.bluez.MediaEndpoint1"/>
    <allow send_interface="org.bluez.MediaPlayer1"/>
    <allow send_interface="org.bluez.Profile1"/>
    <allow send_interface="org.bluez.GattCharacteristic1"/>
    <allow send_interface="org.bluez.GattDescriptor1"/>
    <allow send_interface="org.bluez.LEAdvertisement1"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
    <allow send_interface="org.mpris.MediaPlayer2.Player"/>
  </policy>
</busconfig>
```

```sh
sudo systemctl restart dbus
```

---

### שלב א2 — ביטול seat monitoring + נעילת HFP ב-WirePlumber

**שני קבצי config נדרשים:**

**קובץ 1** — `~/.config/wireplumber/wireplumber.conf.d/51-disable-seat-monitoring.conf`:

```
# On headless/server systems, the logind seat state is "online" instead of
# "active", which prevents the bluez monitor from starting. Disabling
# seat-monitoring makes WirePlumber always activate the bluetooth monitor.
wireplumber.profiles = {
  main = {
    monitor.bluez.seat-monitoring = disabled
  }
}
```

**קובץ 2** — `~/.config/wireplumber/wireplumber.conf.d/52-jbl-headset-profile.conf`:

```
# Lock JBL Flip 4 to HFP (headset-head-unit) profile permanently.
#
# WHY THIS IS NEEDED:
# WirePlumber's autoswitch-bluetooth-profile.lua automatically switches the
# BT device from HFP → A2DP 2 seconds after the last capture stream closes
# (e.g. after container restart or PipeWire pipeline changes).
# When in A2DP mode: microphone is unavailable → wake word detection gets
# silence → LVA never triggers.
#
# TWO SETTINGS ARE REQUIRED:
# 1. Disable autoswitch entirely (wireplumber.settings)
# 2. Force HFP on device init (monitor.bluez.rules)

wireplumber.settings = {
  bluetooth.autoswitch-to-headset-profile = false
}

monitor.bluez.rules = [
  {
    matches = [
      { "device.name" = "bluez_card.5C_FB_7C_2F_70_4D" }
    ]
    actions = {
      update-props = {
        "bluez5.profile" = "headset-head-unit"
      }
    }
  }
]
```

> **⚠️ פשרה בסאונד:** HFP מגביל את כרטיס הסאונד של JBL ל-8kHz (mono). איכות הניגון דרך JBL תהיה נמוכה מ-A2DP.
> זה המחיר של שימוש ב-JBL גם כמיקרופון וגם כרמקול בו זמנית.

```sh
systemctl --user restart wireplumber
# לאחר restart — docker compose restart (ה-mic מתנתק ב-wireplumber restart)
```

וודא שהפרופיל נעול:

```sh
pactl list cards short | grep bluez
wpctl status | grep -A5 bluez_card
# צפוי: Active Profile: headset-head-unit
```

---

### שלב א3 — Factory Reset לרמקול + Pairing מחדש

אם יש שגיאת `br-connection-key-missing` (מפתחות pairing ישנים):

1. **Factory reset לרמקול JBL Flip 4**: לחץ volume+ ו-play בו זמנית עד איפוס.
2. הסר מ-bluetoothctl:

```sh
bluetoothctl remove 5C:FB:7C:2F:70:4D
```

3. סקן ו-pair מחדש — **חשוב**: Classic BT scan, לא BLE:

```sh
bluetoothctl power on
bluetoothctl scan bredr    # Classic BT בלבד!
# המתן עד שה-MAC מופיע
bluetoothctl pair 5C:FB:7C:2F:70:4D
bluetoothctl trust 5C:FB:7C:2F:70:4D
bluetoothctl connect 5C:FB:7C:2F:70:4D
```

4. וודא שגם microphone וגם speaker זמינים:

```sh
pactl list sources short | grep bluez    # bluez_input.5C:FB:7C:2F:70:4D
pactl list sinks short | grep bluez      # bluez_output.5C_FB_7C_2F_70_4D.1
```

5. בדיקת microphone:

```sh
parecord --device=bluez_input.5C:FB:7C:2F:70:4D --rate=16000 --channels=1 --format=s16le --raw > /tmp/test.raw
# דבר, ctrl+C, בדוק שהקובץ לא ריק
ls -la /tmp/test.raw
```

---

## חלק ב׳ — PipeWire Virtual Sink (lva-snapcast)

### המטרה
יצירת sink וירטואלי שאליו LVA ינגן. ה-monitor שלו נקלט ונשלח ל-Snapcast דרך TCP.

### שלב ב1 — צור null sink

צור קובץ `~/.config/pipewire/pipewire.conf.d/99-lva-snapcast.conf`:

```
context.objects = [
  { factory = adapter
    args = {
      factory.name                 = support.null-audio-sink
      node.name                    = lva-snapcast
      node.description             = "LVA Snapcast Sink"
      media.class                  = Audio/Sink
      object.linger                = true
      audio.format                 = S16LE
      audio.rate                   = 22050
      audio.channels               = 1
      audio.position               = [ MONO ]
      session.suspend-timeout-seconds = 0
    }
  }
]
```

> **קריטי:** `session.suspend-timeout-seconds = 0` — בלי זה ה-sink עובר למצב SUSPENDED כשאין אודיו, ו-pacat יוצא מיד.

```sh
systemctl --user restart pipewire pipewire-pulse wireplumber
```

בדוק שה-sink קיים ובמצב IDLE (לא SUSPENDED):

```sh
pactl list sinks short | grep lva
# צפוי: lva-snapcast ... IDLE
```

---

### שלב ב2 — WirePlumber: הפוך lva-snapcast ל-default sink

צור קובץ `~/.config/wireplumber/wireplumber.conf.d/53-lva-output-routing.conf`:

```
# Set lva-snapcast as the system default sink.
# All audio output (including MPV inside LVA) routes through Snapcast.
# JBL Flip 4 receives audio via snapclient, NOT directly — this prevents
# double audio (once BT direct, once Snapcast) and ensures all house
# speakers play in sync.

wireplumber.settings = {
  default.audio.sink = "lva-snapcast"
}
```

> **הערה:** גם בלי זה, ה-`AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` ב-.env מכוון את MPV ישירות ל-sink הנכון. הגדרה זו היא שכבת הגנה נוספת.

```sh
systemctl --user restart wireplumber
```

---

## חלק ג׳ — Snapcast — הגדרת TCP Source

### שלב ג1 — ערוך `/etc/snapserver.conf`

**הוסף** את שורת ה-source (פורט 2509):

```ini
source = tcp://0.0.0.0:2509?name=Agent_Smith&mode=server&sampleformat=22050:16:1
```

> - `sampleformat=22050:16:1` — חייב להתאים ל-sink הווירטואלי
> - `mode=server` — Snapcast מאזין, ffmpeg מתחבר אליו
> - אם יש source ישן בשם `Agent_Smith` — שנה את שמו

**הפחת buffer** לצמצום latency (ב-`[stream]` section):

```ini
buffer = 500
```

> **⚠️ אל תרד מתחת ל-500ms** — WiFi clients יתחילו לגמגם. 500ms הוא האיזון הנכון בין latency לאמינות.

**הסר/הערה** sources שאינם נחוצים (למשל AirMusic):

```ini
#source = process:///usr/bin/ffmpeg?name=AirMusic&params=...
```

```sh
sudo systemctl restart snapserver
```

### שלב ג2 — ודא שכל הclients מוגדרים ל-stream הנכון

בדוק דרך Snapcast web UI (http://192.168.1.30:1780) או API:

```sh
curl -s http://localhost:1780/jsonrpc \
  -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | \
  python3 -m json.tool | grep -E "stream_id|id.*Agent"
```

---

## חלק ד׳ — Systemd Service: Audio Stream לSnapcast

### שלב ד1 — צור `/etc/systemd/system/lva-snapcast-stream.service`

```ini
[Unit]
Description=LVA Audio Stream to Snapcast
After=network.target snapserver.service

[Service]
User=Guy008
Environment=PULSE_SERVER=/run/user/1000/pulse/native
Environment=XDG_RUNTIME_DIR=/run/user/1000
Restart=always
RestartSec=3
ExecStart=/bin/bash -c 'pacat --device=lva-snapcast.monitor --record --raw --rate=22050 --channels=1 --format=s16le --latency-msec=50 | \
  ffmpeg -hide_banner -loglevel error \
    -f s16le -ar 22050 -ac 1 -i pipe:0 \
    -f s16le -ar 22050 -ac 1 \
    tcp://192.168.1.30:2509?tcp_nodelay=1'

[Install]
WantedBy=multi-user.target
```

> **חשוב:** `--record --latency-msec=50` נדרשים — בלי `--record`, pacat יוצא מיד כשה-sink IDLE גם אם אינו SUSPENDED.
> `--latency-msec=50` — ערך נמוך לצמצום latency בchain. היה 200ms, הורדנו ל-50ms.

### שלב ד2 — הפעל

```sh
sudo systemctl daemon-reload
sudo systemctl enable lva-snapcast-stream
sudo systemctl start lva-snapcast-stream
```

בדיקה:

```sh
sudo systemctl status lva-snapcast-stream
ss -tnp | grep 2509
# צפוי: ESTAB עם ffmpeg
```

---

## חלק ד׳ב — Watcher: איתחול אוטומטי של Stream בעת Restart

### הבעיה
כשה-Docker container מתחיל מחדש, MPV מתנתק ומתחבר מחדש ל-`lva-snapcast`. pacat (שרץ ב-`lva-snapcast-stream`) נשאר עם חיבור ישן ל-PipeWire node ומתחיל לשדר silence — הכל רץ, אבל אין קול.

### הפתרון: Watcher Service

צור `/usr/local/bin/lva-snapcast-watcher.sh`:

```bash
#!/bin/bash
# Restart lva-snapcast-stream whenever the LVA container (re)starts.
# Root cause: pacat gets a stale PipeWire connection after MPV reconnects.

docker events \
  --filter "container=linux-voice-assistant" \
  --filter "event=start" \
  --format "{{.Time}}" | \
while read -r _; do
  echo "$(date): LVA container started — restarting lva-snapcast-stream in 3s..."
  sleep 3
  systemctl restart lva-snapcast-stream
  echo "$(date): lva-snapcast-stream restarted"
done
```

```sh
sudo chmod +x /usr/local/bin/lva-snapcast-watcher.sh
```

צור `/etc/systemd/system/lva-snapcast-watcher.service`:

```ini
[Unit]
Description=Restart LVA Snapcast Stream when LVA container (re)starts
After=docker.service lva-snapcast-stream.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/lva-snapcast-watcher.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload
sudo systemctl enable lva-snapcast-watcher
sudo systemctl start lva-snapcast-watcher
```

הפעולה: `docker events` מאזין לאירוע `start` של ה-container. כשהוא מתרחש, ממתין 3 שניות (כדי שMPV יספיק להתחבר מחדש ל-lva-snapcast), ומאתחל את pipeline.

---

## חלק ד׳ג — Audio Pipeline Watchdog

### הבעיה
לעיתים ffmpeg מאבד חיבור ל-Snapcast ולא מתחבר מחדש אוטומטית.

### הפתרון: Watchdog Timer

צור `/usr/local/bin/lva-audio-watchdog.sh`:

```bash
#!/bin/bash
# Watchdog: verify audio is actually flowing through the pipeline.
# If ffmpeg loses connection to Snapcast, restart lva-snapcast-stream.

SNAPCAST_PORT="2509"

if ! ss -tn state established "( dport = :$SNAPCAST_PORT or sport = :$SNAPCAST_PORT )" | grep -q ffmpeg 2>/dev/null; then
    if ! ss -tn state established 2>/dev/null | grep -q ":$SNAPCAST_PORT"; then
        echo "$(date): ffmpeg not connected to Snapcast — restarting lva-snapcast-stream"
        systemctl restart lva-snapcast-stream
        exit 0
    fi
fi

if ! docker inspect linux-voice-assistant --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "$(date): LVA container not running"
    exit 0
fi

echo "$(date): OK — pipeline healthy"
```

```sh
sudo chmod +x /usr/local/bin/lva-audio-watchdog.sh
```

צור `/etc/systemd/system/lva-audio-watchdog.service`:

```ini
[Unit]
Description=LVA Audio Pipeline Watchdog
After=lva-snapcast-stream.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lva-audio-watchdog.sh
```

צור `/etc/systemd/system/lva-audio-watchdog.timer`:

```ini
[Unit]
Description=Run LVA Audio Watchdog every 2 minutes

[Timer]
OnBootSec=120
OnUnitActiveSec=120

[Install]
WantedBy=timers.target
```

```sh
sudo systemctl daemon-reload
sudo systemctl enable lva-audio-watchdog.timer
sudo systemctl start lva-audio-watchdog.timer
```

---

## חלק ד׳ד — BT Auto-Reconnect

### הבעיה
כש-JBL מתנתק (BT קצר, שינה, אתחול), ה-Docker container קורס ב-`IndexError: no soundcard` ונכנס ל-crash loop לפני שה-BT מספיק להתחבר מחדש.

### הפתרון: שני מנגנונים

**מנגנון 1:** Auto-reconnect BT כל 15 שניות.

צור `/usr/local/bin/bt-reconnect-jbl.sh`:

```bash
#!/bin/bash
# Auto-reconnect JBL Flip 4 when it disconnects
DEVICE="5C:FB:7C:2F:70:4D"
while true; do
  if ! bluetoothctl info "$DEVICE" 2>/dev/null | grep -q "Connected: yes"; then
    echo "$(date): JBL disconnected, attempting reconnect..."
    bluetoothctl connect "$DEVICE" 2>/dev/null
  fi
  sleep 15
done
```

```sh
sudo chmod +x /usr/local/bin/bt-reconnect-jbl.sh
```

צור `/etc/systemd/system/bt-reconnect-jbl.service`:

```ini
[Unit]
Description=Auto-reconnect JBL Flip 4 Bluetooth
After=bluetooth.service
Requires=bluetooth.service

[Service]
ExecStart=/usr/local/bin/bt-reconnect-jbl.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload
sudo systemctl enable bt-reconnect-jbl
sudo systemctl start bt-reconnect-jbl
```

**מנגנון 2:** המתנה ל-mic ב-entrypoint לפני הפעלת האפליקציה (ראה חלק ה׳).

---

## חלק ה׳ — linux-voice-assistant Docker

### שלב ה1 — קבצי Wake Word מותאמים אישית

מבנה הנפח `wakeword_custom`:

```
/var/lib/docker/volumes/linux-voice-assistant_wakeword_custom/_data/
└── openWakeWord/           ← תיקיה ייעודית לOpenWakeWord
    ├── agent_smitt.tflite
    ├── agent_smitt.json
    ├── maraa_maraa_sheal_hakir.tflite
    └── maraa_maraa_sheal_hakir.json
```

> - `openWakeWord/` — מודלי OpenWakeWord
> - `microWakeWord/` — מודלי MicroWakeWord (תיקיה נפרדת!)

**agent_smitt.json**:
```json
{
  "type": "openWakeWord",
  "wake_word": "Agent Smith",
  "model": "agent_smitt.tflite"
}
```

**maraa_maraa_sheal_hakir.json**:
```json
{
  "type": "openWakeWord",
  "wake_word": "Smart Magic Mirror",
  "model": "maraa_maraa_sheal_hakir.tflite"
}
```

העתק לנפח:

```sh
WAKEWORD_DIR=/var/lib/docker/volumes/linux-voice-assistant_wakeword_custom/_data/openWakeWord
sudo mkdir -p $WAKEWORD_DIR
sudo cp agent_smitt.tflite agent_smitt.json $WAKEWORD_DIR/
sudo cp maraa_maraa_sheal_hakir.tflite maraa_maraa_sheal_hakir.json $WAKEWORD_DIR/
```

---

### שלב ה1ב — libmpv.py: audio-buffer + הסרת audio-stream-silence

הקובץ `linux_voice_assistant/player/libmpv.py` בתוך ה-image שונה משמעותית מה-upstream. יש לbind-mount גרסה מקומית מעודכנת.

**שינויים שבוצעו:**

1. **`audio-buffer = 0.3`** (image מגיע עם 0.8) — מפחית latency
2. **הסרת `audio-stream-silence`** — קריטי!
   - עם `audio-stream-silence = True`: MPV יוצר node `monitor_MONO` בתהליך LVA ש-WirePlumber **לא** מחבר ל-lva-snapcast
   - התוצאה: MPV מנגן אך הסאונד לא מגיע לsink הנכון
   - ללא `audio-stream-silence`: MPV מחבר ישירות ל-lva-snapcast בכל התחלת ניגון

```python
# Audio buffer: keep small to minimise latency through the Snapcast
# pipeline. 0.3s is enough headroom for the PipeWire sink to initialise
# on each play without adding perceptible delay.
# (audio-stream-silence removed: it prevents PipeWire from routing the
# stream correctly to the target sink when using pipewire/ backend.)
self._mpv["audio-buffer"] = 0.3
```

ב-`docker-compose.yml`, תחת `volumes` של `linux-voice-assistant`:
```yaml
- ./linux_voice_assistant/player/libmpv.py:/app/linux_voice_assistant/player/libmpv.py:ro
```

---

### שלב ה1ג — docker-entrypoint.sh: המתנה ל-BT Mic

ה-entrypoint המקורי של ה-image מפעיל את האפליקציה מיד. אם רמקול הBT עדיין לא מחובר, LVA קורסת ב-`IndexError: no soundcard` ו-Docker נכנס ל-crash loop.

**הפתרון:** bind-mount של entrypoint מותאם אישית שממתין עד שה-mic זמין.

מיקום: `docker-entrypoint.sh` (שורש הפרויקט)

**שלבי ההמתנה שנוספו:**
1. המתנה ל-PulseAudio (30 ניסיונות × 1 שניה)
2. המתנה ל-`bluez_input.5C:FB:7C:2F:70:4D` ב-`pactl list sources` (60 ניסיונות × 2 שניות = עד 120 שניות)

ב-`docker-compose.yml`:
```yaml
- ./docker-entrypoint.sh:/app/docker-entrypoint.sh:ro
```

> **חשוב:** שינוי volume mount דורש `docker compose down && docker compose up -d` — לא מספיק `docker compose restart`.

---

### שלב ה2 — קובץ .env

מיקום: `/home/Guy008/Scripts/Server/docker/linux-voice-assistant/.env`

```dotenv
# Linux-Voice-Assistant - Docker Environment Configuration

### User ID:
LVA_USER_ID="1000"
LVA_USER_GROUP="1000"

### Name for this satellite:
CLIENT_NAME="JBL"

### PipeWire socket:
LVA_PULSE_SERVER="/run/user/1000/pulse/native"
LVA_XDG_RUNTIME_DIR="/run/user/1000"
LVA_PULSE_COOKIE="/run/user/1000/pulse/cookie"

### Network:
HOST="0.0.0.0"
NETWORK_INTERFACE="br0"
PORT="6053"

### Audio devices:
AUDIO_INPUT_DEVICE="bluez_input.5C:FB:7C:2F:70:4D"
AUDIO_OUTPUT_DEVICE="pipewire/lva-snapcast"
# Note: lva-snapcast is also the system default PipeWire sink (via WirePlumber
# 53-lva-output-routing.conf), so audio routes there even without this setting.

### Wake word:
WAKE_MODEL="agent_smitt"

### Custom wake words directory (inside container):
WAKE_WORD_DIR="wakewords/custom/openWakeWord"

### Debug — הפעל רק לאבחון:
# ENABLE_DEBUG="1"
```

> **⚠️ `AUDIO_OUTPUT_DEVICE` — prefix קריטי:**
> - `pipewire/lva-snapcast` — שימוש ב-backend PipeWire הישיר (מומלץ, routing נכון יותר)
> - `pulse/lva-snapcast` — שימוש דרך PulseAudio compatibility layer (עובד, אך פחות יעיל)
> - `lva-snapcast` לבד **לא נמצא** — גורם לכל ניגון להיכשל בשקט (reason=4, done_callback לא נקרא)
>
> לבדיקת שמות זמינים: ראה [בדיקת device names](#בדיקת-device-names-של-mpv).

---

### שלב ה3 — docker-compose.yml

Volume mounts קריטיים שנוספו:

```yaml
volumes:
  # Low-latency MPV config override (audio-buffer reduced, audio-stream-silence removed)
  - ./linux_voice_assistant/player/libmpv.py:/app/linux_voice_assistant/player/libmpv.py:ro
  # Wait for BT mic before starting (prevents crash-loop when JBL not ready)
  - ./docker-entrypoint.sh:/app/docker-entrypoint.sh:ro
```

---

### שלב ה4 — הפעלה

```sh
cd /home/Guy008/Scripts/Server/docker/linux-voice-assistant
docker compose up -d
docker compose logs -f
```

> **⚠️ חשוב:** לאחר שינוי ב-.env, קבצי config, או volume mounts — **חובה** `docker compose down && docker compose up -d`.
> `docker compose restart` **לא מחיל** שינויים ב-env_file או volume mounts — הוא רק מאתחל את ה-process הקיים.

בדוק שמילות ההשכמה נטענו (עם `ENABLE_DEBUG="1"`):

```sh
docker compose logs | grep -E "Available wake words|Loading wake model|Server started"
# צפוי:
# Available wake words: ['agent_smitt', ..., 'maraa_maraa_sheal_hakir', ...]
# Loading wake model: agent_smitt
# Loading wake model: maraa_maraa_sheal_hakir
# INFO:__main__:Server started (host=0.0.0.0, port=6053)
```

---

## חלק ו׳ — חיבור ל-Home Assistant

1. **Settings → Devices & Services → Add Integration**
2. בחר **ESPHome**
3. הכנס host: `192.168.1.30`, port: `6053`
4. לחץ **Submit**

לאחר החיבור, ה-satellite "JBL" יופיע ב-HA.  
מילת ההשכמה השנייה (`maraa_maraa_sheal_hakir`) — ניתן להפעיל דרך ה-UI ב-HA לאחר החיבור.

---

## בדיקה מקצה לקצה

1. אמור "Agent Smith"
2. צליל ההשכמה אמור להגיע מכל הרמקולים דרך Snapcast (~500ms עיכוב — נורמלי)
3. שאל שאלה — התשובה תישמע בכל הבית

```sh
# בדוק שה-pipeline חי:
ss -tnp | grep 2509                          # ffmpeg ESTAB
sudo systemctl status lva-snapcast-stream    # active (running)
docker ps | grep linux-voice-assistant       # Up

# בדוק שכל services פועלים:
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl
# צפוי: active × 4

# בדוק שSnapcast מקבל אודיו בעת ניגון:
curl -s http://localhost:1780/jsonrpc \
  -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | \
  python3 -c "import json,sys; [print(s['id'],s['status']) for s in json.load(sys.stdin)['result']['server']['streams']]"
# Agent_Smith: playing (בזמן ניגון), idle (בשקט)
```

---

## פתרון בעיות

| בעיה | סיבה | פתרון |
|------|------|--------|
| `Protocol not available` בחיבור BT | WirePlumber seat-monitoring bug על headless | צור `51-disable-seat-monitoring.conf` (שלב א2) |
| `br-connection-key-missing` | מפתחות pairing ישנים | Factory reset + pair מחדש (שלב א3) |
| JBL לא נמצא ב-scan | bluetoothctl מחפש BLE | השתמש ב-`scan bredr` |
| `KeyError: agent_smitt` ב-Docker | נתיב WAKE_WORD_DIR שגוי | `wakewords/custom/openWakeWord` (לא `app/...`) |
| `lva-snapcast-stream` יוצא מיד | pacat יוצא כשה-sink IDLE | הוסף `--record --latency-msec=50` |
| ה-sink במצב SUSPENDED | session.suspend-timeout-seconds חסר | הוסף ל-99-lva-snapcast.conf (שלב ב1) |
| אין סאונד, disconnect loop מ-HA | `AUDIO_OUTPUT_DEVICE` ללא prefix | שנה ל-`pipewire/lva-snapcast` (שלב ה2) |
| MPV מחזיר reason=4, done_callback לא נקרא | device name לא מוכר ל-MPV | כנ"ל — `pipewire/lva-snapcast` |
| אודיו מגיע ל-JBL ישירות אבל לא לשאר הרמקולים | MPV מנגן ל-JBL BT ישירות, לא דרך Snapcast | וודא `AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` ב-.env |
| מנגן אבל שום דבר לא נשמע ברמקולים | pacat עם חיבור ישן אחרי docker restart — שולח silence | אוטומטי ע"י `lva-snapcast-watcher`. ידנית: `sudo systemctl restart lva-snapcast-stream` |
| מילת השכמה הפסיקה לעבוד אחרי כמה דקות | WirePlumber החליף JBL מ-HFP → A2DP, מיקרופון נעלם | צור `52-jbl-headset-profile.conf` (שלב א2), restart wireplumber + docker |
| Container crash loop כשJBL לא מחובר | LVA קורסת ב-`IndexError: no soundcard` לפני שBT מספיק להתחבר | `bt-reconnect-jbl.service` + wait loop ב-entrypoint (שלב ד׳ד + ה1ג) |
| שינוי ב-.env לא נכנס לתוקף | `docker compose restart` לא מחיל שינויי env | חובה `docker compose down && docker compose up -d` |
| אין אודיו למרות שה-pipeline רץ | `audio-stream-silence=True` שובר routing ב-PipeWire | הסר את `audio-stream-silence` מ-libmpv.py (שלב ה1ב) |

---

## אבחון מתקדם

### בדיקת device names של MPV

```sh
docker exec linux-voice-assistant /app/.venv/bin/python3 -c "
import mpv
m = mpv.MPV(audio_display=False)
devices = m._get_property('audio-device-list')
for d in devices:
    print(d['name'], '—', d.get('description', ''))
m.terminate()
"
# צפוי בפלט:
# pipewire/lva-snapcast — LVA Snapcast Sink
# pipewire/bluez_output.5C_FB_7C_2F_70_4D.1 — JBL Flip 4
```

### בדיקת audio flow בזמן ניגון

```sh
# ניגון ישיר ל-sink ובדיקה שSnapcast מתעורר
paplay --device=lva-snapcast /usr/share/sounds/alsa/Front_Center.wav &
sleep 1
curl -s http://localhost:1780/jsonrpc \
  -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | \
  python3 -c "
import json,sys
for s in json.load(sys.stdin)['result']['server']['streams']:
    if 'Agent_Smith' in s['id']:
        print('Agent_Smith:', s['status'])  # צפוי: playing
"
```

### בדיקת monitor — האם אודיו מגיע

```sh
# לכד 5 שניות מה-monitor ובדוק אם יש ערכים לא-אפס
timeout 5 pacat --device=lva-snapcast.monitor --record --raw \
  --rate=22050 --channels=1 --format=s16le > /tmp/monitor_test.raw 2>/dev/null

python3 -c "
data = open('/tmp/monitor_test.raw','rb').read()
total = len(data)//2
nz = sum(1 for i in range(0, len(data)-1, 2) if data[i]!=0 or data[i+1]!=0)
print(f'Samples: {total}, Non-zero: {nz} ({100*nz/total:.1f}%)' if total else 'No data')
# אם 0% — אין אודיו מגיע לsink; אם >0% — אודיו מגיע, הבעיה בהמשך הchain
"
```

### בדיקת wpctl routing

```sh
wpctl status | grep -A10 "Streams"
# בזמן ניגון ב-LVA, צפוי לראות:
# linux_voice_assistant
#   output_MONO  > LVA Snapcast Sink:playback_MONO  [active]
```

### בדיקת TCP data flow בזמן ניגון

```sh
# בזמן שLVA מנגן — ה-send queue של ffmpeg אמור לעלות מ-0
watch -n0.5 'ss -tnp | grep "2509.*ffmpeg" | awk "{print \"send queue:\", \$3}"'
```

---

## ארכיטקטורה — זרימת האודיו

```
JBL Flip 4 (BT Mic — HFP profile, 8kHz mono)
        │  bluez_input.5C:FB:7C:2F:70:4D
        ▼
  PipeWire (host) — לכידת mic
        │  AUDIO_INPUT_DEVICE
        ▼
linux-voice-assistant (Docker, network=host, uid=1000)
        │  Wake word detection → Home Assistant → STT/TTS
        │  AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
        ▼
  lva-snapcast  (PipeWire Virtual Sink, 22050Hz S16LE mono)
  [session.suspend-timeout-seconds=0 → תמיד IDLE, לא SUSPENDED]
        │  lva-snapcast.monitor
        ▼
  pacat --record --latency-msec=50
        │  raw PCM pipe
        ▼
  ffmpeg  →  TCP:2509 (tcp_nodelay=1)
                │
                ▼
        Snapcast Server (buffer=500ms)
        stream: Agent_Smith, 22050:16:1
                │
     ┌──────────┼──────────────┐
     ▼          ▼              ▼
  JBL Flip 4  חדר עבודה    Android/TV
  (snapclient) (snapclient) clients
```

**שירותי systemd המנהלים את הpipeline:**

| שירות | תפקיד |
|-------|--------|
| `lva-snapcast-stream` | pacat→ffmpeg→Snapcast, מאתחל אוטומטית |
| `lva-snapcast-watcher` | מאזין לdocker events, מאתחל stream אחרי container restart |
| `lva-audio-watchdog.timer` | כל 2 דקות: בודק חיבור ffmpeg לSnapcast |
| `bt-reconnect-jbl` | כל 15 שניות: מנסה reconnect אם JBL מנותק |

**עיכוב כולל צפוי:** ~600–800ms  
- pacat buffer: 50ms  
- MPV audio-buffer: 300ms  
- Snapcast buffer: 500ms  
- (חלקי הbuffers חופפים, העיכוב בפועל ~500–700ms)

---

## קבצים שנוצרו / שונו

| קובץ | פעולה | מטרה |
|------|-------|------|
| `/etc/dbus-1/system.d/pipewire-bluetooth.conf` | נוצר | D-Bus policy לBluetooth |
| `~/.config/wireplumber/wireplumber.conf.d/51-disable-seat-monitoring.conf` | נוצר | תיקון seat-monitoring headless |
| `~/.config/wireplumber/wireplumber.conf.d/52-jbl-headset-profile.conf` | נוצר | נעילת JBL על פרופיל HFP, ביטול autoswitch A2DP |
| `~/.config/wireplumber/wireplumber.conf.d/53-lva-output-routing.conf` | נוצר | lva-snapcast כ-default PipeWire sink |
| `~/.config/pipewire/pipewire.conf.d/99-lva-snapcast.conf` | נוצר | Virtual sink לLVA |
| `/etc/snapserver.conf` | עודכן | הוספת TCP source:2509, buffer=500ms, הסרת AirMusic |
| `/etc/systemd/system/lva-snapcast-stream.service` | נוצר | Streaming pipeline לSnapcast |
| `/usr/local/bin/lva-snapcast-watcher.sh` | נוצר | סקריפט watcher |
| `/etc/systemd/system/lva-snapcast-watcher.service` | נוצר | מאזין לdocker events, מאתחל stream אחרי container restart |
| `/usr/local/bin/lva-audio-watchdog.sh` | נוצר | בדיקת TCP connection לSnapcast |
| `/etc/systemd/system/lva-audio-watchdog.service` | נוצר | oneshot watchdog service |
| `/etc/systemd/system/lva-audio-watchdog.timer` | נוצר | הפעלת watchdog כל 2 דקות |
| `/usr/local/bin/bt-reconnect-jbl.sh` | נוצר | סקריפט auto-reconnect BT |
| `/etc/systemd/system/bt-reconnect-jbl.service` | נוצר | שמירת JBL מחובר |
| `linux_voice_assistant/player/libmpv.py` | עודכן | audio-buffer=0.3, הסרת audio-stream-silence |
| `docker-entrypoint.sh` | עודכן | המתנה ל-PulseAudio + BT mic לפני הפעלה |
| `docker-compose.yml` | עודכן | הוספת volume mounts לlibmpv.py ולentrypoint |
| `.env` | נוצר | הגדרות Docker לLVA, AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast |
| Docker volume `linux-voice-assistant_wakeword_custom` | עודכן | wake word models |

---

*נוצר: אפריל 2026 | שרת: Guy008PUB | Arch Linux + PipeWire + Docker*
