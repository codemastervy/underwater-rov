#!/bin/bash
# Pair a PS5 / PS4 (or other) Bluetooth controller with the Pi. Run on the Pi:  bash pair-controller.sh
# After pairing once, the controller reconnects automatically when you press its PS button.
set -u

cat <<'EOF'
Put the controller in pairing mode NOW:
  PS5 DualSense : hold CREATE (left of touchpad) + PS button until the light bar double-flashes fast
  PS4 DualShock : hold SHARE + PS button until the light bar flashes fast
  Xbox          : hold the small PAIR button on top until the logo flashes fast
  8BitDo        : see its manual (usually START + X or START + B)
Scanning for 20 seconds...
EOF

bluetoothctl power on >/dev/null
bluetoothctl --timeout 20 scan on >/dev/null

PATTERN='DualSense|Wireless Controller|Xbox|8BitDo|Pro Controller|Gamepad'
mapfile -t FOUND < <(bluetoothctl devices | grep -E "$PATTERN")

if [ ${#FOUND[@]} -eq 0 ]; then
  echo "No controller found. Make sure the light is flashing fast and try again."
  exit 1
fi

echo "Found:"
for i in "${!FOUND[@]}"; do echo "  [$i] ${FOUND[$i]#Device }"; done
CHOICE=0
if [ ${#FOUND[@]} -gt 1 ]; then read -rp "Which one? [0] " CHOICE; CHOICE=${CHOICE:-0}; fi
MAC=$(echo "${FOUND[$CHOICE]}" | awk '{print $2}')

echo "Pairing $MAC ..."
bluetoothctl pair "$MAC"
bluetoothctl trust "$MAC"
bluetoothctl connect "$MAC"

if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
  echo "Connected! It will now reconnect on its own when you press the PS button."
else
  cat <<EOF
Not connected yet. Try it by hand:
  bluetoothctl
    remove $MAC
    scan on        (put controller in pairing mode, wait for it to show)
    pair $MAC
    trust $MAC
    connect $MAC
If a PS4 clone controller won't stay connected, set  ClassicBondedOnly=false  in
/etc/bluetooth/input.conf and run:  sudo systemctl restart bluetooth
EOF
fi
