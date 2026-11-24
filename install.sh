#!/bin/bash
# Installs the ROV app on Raspberry Pi OS and makes it open when the desktop starts.
# Run on the Pi:   sudo bash install.sh
# (The pre-built image runs this automatically on first boot.)
set -euo pipefail

if [ "$EUID" -ne 0 ]; then echo "Run with sudo:  sudo bash install.sh"; exit 1; fi
RUN_USER="${ROV_USER:-${SUDO_USER:-$(logname 2>/dev/null || echo pi)}}"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/rov

echo "==> Checking packages"
NEED=()
for p in python3-evdev python3-lgpio python3-pygame python3-numpy fonts-dejavu-core bluez ffmpeg curl; do
  dpkg -s "$p" >/dev/null 2>&1 || NEED+=("$p")
done
if [ ${#NEED[@]} -gt 0 ]; then
  # use bundled .deb files first (works with no internet)
  ls "$SRC"/*.deb >/dev/null 2>&1 && dpkg -i "$SRC"/*.deb || true
  STILL=()
  for p in "${NEED[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || STILL+=("$p"); done
  if [ ${#STILL[@]} -gt 0 ]; then apt-get update && apt-get install -y "${STILL[@]}"; fi
fi

echo "==> Giving $RUN_USER access to controllers and GPIO"
usermod -aG input,gpio,bluetooth "$RUN_USER"

echo "==> Copying program to $DEST"
install -d "$DEST"
install -m 755 "$SRC/rov.py" "$DEST/rov.py"
rm -f "$DEST/rov-autopair.sh"                  # the app pairs controllers itself now
install -m 755 "$SRC/pair-controller.sh" "$DEST/pair-controller.sh"
install -m 644 "$SRC/README.md" "$DEST/README.md"
install -m 755 "$SRC/rov_gui.py" "$DEST/rov_gui.py"
rm -rf "${DEST:?}/dashboard"
cp -r "$SRC/dashboard" "$DEST/dashboard"
install -m 644 "$SRC/vision.py" "$DEST/vision.py"
install -m 644 "$SRC/updater.py" "$DEST/updater.py"
# which GitHub version this is (written by setup.sh; the dashboard's auto-update writes it itself)
if [ -f "$SRC/VERSION" ]; then install -m 644 "$SRC/VERSION" "$DEST/VERSION"; fi
# one app: full screen on the case monitor when the desktop starts, and in the menu
USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
install -d -o "$RUN_USER" "$USER_HOME/.config" "$USER_HOME/.config/autostart"
cat > /usr/share/applications/rov.desktop <<EOF
[Desktop Entry]
Type=Application
Name=ROV
Comment=Drive the ROV
Exec=/usr/bin/python3 $DEST/rov_gui.py
Icon=input-gaming
Terminal=false
StartupWMClass=rov-dashboard
Categories=Utility;
EOF
install -m 644 -o "$RUN_USER" /usr/share/applications/rov.desktop "$USER_HOME/.config/autostart/rov-screen.desktop"
if [ -f "$DEST/config.toml" ]; then
  echo "    keeping your existing $DEST/config.toml (new default saved as config.toml.new)"
  install -m 644 "$SRC/config.toml" "$DEST/config.toml.new"
else
  install -m 644 "$SRC/config.toml" "$DEST/config.toml"
fi
for f in profiles.json camera.json; do
  if [ -f "$SRC/$f" ] && [ ! -f "$DEST/$f" ]; then install -m 644 "$SRC/$f" "$DEST/$f"; fi
done
chown -R "$RUN_USER" "$DEST"

# Versions before the one-app version ran as systemd services: remove them (they would hold the motor pins)
for name in rov rov-autopair; do
  if [ -f "/etc/systemd/system/$name.service" ]; then
    echo "==> Removing the old '$name' service"
    systemctl disable --now "$name.service" || true
    rm -f "/etc/systemd/system/$name.service"
    systemctl daemon-reload
  fi
done

# direct Ethernet cable (no router): never give up waiting for DHCP, use link-local addresses
nmcli con mod "Wired connection 1" ipv4.dhcp-timeout 2147483647 ipv4.link-local fallback \
  ipv6.method link-local connection.autoconnect-retries 0 2>/dev/null || true

if [ -n "${ROV_FROM_UPDATE:-}" ]; then exit 0; fi   # auto-update from the dashboard
cat <<EOF

Installed. The ROV app opens by itself when the desktop starts (or from the menu: ROV).
  Pair a controller: just put it in pairing mode (PS5: CREATE+PS, PS4: SHARE+PS) - it pairs by itself.
  Identify motors:   close the app, then  python3 $DEST/rov.py --test
  Settings:          $DEST/config.toml   then close and open the app
  Log:               $DEST/rov.log
EOF
