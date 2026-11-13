#!/bin/bash
# Installs the ROV controller on Raspberry Pi OS and makes it start on boot.
# Run on the Pi:   sudo bash install.sh
# (The pre-built image runs this automatically on first boot.)
set -euo pipefail

if [ "$EUID" -ne 0 ]; then echo "Run with sudo:  sudo bash install.sh"; exit 1; fi
RUN_USER="${ROV_USER:-${SUDO_USER:-$(logname 2>/dev/null || echo pi)}}"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/opt/rov

echo "==> Checking packages"
NEED=()
for p in python3-evdev python3-lgpio python3-tk bluez ffmpeg curl; do
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
install -m 755 "$SRC/rov-autopair.sh" "$DEST/rov-autopair.sh"
install -m 755 "$SRC/pair-controller.sh" "$DEST/pair-controller.sh"
install -m 644 "$SRC/README.md" "$DEST/README.md"
install -m 755 "$SRC/rov_gui.py" "$DEST/rov_gui.py"
# full-screen dashboard on the case monitor when the desktop starts
USER_HOME=$(getent passwd "$RUN_USER" | cut -d: -f6)
install -d -o "$RUN_USER" "$USER_HOME/.config" "$USER_HOME/.config/autostart"
cat > "$USER_HOME/.config/autostart/rov-screen.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ROV dashboard
Exec=/usr/bin/python3 $DEST/rov_gui.py
EOF
chown "$RUN_USER" "$USER_HOME/.config/autostart/rov-screen.desktop"
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

echo "==> Creating systemd services 'rov' and 'rov-autopair'"
cat > /etc/systemd/system/rov.service <<EOF
[Unit]
Description=Underwater ROV controller
After=bluetooth.target
Wants=bluetooth.target

[Service]
User=$RUN_USER
SupplementaryGroups=input gpio
WorkingDirectory=$DEST
ExecStart=/usr/bin/python3 $DEST/rov.py --config $DEST/config.toml
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/rov-autopair.service <<EOF
[Unit]
Description=Auto-pair game controllers for the ROV
After=bluetooth.target
Requires=bluetooth.target

[Service]
ExecStart=/bin/bash $DEST/rov-autopair.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# direct Ethernet cable (no router): never give up waiting for DHCP, use link-local addresses
nmcli con mod "Wired connection 1" ipv4.dhcp-timeout 2147483647 ipv4.link-local fallback \
  ipv6.method link-local connection.autoconnect-retries 0 2>/dev/null || true

systemctl daemon-reload
systemctl enable bluetooth rov.service rov-autopair.service

cat <<EOF

Installed. 'rov' starts on every boot.
  Pair a controller: just put it in pairing mode (PS5: CREATE+PS, PS4: SHARE+PS) - it pairs by itself.
  Identify motors:   sudo systemctl stop rov && python3 $DEST/rov.py --test
  Settings:          $DEST/config.toml   then  sudo systemctl restart rov
  Logs:              journalctl -u rov -f
EOF
