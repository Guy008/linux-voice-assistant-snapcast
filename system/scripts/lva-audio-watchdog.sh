#!/bin/bash
# Watchdog: verify ffmpeg is connected to Snapcast.
# If the TCP connection is gone, restart lva-snapcast-stream.

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
