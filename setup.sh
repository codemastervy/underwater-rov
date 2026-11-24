#!/bin/bash
# ROV (Raspberry Pi) - one command to INSTALL on a new Pi, or UPDATE an existing one.
# Needs only an internet connection (Wi-Fi or Ethernet). Run it in a terminal on the Pi (or over SSH):
#
#   curl -fsSL https://raw.githubusercontent.com/codemastervy/underwater-rov/main/setup.sh | bash
#
# - Downloads the latest version from GitHub into ~/underwater-rov (no git needed).
# - Installs everything it needs (Python libraries, Bluetooth, ffmpeg) and the ROV app (no services).
# - Updating keeps your settings: motor flips (config.toml), drive profiles, camera, autopilot, arm tune.
# - After this, the app updates itself: UPDATE NOW on the SYSTEM page when it says UPDATE READY.
# - New Pi only: sets the screen to 800x480 for the case monitor (skip with ROV_SCREEN=none).
set -euo pipefail

REPO="codemastervy/underwater-rov"
BRANCH="${ROV_BRANCH:-main}"
DIR="$HOME/underwater-rov"
SCREEN="${ROV_SCREEN:-800x480}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (not with sudo). It asks for your password when it needs it."
  exit 1
fi

if [ -d /opt/rov ]; then MODE=update; else MODE=install; fi
echo "==> ROV setup: $MODE"

echo "==> Downloading the latest version from GitHub"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SHA="$(curl -fsSL -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/$BRANCH" || true)"
if [ ${#SHA} -ne 40 ]; then SHA="$BRANCH"; fi
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$SHA" | tar -xz -C "$TMP"
SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ "$SHA" != "$BRANCH" ]; then echo "$SHA" > "$SRC/VERSION"; fi   # lets the dashboard spot newer versions
mkdir -p "$DIR"
cp -a "$SRC/." "$DIR/"
chmod +x "$DIR"/*.sh

# close the app (the motors stop) before its files are replaced
APP="^[^ ]*python[0-9.]* ([^ ]*/)?rov(_gui)?\.py( |$)"
pkill -TERM -f "$APP" 2>/dev/null || true
for _ in $(seq 20); do pgrep -f "$APP" >/dev/null || break; sleep 0.3; done

echo "==> Installing (asks for your password)"
sudo ROV_USER="$USER" bash "$DIR/install.sh"

# Screen resolution for the 800x480 case monitor (new installs only; HDMI port 0 or 1)
if [ "$MODE" = install ] && [ "$SCREEN" != none ]; then
  echo "==> Setting the screen to $SCREEN"
  mkdir -p "$HOME/.config/kanshi"
  if [ -f "$HOME/.config/kanshi/config" ]; then
    cp "$HOME/.config/kanshi/config" "$HOME/.config/kanshi/config.before-rov"
  fi
  cat > "$HOME/.config/kanshi/config" <<EOF
profile {
	output HDMI-A-1 enable scale 1.000000 mode --custom ${SCREEN}@60Hz position 0,0 transform normal
}
profile {
	output HDMI-A-2 enable scale 1.000000 mode --custom ${SCREEN}@60Hz position 0,0 transform normal
}
EOF
  for f in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    if [ -f "$f" ] && ! grep -q "video=HDMI-A-1" "$f"; then
      sudo sed -i "1 s/\$/ video=HDMI-A-1:${SCREEN}@60 video=HDMI-A-2:${SCREEN}@60/" "$f"
      break
    fi
  done
fi

if [ "$MODE" = update ]; then
  echo "==> Starting the new version"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" DISPLAY="${DISPLAY:-:0}"
  (cd /opt/rov && setsid python3 /opt/rov/rov_gui.py >/dev/null 2>&1 < /dev/null &) || true
  echo
  echo "Updated to the latest version. The ROV app has restarted."
else
  echo
  echo "Installed. Reboot to finish (screen size, permissions, autostart):  sudo reboot"
  echo "Then pair the controller: PS5 hold CREATE+PS (PS4: SHARE+PS) - it pairs by itself."
fi
