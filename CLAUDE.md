# linux-voice-assistant-snapcast — CLAUDE.md

> קרא את זה לפני כל פעולה. זה מתאר את המצב הנוכחי, ארכיטקטורת המערכת, ואת כל ההחלטות שנלמדו בדרך הקשה.

---

## סטטוס: עובד במלואו (אפריל 2026)

המערכת שומעת, מגיבה, והקול יוצא בכל רמקולי הבית דרך Snapcast.

---

## גיא — מי הוא ואיך לעבוד איתו

- Mad scientist. חושב בתמונות ומטפורות. רעיונות גדולים מתקבלים בברכה.
- **מאשר לבצע פעולות עצמאית**: sudo, systemctl, docker, קבצי config — אין צורך לבקש אישור.
- כשיש שגיאה — לאבחן, לתקן, לדווח. לא לשאול כל פעם.

---

## מה הפרויקט הזה

Fork של [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) עם שינוי אחד מרכזי:
**כל האודיו של העוזר הקולי עובר דרך Snapcast** — כל הרמקולים בבית שומעים בסנכרון.

השרת הוא HP ProLiant DL360 Gen9, Arch Linux headless, IP: `192.168.1.30`.
רמקול/מיק: JBL Flip 4 Bluetooth, MAC: `5C:FB:7C:2F:70:4D`.

---

## ארכיטקטורת אודיו (קריטי להבין)

```
JBL Flip 4 (BT HFP mic, 8kHz)
    │ bluez_input.5C:FB:7C:2F:70:4D
    ▼
PipeWire (host)
    │ AUDIO_INPUT_DEVICE
    ▼
linux-voice-assistant Docker  ←→  Home Assistant (STT/TTS)
    │ AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
    ▼
lva-snapcast (PipeWire virtual null sink, 22050Hz S16LE mono)
    │ lva-snapcast.monitor
    ▼
pacat --record --latency-msec=50
    │ raw PCM pipe
    ▼
ffmpeg → TCP:2509 → Snapcast Server → כל הרמקולים בבית
```

---

## קבצים שהשתנו מה-upstream ולמה

### `linux_voice_assistant/player/libmpv.py`
**volume-mounted לתוך הcontainer** (לא נבנה בתוך ה-image).

שינויים:
- `audio-buffer = 0.3` (במקום 0.8) — להפחתת latency
- `audio-stream-silence` — **הוסר לחלוטין**

**⚠️ אל תחזיר את `audio-stream-silence`!**
הסיבה: עם `audio-stream-silence=True`, MPV יוצר node `monitor_MONO` בתהליך LVA שWirePlumber לא מחבר ל-lva-snapcast. התוצאה: MPV "מנגן" אבל הסאונד לא מגיע לsink. הבאג נראה כאילו הכל עובד (AO: pipewire, state: PLAYING) אבל הmonitor ריק.

### `docker-entrypoint.sh`
**volume-mounted לתוך הcontainer**.

נוסף: לולאת המתנה ל-PulseAudio (30 ניסיונות) ולBT mic (60 ניסיונות × 2 שניות).
**למה:** LVA קורסת ב-`IndexError: no soundcard` אם ה-BT mic לא זמין. Docker נכנס ל-crash loop שמונע מה-BT להתחבר מחדש.

### `docker-compose.yml`
נוספו שני volume mounts:
```yaml
- ./linux_voice_assistant/player/libmpv.py:/app/linux_voice_assistant/player/libmpv.py:ro
- ./docker-entrypoint.sh:/app/docker-entrypoint.sh:ro
```
**⚠️ שינוי ב-volume mounts דורש `docker compose down && docker compose up -d`**. לא מספיק `restart`.

### `.env`
```dotenv
AUDIO_OUTPUT_DEVICE="pipewire/lva-snapcast"
```
**⚠️ prefix קריטי**: `pipewire/` — בלי זה MPV לא מוצא את הdevice ומחזיר reason=4 בשקט.

---

## שירותי systemd (כולם מותקנים ע"י `system/install.sh`)

