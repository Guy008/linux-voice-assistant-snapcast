# Linux Voice Assistant — Snapcast Edition

**[עברית](#עברית) | [English](#english)**

---

## עברית

פורק של [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) עם שינוי מרכזי אחד:

> **כל קול העוזר יוצא דרך Snapcast** — כל הרמקולים בבית שומעים בסנכרון,
> במקום שהקול ינוגן ישירות לרמקול מקומי.

### מה שונה מהפרויקט המקורי?

| תכונה | מקורי | הפורק הזה |
|-------|--------|-----------|
| פלט אודיו | רמקול מקומי / BT ישיר | Snapcast ← כל הרמקולים בבית |
| transport | MPV ← מכשיר מקומי | MPV ← PipeWire sink ← pacat ← ffmpeg ← TCP ← Snapcast |
| `audio-buffer` | 0.8s | 0.3s (latency נמוך יותר) |
| `audio-stream-silence` | פועל | **הוסר** (שובר routing ב-PipeWire) |
| `AUDIO_OUTPUT_DEVICE` | `default` | `pipewire/lva-snapcast` |
| יציבות Bluetooth | בסיסית | נעילת HFP, reconnect אוטומטי, מניעת crash-loop |
| שרת headless | חלקי | תיקון WirePlumber seat-monitoring |
| התקנה | ידנית | `sudo system/install.sh` — מגדיר הכל אוטומטית |

### זרימת האודיו

```
מיקרופון Bluetooth (HFP)
        │
        ▼
PipeWire (host)  ──►  linux-voice-assistant (Docker)  ◄──►  Home Assistant
                                │
                                │  AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
                                ▼
                         lva-snapcast  ←  PipeWire virtual null sink
                         (22050Hz mono)
                                │  monitor
                                ▼
                     pacat ──► ffmpeg ──► TCP:2509
                                              │
                                       Snapcast Server
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                   ▼                   ▼
                    סלון (snapclient)  חדר שינה (snapclient)  מטבח (snapclient)
```

### התקנה

```bash
# 1. שכפל את הפרויקט
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast

# 2. הגדר את קובץ הסביבה
cp .env.example .env
nano .env
# ערוך: AUDIO_INPUT_DEVICE, CLIENT_NAME, NETWORK_INTERFACE, PORT

# 3. ערוך 3 משתנים בראש system/install.sh:
#    USERNAME, SNAPCAST_HOST, BT_DEVICE_MAC
#    ואז הרץ את הסקריפט:
sudo system/install.sh

# 4. אתחל PipeWire (כ-user, לא root!)
systemctl --user restart pipewire pipewire-pulse wireplumber

# 5. הרם את הcontainer
docker compose up -d

# 6. הוסף ל-Home Assistant:
#    Settings → Devices & Services → Add Integration → ESPHome
#    Host: <IP השרת שלך>    Port: 6053
```

> **⚠️ חשוב:** לאחר שינוי ב-`.env` או ב-volume mounts —
> חובה `docker compose down && docker compose up -d`.
> `docker compose restart` **לא** מחיל שינויים אלה.

### מה כלול בפרויקט

| קובץ / תיקייה | תפקיד |
|--------------|-------|
| `system/install.sh` | מגדיר הכל: D-Bus, PipeWire sink, WirePlumber, systemd, snapserver |
| `system/` | כל קבצי הconfig וה-scripts (ראה להלן) |
| `docker-entrypoint.sh` | ממתין ל-Bluetooth mic לפני הפעלה (מונע crash-loop) |
| `linux_voice_assistant/player/libmpv.py` | audio-buffer מופחת, ללא audio-stream-silence |
| `wakewords/` | תיקייה להנחת מודלים מותאמים אישית (`.tflite` + `.json`) |
| `docs/setup-guide-guy008.md` | מדריך מלא צעד-אחר-צעד בעברית (Arch Linux) |

### שירותי systemd (מותקנים אוטומטית)

| שירות | מה הוא עושה |
|-------|------------|
| `lva-snapcast-stream` | pacat → ffmpeg → TCP:2509 → Snapcast |
| `lva-snapcast-watcher` | מאתחל את הstream 3 שניות אחרי restart של הcontainer |
| `lva-audio-watchdog.timer` | כל 2 דקות: בודק שffmpeg מחובר לSnapcast |
| `bt-reconnect-jbl` | כל 15 שניות: מחבר מחדש את BT אם התנתק |

### כללים חשובים (נלמדו בדרך הקשה)

- **אל תחזיר `audio-stream-silence`** — יוצר PipeWire node שלא מנותב ל-lva-snapcast
- **אל תורד Snapcast buffer מתחת ל-1000ms** — חלק מרמקולי ה-WiFi לא עובדים מתחת לשנייה
- **השתמש תמיד ב-`docker compose down && up -d`** אחרי שינוי ב-`.env` או volumes
- **`AUDIO_OUTPUT_DEVICE` חייב להתחיל ב-`pipewire/`** — בלי זה MPV נכשל בשקט

### מילות השכמה מותאמות אישית

הנח קובץ `.tflite` וקובץ `.json` מתאים בתיקיית `wakewords/`:

```json
{
  "type": "openWakeWord",
  "wake_word": "שם מילת ההשכמה",
  "model": "my_wake_word.tflite"
}
```

הגדר `WAKE_MODEL=my_wake_word` ב-`.env`.

### עדכון מהפרויקט המקורי

```bash
git fetch upstream
git merge upstream/main
git push origin main
```

### אבחון מהיר

```bash
# כל השירותים פועלים?
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl

# ffmpeg מחובר לSnapcast?
ss -tnp | grep 2509          # צפוי: ESTAB עם ffmpeg

# הcontainer עלה?
docker compose ps

# אודיו מגיע ל-lva-snapcast? (הרץ ואז דבר אל העוזר)
timeout 5 pacat --device=lva-snapcast.monitor --record --raw \
  --rate=22050 --channels=1 --format=s16le > /tmp/t.raw 2>/dev/null
python3 -c "
d=open('/tmp/t.raw','rb').read(); n=len(d)//2
nz=sum(1 for i in range(0,len(d)-1,2) if d[i]!=0 or d[i+1]!=0)
print(f'{nz}/{n} samples non-zero ({100*nz/n:.1f}%)' if n else 'no data')
"
```

### פתרון בעיות

| בעיה | סיבה | פתרון |
|------|------|--------|
| אין קול בשום רמקול | pacat עם חיבור ישן | `sudo systemctl restart lva-snapcast-stream` |
| קול רק מה-BT, לא משאר הרמקולים | AUDIO_OUTPUT_DEVICE שגוי | בדוק `AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` ב-`.env` |
| הcontainer קורס בלופ | BT mic לא מוכן בהפעלה | אוטומטי — `bt-reconnect-jbl` + wait loop ב-entrypoint |
| מילת השכמה הפסיקה לעבוד | WirePlumber החליף BT מ-HFP ל-A2DP | הרץ `system/install.sh` לנעילת HFP |
| Bluetooth לא מתחבר | אין D-Bus policy | הרץ `system/install.sh` |
| שינוי ב-`.env` לא נכנס לתוקף | שימוש ב-`restart` | `docker compose down && docker compose up -d` |

### מדריך מלא

מדריך התקנה שלם (Arch Linux, pairing בלוטוס, PipeWire, WirePlumber, Snapcast):
→ [docs/setup-guide-guy008.md](docs/setup-guide-guy008.md)

---

## English

Fork of [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) with one core change:

> Instead of playing audio locally or directly to a Bluetooth speaker,
> all assistant audio is routed through **Snapcast** — every speaker in the house plays in sync.

### What's different from upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Audio output | Local device / direct BT | Snapcast → all house speakers |
| Transport | MPV → local device | MPV → PipeWire sink → pacat → ffmpeg → TCP → Snapcast |
| `audio-buffer` | 0.8s | 0.3s (lower latency) |
| `audio-stream-silence` | enabled | **removed** (breaks PipeWire routing) |
| `AUDIO_OUTPUT_DEVICE` | `default` | `pipewire/lva-snapcast` |
| Bluetooth stability | basic | HFP lock, auto-reconnect, crash-loop prevention |
| Headless server | partial | WirePlumber seat-monitoring fix |
| System installer | none | `sudo system/install.sh` — configures everything |

### Audio flow

```
Bluetooth Mic (HFP)
        │
        ▼
PipeWire (host)  ──►  linux-voice-assistant (Docker)  ◄──►  Home Assistant
                                │
                                │  AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
                                ▼
                         lva-snapcast  ←  PipeWire virtual null sink
                         (22050Hz mono)
                                │  monitor
                                ▼
                     pacat ──► ffmpeg ──► TCP:2509
                                              │
                                       Snapcast Server
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                   ▼                   ▼
                   Living room          Bedroom              Kitchen
                   (snapclient)       (snapclient)          (snapclient)
```

### Installation

```bash
# 1. Clone the project
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast

# 2. Configure the environment file
cp .env.example .env
nano .env
# Set: AUDIO_INPUT_DEVICE, CLIENT_NAME, NETWORK_INTERFACE, PORT

# 3. Edit 3 variables at the top of system/install.sh:
#    USERNAME, SNAPCAST_HOST, BT_DEVICE_MAC
#    Then run:
sudo system/install.sh

# 4. Restart PipeWire (as your user, NOT root!)
systemctl --user restart pipewire pipewire-pulse wireplumber

# 5. Start the container
docker compose up -d

# 6. Add to Home Assistant:
#    Settings → Devices & Services → Add Integration → ESPHome
#    Host: <your server IP>    Port: 6053
```

> **⚠️ Important:** After changing `.env` or volume mounts —
> always use `docker compose down && docker compose up -d`.
> `docker compose restart` does **not** apply those changes.

### What's included

| File / Directory | Purpose |
|-----------------|---------|
| `system/install.sh` | Installs everything: D-Bus, PipeWire sink, WirePlumber, systemd, snapserver |
| `system/` | All config files and scripts (see below) |
| `docker-entrypoint.sh` | Waits for Bluetooth mic before starting (prevents crash-loop) |
| `linux_voice_assistant/player/libmpv.py` | Reduced audio-buffer, audio-stream-silence removed |
| `wakewords/` | Place custom wake word models here (`.tflite` + `.json`) |
| `docs/setup-guide-guy008.md` | Full step-by-step guide (Arch Linux, Hebrew) |

### Systemd services (installed automatically)

| Service | Purpose |
|---------|---------|
| `lva-snapcast-stream` | pacat → ffmpeg → TCP:2509 → Snapcast |
| `lva-snapcast-watcher` | Restarts stream 3s after container restart (fixes stale pacat connection) |
| `lva-audio-watchdog.timer` | Every 2 min: checks ffmpeg is connected to Snapcast |
| `bt-reconnect-jbl` | Every 15s: reconnects BT device if disconnected |

### Key rules (learned the hard way)

- **Never re-add `audio-stream-silence`** — creates a PipeWire node that doesn't route to lva-snapcast
- **Never set Snapcast buffer below 1000ms** — some WiFi speakers don't work reliably below 1 second
- **Always use `docker compose down && up -d`** after changing `.env` or volume mounts
- **`AUDIO_OUTPUT_DEVICE` must have `pipewire/` prefix** — without it MPV silently fails

### Custom wake words

Place a `.tflite` model and matching `.json` config in `wakewords/`:

```json
{
  "type": "openWakeWord",
  "wake_word": "Hey Computer",
  "model": "hey_computer.tflite"
}
```

Set `WAKE_MODEL=hey_computer` in `.env`.

### Keeping up with upstream

```bash
git fetch upstream
git merge upstream/main
git push origin main
```

### Quick diagnostics

```bash
# All services running?
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl

# ffmpeg connected to Snapcast?
ss -tnp | grep 2509          # expected: ESTAB with ffmpeg

# Container up?
docker compose ps

# Audio reaching lva-snapcast? (run, then speak to the assistant)
timeout 5 pacat --device=lva-snapcast.monitor --record --raw \
  --rate=22050 --channels=1 --format=s16le > /tmp/t.raw 2>/dev/null
python3 -c "
d=open('/tmp/t.raw','rb').read(); n=len(d)//2
nz=sum(1 for i in range(0,len(d)-1,2) if d[i]!=0 or d[i+1]!=0)
print(f'{nz}/{n} samples non-zero ({100*nz/n:.1f}%)' if n else 'no data')
"
```

### Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| No audio on any speaker | Stale pacat connection | `sudo systemctl restart lva-snapcast-stream` |
| Audio on BT only, not other speakers | Wrong AUDIO_OUTPUT_DEVICE | Check `AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` in `.env` |
| Container crash-loops on start | BT mic not ready at startup | Automatic — `bt-reconnect-jbl` + entrypoint wait loop |
| Wake word stops working after minutes | WirePlumber switched BT from HFP to A2DP | Run `system/install.sh` to lock HFP profile |
| Bluetooth not connecting | No D-Bus policy | Run `system/install.sh` |
| Changes to `.env` not applied | Used `docker compose restart` | Use `docker compose down && docker compose up -d` |

### Full setup guide

Step-by-step guide for Arch Linux (Bluetooth pairing, PipeWire, WirePlumber, Snapcast):
→ [docs/setup-guide-guy008.md](docs/setup-guide-guy008.md)

---

## License

Apache 2.0 — same as upstream. See [LICENSE.md](LICENSE.md).

Fork by [@Guy008](https://github.com/Guy008) •
Based on [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) by the [Open Home Foundation](https://www.openhomefoundation.org/)
