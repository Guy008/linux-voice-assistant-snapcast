#!/bin/bash
# Auto-reconnect JBL Flip 4 when it disconnects.
# Runs every 15 seconds and attempts bluetoothctl connect if needed.
DEVICE="5C:FB:7C:2F:70:4D"
while true; do
  if ! bluetoothctl info "$DEVICE" 2>/dev/null | grep -q "Connected: yes"; then
    echo "$(date): JBL disconnected, attempting reconnect..."
    bluetoothctl connect "$DEVICE" 2>/dev/null
  fi
  sleep 15
done