| שירות | מה הוא עושה | למה הוא קיים |
|-------|------------|--------------|
| `lva-snapcast-stream` | pacat→ffmpeg→TCP:2509 | מזרים אודיו מה-sink לSnapcast |
| `lva-snapcast-watcher` | docker events → restart stream אחרי 3s | pacat מקבל חיבור ישן אחרי container restart — שולח silence |
| `lva-audio-watchdog.timer` | כל 2 דק׳: בודק ffmpeg TCP | ffmpeg יכול לאבד חיבור |
| `bt-reconnect-jbl` | כל 15 שנ׳: bluetoothctl connect | JBL מתנתק לפעמים |

---

## WirePlumber config files (ב-`~/.config/wireplumber/wireplumber.conf.d/`)

| קובץ | מה הוא עושה | למה הוא קריטי |
|------|------------|---------------|
| `51-disable-seat-monitoring.conf` | מבטל seat monitoring | על headless server, logind מדווח seat=online לא active → WirePlumber לא מפעיל BT monitor |
| `52-jbl-headset-profile.conf` | נועל JBL על HFP + מבטל autoswitch | WirePlumber מחליף ל-A2DP אחרי שהstream נסגר → מיק נעלם |
| `53-lva-output-routing.conf` | lva-snapcast = default sink | שכבת הגנה נוספת לניתוב MPV |

---

## אבחון מהיר

```bash
# כל השירותים פועלים?
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl

# ffmpeg מחובר לSnapcast?
ss -tnp | grep 2509   # צפוי: ESTAB עם ffmpeg

# האם JBL מחובר ובפרופיל HFP?
bluetoothctl info 5C:FB:7C:2F:70:4D | grep -E "Connected|Profile"

# האם lva-snapcast sink קיים?
pactl list sinks short | grep lva

# האם MPV רואה את lva-snapcast?
docker exec linux-voice-assistant /app/.venv/bin/python3 -c "
import mpv; m=mpv.MPV(audio_display=False)
print([d['name'] for d in m._get_property('audio-device-list') if 'snapcast' in d['name']])
"

# בדיקת זרימת אודיו (5 שניות):
timeout 5 pacat --device=lva-snapcast.monitor --record --raw \
  --rate=22050 --channels=1 --format=s16le > /tmp/t.raw 2>/dev/null
python3 -c "
d=open('/tmp/t.raw','rb').read(); n=len(d)//2
nz=sum(1 for i in range(0,len(d)-1,2) if d[i]!=0 or d[i+1]!=0)
print(f'{nz}/{n} samples non-zero ({100*nz/n:.1f}%)' if n else 'no data')
"
# > 0% = אודיו זורם; 0% = בעיה ב-MPV routing
```

---

## דברים שלא לעשות

- **לא להחזיר `audio-stream-silence`** — ראה הסבר למעלה
- **לא להוריד Snapcast buffer מ-500ms** — WiFi clients גמגום
- **לא להשתמש ב-`docker compose restart`** אחרי שינוי volumes/env — חובה down+up
- **לא לשנות את `lva-snapcast` ל-A2DP** — JBL חייב להישאר HFP למיק

---

## הרצה ראשונה על מחשב חדש

```bash
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast

# 1. הגדר .env
cp .env.example .env
nano .env   # AUDIO_INPUT_DEVICE, CLIENT_NAME, NETWORK_INTERFACE, PORT

# 2. התקן קבצי מערכת (ערוך USERNAME, SNAPCAST_HOST, BT_DEVICE_MAC בראש הקובץ)
sudo system/install.sh

# 3. Pair BT (אם עוד לא עשית):
#    bluetoothctl scan bredr → pair XX:XX:XX:XX:XX:XX → trust → connect

# 4. אתחל PipeWire (כ-user, לא root)
systemctl --user restart pipewire pipewire-pulse wireplumber

# 5. הרם container
docker compose up -d

# 6. חבר ל-Home Assistant: Settings → Devices → ESPHome → host:port
```

---

## Git

- `origin` = Guy008/linux-voice-assistant-snapcast (הfork שלנו)
- `upstream` = OHF-Voice/linux-voice-assistant (המקורי)
- לעדכון: `git fetch upstream && git merge upstream/main && git push origin main`

---

## תיעוד מלא

`docs/setup-guide-guy008.md` — מדריך התקנה שלם צעד-אחר-צעד כולל תיקון Bluetooth על Arch Linux headless.
