# Linux Voice Assistant — Snapcast Edition

**עברית | [English below](#english)**

---

## עברית

פורק של [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) עם שינוי מרכזי אחד:

**כל קול העוזר יוצא דרך Snapcast** — כל הרמקולים בבית שומעים בסנכרון, במקום שהקול ינוגן ישירות מהמחשב.

### מה שונה מהפרויקט המקורי?

| תכונה | מקורי | הפורק הזה |
|-------|-------|-----------|
| פלט אודיו | רמקול מקומי / BT ישיר | Snapcast ← כל הרמקולים בבית |
| יציבות Bluetooth | בסיסית | נעילת HFP, reconnect אוטומטי, מניעת crash-loop |
| שרת headless | חלקי | תיקון WirePlumber seat-monitoring |
| התקנה | ידנית | `sudo system/install.sh` — מגדיר הכל |

### איך מתקינים?

```bash
# 1. שכפל את הפרויקט
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast

# 2. הגדר את קובץ הסביבה
cp .env.example .env
nano .env    # שנה: AUDIO_INPUT_DEVICE, CLIENT_NAME, NETWORK_INTERFACE, PORT

# 3. ערוך 3 שורות בראש system/install.sh (USERNAME, SNAPCAST_HOST, BT_DEVICE_MAC)
#    ואז הרץ:
sudo system/install.sh

# 4. אתחל PipeWire (כ-user, לא root!)
systemctl --user restart pipewire pipewire-pulse wireplumber

# 5. הרם את הcontainer
docker compose up -d

# 6. הוסף ל-Home Assistant:
#    Settings → Devices & Services → Add Integration → ESPHome
#    Host: <IP השרת שלך>  Port: 6053
```

### מה כלול?

- `system/install.sh` — מתקין הכל בלחיצה אחת (D-Bus, PipeWire sink, WirePlumber, systemd services, snapserver)
- `docker-entrypoint.sh` — ממתין ל-Bluetooth mic לפני שמפעיל (מונע crash-loop)
- `linux_voice_assistant/player/libmpv.py` — latency מופחת, ניתוב נכון ל-PipeWire
- `docs/setup-guide-guy008.md` — מדריך מלא צעד-אחר-צעד (Arch Linux, עברית)
- `wakewords/` — מקום להניח מודלים מותאמים אישית (`.tflite` + `.json`)

### אבחון מהיר

```bash
# כל השירותים פועלים?
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl

# ffmpeg מחובר לSnapcast?
ss -tnp | grep 2509   # צפוי: ESTAB עם ffmpeg

# האם הקונטיינר עלה?
docker compose ps
```

---

## English

Fork of [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) with one core change:

> Instead of playing audio locally or directly to a Bluetooth speaker,  
> all assistant audio is routed through **Snapcast** — every speaker in the house plays in sync.

### What's different from upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Audio output | Local device / direct BT | Snapcast → all house speakers |
| Audio transport | MPV → local | MPV → PipeWire virtual sink → pacat → ffmpeg → TCP → Snapcast |
| MPV `audio-buffer` | 0.8s | 0.3s |
| `audio-stream-silence` | enabled | **removed** (breaks PipeWire routing) |
| `AUDIO_OUTPUT_DEVICE` | `default` | `pipewire/lva-snapcast` |
| Bluetooth stability | basic | HFP lock, auto-reconnect, crash-loop prevention |
| Headless server | partial | WirePlumber seat-monitoring fix included |
| System installer | none | `sudo system/install.sh` |

### Audio flow

```
Bluetooth Mic (HFP)
      │
      ▼
PipeWire (host)  ──►  linux-voice-assistant (Docker)  ◄──►  Home Assistant
                              │
                              │  AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
                              ▼
                       lva-snapcast        ← PipeWire virtual null sink
                       (22050Hz mono)
                              │  monitor
                              ▼
                   pacat ──► ffmpeg ──► TCP:2509
                                           │
                                    Snapcast Server
                                           │
                          ┌────────────────┼────────────────┐
                          ▼                ▼                ▼
                    Living room        Bedroom          Kitchen
                    (snapclient)     (snapclient)     (snapclient)
```

### Quick start

```bash
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast

cp .env.example .env
nano .env   # set AUDIO_INPUT_DEVICE, CLIENT_NAME, NETWORK_INTERFACE

# Edit USERNAME, SNAPCAST_HOST, BT_DEVICE_MAC at the top of install.sh, then:
sudo system/install.sh

systemctl --user restart pipewire pipewire-pulse wireplumber
docker compose up -d
```

Add to Home Assistant: **Settings → Devices & Services → ESPHome** → host + port 6053.

### Systemd services (installed automatically)

| Service | Purpose |
|---------|---------|
| `lva-snapcast-stream` | pacat → ffmpeg → TCP → Snapcast |
| `lva-snapcast-watcher` | Restarts stream 3s after container restart (fixes stale pacat connection) |
| `lva-audio-watchdog.timer` | Every 2 min: checks ffmpeg TCP connection |
| `bt-reconnect-jbl` | Every 15s: reconnects BT device if disconnected |

### Key rules (lessons learned the hard way)

- **Never re-add `audio-stream-silence`** — it creates a PipeWire node that doesn't route to lva-snapcast
- **Never set Snapcast buffer below 500ms** — WiFi clients will stutter
- **Always use `docker compose down && up -d`** after changing `.env` or volume mounts — `restart` doesn't apply them
- **`AUDIO_OUTPUT_DEVICE` must have `pipewire/` prefix** — without it MPV silently fails

### Keeping up with upstream

```bash
git fetch upstream
git merge upstream/main
git push origin main
```

### Custom wake words

Place `.tflite` model and matching `.json` config in `wakewords/`:

```json
{
  "type": "openWakeWord",
  "wake_word": "Hey Computer",
  "model": "hey_computer.tflite"
}
```

Set `WAKE_MODEL=hey_computer` in `.env`.

### Full setup guide

Step-by-step guide for Arch Linux (Bluetooth pairing, PipeWire, WirePlumber, Snapcast):  
→ [docs/setup-guide-guy008.md](docs/setup-guide-guy008.md)

### Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| No audio on any speaker | Stale pacat connection | `sudo systemctl restart lva-snapcast-stream` |
| Audio on BT only, not others | Wrong AUDIO_OUTPUT_DEVICE | Check `AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` in `.env` |
| Container crash-loops | BT mic not ready at startup | `bt-reconnect-jbl` + entrypoint wait loop handle this automatically |
| Wake word stops after minutes | WirePlumber switched BT HFP→A2DP | Run `system/install.sh` to lock HFP profile |
| Bluetooth not connecting | No D-Bus policy | Run `system/install.sh` |
| Changes to `.env` not applied | Used `docker compose restart` | Use `docker compose down && docker compose up -d` |

---

## License

Apache 2.0 — same as upstream. See [LICENSE.md](LICENSE.md).

Fork by [@Guy008](https://github.com/Guy008) •
Based on [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) by the [Open Home Foundation](https://www.openhomefoundation.org/)
