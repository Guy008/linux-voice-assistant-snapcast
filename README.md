# Linux Voice Assistant — Snapcast Edition

**Fork of [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) with multi-room audio routing via Snapcast/TCP.**

> Instead of playing audio locally or directly to a Bluetooth speaker,
> this fork routes all assistant audio through a Snapcast server — so every
> speaker in the house plays the assistant's voice simultaneously, in sync.

---

## What's different from upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Audio output | Local speaker / direct BT | Snapcast → all house speakers |
| Audio transport | MPV → local device | MPV → PipeWire virtual sink → pacat → ffmpeg → TCP → Snapcast |
| MPV `audio-buffer` | 0.8s | 0.3s (lower latency) |
| `audio-stream-silence` | enabled | **removed** (breaks PipeWire routing) |
| `AUDIO_OUTPUT_DEVICE` | `default` | `pipewire/lva-snapcast` |
| Bluetooth stability | none | HFP lock, auto-reconnect service, crash-loop prevention |
| Headless server support | partial | full (WirePlumber seat-monitoring fix) |
| Wake words included | `okay_nabu` | `agent_smitt` + `maraa_maraa_sheal_hakir` |
| One-shot system installer | no | `system/install.sh` |

---

## Audio architecture

```
Bluetooth Mic (JBL Flip 4 / HFP)
        │
        ▼
  PipeWire (host)
        │  AUDIO_INPUT_DEVICE=bluez_input.*
        ▼
linux-voice-assistant  ◄──── Home Assistant (STT / TTS)
  (Docker, network=host)
        │  AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast
        ▼
  lva-snapcast         ← PipeWire virtual null sink (22050Hz mono)
        │  lva-snapcast.monitor
        ▼
  pacat ──► ffmpeg ──► TCP:2509
                           │
                           ▼
                    Snapcast Server
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
       Living room     Bedroom       Kitchen / TV
       (snapclient)  (snapclient)   (snapclient)
```

All speakers play in sync. Latency: ~500–700ms (adjustable via Snapcast buffer).

---

## Quick start

### Prerequisites

- Arch Linux (or similar) with PipeWire + WirePlumber
- Snapcast server running and reachable
- Bluetooth speaker/mic paired (or any PipeWire-compatible mic)
- Docker + Docker Compose
- Home Assistant with ESPHome integration

### 1. Clone

```sh
git clone https://github.com/Guy008/linux-voice-assistant-snapcast
cd linux-voice-assistant-snapcast
```

### 2. Configure `.env`

```sh
cp .env.example .env
nano .env   # set your IPs, BT device MAC, network interface
```

Key variables:
```dotenv
AUDIO_INPUT_DEVICE="bluez_input.XX:XX:XX:XX:XX:XX"   # your BT mic
AUDIO_OUTPUT_DEVICE="pipewire/lva-snapcast"            # do not change
CLIENT_NAME="LivingRoom"                               # shown in HA
NETWORK_INTERFACE="br0"                                # or eth0, eno1
PORT="6053"
```

### 3. Install system components (one time)

Edit the variables at the top of `system/install.sh`:
```sh
USERNAME="your_username"
SNAPCAST_HOST="192.168.1.X"    # your Snapcast server IP
BT_DEVICE_MAC="XX:XX:XX:XX:XX:XX"
```

Then run:
```sh
sudo system/install.sh
```

This installs:
- PipeWire virtual sink (`lva-snapcast`)
- WirePlumber config (headless fix, HFP lock, default sink)
- D-Bus policy for Bluetooth
- 4 systemd services (stream, watcher, watchdog, BT reconnect)

### 4. Restart PipeWire (as your user, not root)

```sh
systemctl --user restart pipewire pipewire-pulse wireplumber
```

### 5. Start the container

```sh
docker compose up -d
docker compose logs -f
```

### 6. Add to Home Assistant

**Settings → Devices & Services → Add Integration → ESPHome**  
Host: `<your server IP>`, Port: `6053`

---

## Keeping up with upstream

```sh
git fetch upstream
git merge upstream/main
# resolve any conflicts in docker-compose.yml / libmpv.py if needed
git push origin main
```

---

## Included wake words

