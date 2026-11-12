#!/bin/bash
# Background helper: while NO controller is connected, look for one in pairing mode
# and pair + trust it automatically. So you never need a keyboard to pair:
#   PS5: hold CREATE + PS until the light flashes fast.   PS4: hold SHARE + PS.
# Once paired, the controller reconnects on its own when you press PS.
PATTERN='DualSense|Wireless Controller|Xbox|8BitDo|Pro Controller'

# Pi OS can start with Bluetooth soft-blocked (rfkill); unblock it (service runs as root)
for d in /sys/class/rfkill/rfkill*; do
  [ "$(cat "$d/type" 2>/dev/null)" = bluetooth ] && echo 0 > "$d/soft" 2>/dev/null
done
sleep 1

while true; do
  if bluetoothctl devices Connected 2>/dev/null | grep -qE "$PATTERN"; then
    sleep 5
    continue
  fi
  bluetoothctl power on >/dev/null 2>&1
  bluetoothctl --timeout 8 scan on >/dev/null 2>&1
  bluetoothctl devices 2>/dev/null | grep -E "$PATTERN" | while read -r _ mac name; do
    if ! bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes"; then
      echo "Pairing new controller: $name ($mac)"
      bluetoothctl --timeout 15 pair "$mac"
    fi
    bluetoothctl trust "$mac" >/dev/null 2>&1
    bluetoothctl --timeout 5 connect "$mac" >/dev/null 2>&1
  done
  sleep 2
done
