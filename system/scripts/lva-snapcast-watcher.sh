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