| Model file | Wake phrase | Language |
|-----------|-------------|----------|
| `agent_smitt.tflite` | "Agent Smith" | Hebrew-accented English |
| `maraa_maraa_sheal_hakir.tflite` | "מראה מראה שעל הקיר" (Magic Mirror) | Hebrew |

Place additional custom wake word models in the `wakewords/` directory  
with a matching `.json` config file. See `wakewords/agent_smitt.json` for the format.

---

## Systemd services (installed by `system/install.sh`)

| Service | Purpose |
|---------|---------|
| `lva-snapcast-stream` | Captures `lva-snapcast.monitor` → ffmpeg → TCP → Snapcast |
| `lva-snapcast-watcher` | Restarts the stream 3s after the Docker container (re)starts |
| `lva-audio-watchdog.timer` | Every 2 min: checks ffmpeg TCP connection, restarts if broken |
| `bt-reconnect-jbl` | Every 15s: reconnects BT device if disconnected |

```sh
# Check status of all services
systemctl is-active lva-snapcast-stream lva-snapcast-watcher lva-audio-watchdog.timer bt-reconnect-jbl

# Full diagnostics
ss -tnp | grep 2509       # should show ESTAB with ffmpeg
wpctl status              # lva-snapcast should be visible as a sink
docker ps                 # container should be Up
```

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| No audio on any speaker | pacat has stale PipeWire connection | `sudo systemctl restart lva-snapcast-stream` |
| Audio on BT speaker only, not others | MPV routing to wrong device | Check `AUDIO_OUTPUT_DEVICE=pipewire/lva-snapcast` in `.env` |
| Container crash loop at startup | BT mic not ready | `bt-reconnect-jbl` + entrypoint wait loop handle this automatically |
| Wake word stops working after a few minutes | WirePlumber switched BT from HFP → A2DP, mic disappeared | Check `52-jbl-headset-profile.conf` is installed |
| WirePlumber BT monitor not starting | Headless server: seat=online instead of active | Check `51-disable-seat-monitoring.conf` is installed |
| `docker compose restart` doesn't apply changes | restart reuses the existing container | Use `docker compose down && docker compose up -d` |

Full setup guide (Arch Linux, step by step): [docs/setup-guide-guy008.md](docs/setup-guide-guy008.md)

---

## Original project features

Everything from the upstream project is preserved:

- Home Assistant integration via ESPHome protocol
- Local wake word detection — OpenWakeWord and MicroWakeWord
- Multiple wake words and languages
- Announcements, start/continue conversation, timers
- `amd64` and `aarch64` Docker images (uses upstream GHCR image)
- All original CLI parameters and environment variables

See the [original README](https://github.com/OHF-Voice/linux-voice-assistant) and [docs/install.md](docs/install.md) for full upstream documentation.

---

## Parameter reference

| Parameter | Env variable | Default |
|-----------|-------------|---------|
| `--name` | `CLIENT_NAME` | Auto (`lva-MAC`) |
| `--audio-input-device` | `AUDIO_INPUT_DEVICE` | Autodetected |
| `--audio-output-device` | `AUDIO_OUTPUT_DEVICE` | `pipewire/lva-snapcast` |
| `--wake-word-dir` | `WAKE_WORD_DIR` | `wakewords/custom/openWakeWord` |
| `--wake-model` | `WAKE_MODEL` | `agent_smitt` |
| `--host` | `HOST` | `0.0.0.0` |
| `--network-interface` | `NETWORK_INTERFACE` | Autodetected |
| `--port` | `PORT` | `6053` |
| `--mic-volume` | `MIC_VOLUME` | `1.0` |
| `--mic-auto-gain` | `MIC_AUTO_GAIN` | `0` |
| `--mic-noise-suppression` | `MIC_NOISE_SUPPRESSION` | `0` |
| `--debug` | `ENABLE_DEBUG=1` | off |

Full list: see [docs/install_application.md](docs/install_application.md)

---

## License

Apache 2.0 — same as upstream. See [LICENSE.md](LICENSE.md).

Fork maintained by [@Guy008](https://github.com/Guy008).  
Based on [OHF-Voice/linux-voice-assistant](https://github.com/OHF-Voice/linux-voice-assistant) by the [Open Home Foundation](https://www.openhomefoundation.org/).
