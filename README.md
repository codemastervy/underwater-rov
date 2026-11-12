# Underwater ROV controller (Raspberry Pi 4 + 4× BTS7960 + PS5/PS4 controller)

The Pi in the case reads a Bluetooth (or USB) game controller and drives the 4 thrusters
through 4 BTS7960 (IBT-2) boards. Everything runs above water; only the motor wires go down the tether.

## Files
| File | What it is |
|---|---|
| `rov.py` | the program |
| `config.toml` | pins, motor layout, speeds, safety settings |
| `install.sh` | installs everything on the Pi and starts it on boot |
| `pair-controller.sh` | pairs a PS5/PS4/other Bluetooth controller |

## Wiring

Pin numbers: **GPIO** = what goes in `config.toml`, **Pin** = physical pin on the Pi header (pin 1 is the corner nearest the SD card end, marked with a square pad).

| BTS7960 board | RPWM | LPWM | R_EN + L_EN | VCC | GND |
|---|---|---|---|---|---|
| Motor 1 (left)  | GPIO12 / Pin 32 | GPIO13 / Pin 33 | GPIO17 / Pin 11 | 3.3V Pin 1 or 17 | any GND |
| Motor 2 (right) | GPIO19 / Pin 35 | GPIO26 / Pin 37 | GPIO17 / Pin 11 | 3.3V | GND |
| Motor 3 (vert front) | GPIO16 / Pin 36 | GPIO20 / Pin 38 | GPIO17 / Pin 11 | 3.3V | GND |
| Motor 4 (vert rear)  | GPIO24 / Pin 18 | GPIO25 / Pin 22 | GPIO17 / Pin 11 | 3.3V | GND |

Pi GND pins: 6, 9, 14, 20, 25, 30, 34, 39.

- **All 8 enable pins (R_EN and L_EN on every board) go to GPIO17.** The program only turns this on while armed,
  so the motors are physically disabled at boot, after a crash, or if the controller drops out.
  Add a **10 kΩ resistor from GPIO17 to GND** so it stays off while the Pi is booting.
- **VCC on the boards → Pi 3.3 V** (not 5 V). This makes the board's logic match the Pi's 3.3 V signals.
  The boards take only a few mA.
- **Leave R_IS / L_IS unconnected.** They can put out more than 3.3 V and damage the Pi.
- **B+ / B−** → 12 V battery (through a **fuse** and your main switch). **M+ / M−** → motor wires in the tether.
- The Pi needs its own 5 V 3 A supply (a 12 V→5 V USB-C buck converter is fine). The BTS7960's logic ground
  and the battery ground are joined on the board, so the Pi and battery share ground through the GND wire. That is required.
- Optional: wire one of the red panel toggles between **GPIO22 (Pin 15)** and GND, and set `arm_switch_pin = 22`.
  Then motors can only run while that switch is up. That gives you a hardware kill switch.
- Optional: an LED (with a 330 Ω resistor) on GPIO27 (Pin 13), `status_led_pin = 27`. It lights when armed.

## Setup on the Pi

1. Flash `2026-10-06-raspios-trixie-arm64.img` with **Raspberry Pi Imager** → *Use custom* → pick the .img.
   In the settings (gear) set a username/password, Wi-Fi, and enable SSH.
2. Copy this folder to the Pi (USB stick, or `scp -r underwater-rov <user>@<pi>.local:~`).
3. On the Pi:
   ```bash
   cd ~/underwater-rov
   sudo bash install.sh
   sudo reboot
   bash ~/underwater-rov/pair-controller.sh
   ```
4. **Identify the motors** (props in the water or clear of everything):
   ```bash
   sudo systemctl stop rov
   python3 /opt/rov/rov.py --test
   ```
   Each motor spins forward then reverse at 30 %. Then edit `/opt/rov/config.toml`:
   wrong direction → `invert = true`; wrong motor → swap the `rpwm`/`lpwm` pins between entries.
5. `sudo systemctl start rov`. From now on it starts by itself on every boot.

To watch it live on the case's monitor: `sudo systemctl stop rov && python3 /opt/rov/rov.py`.

## Controls

| Button | Action |
|---|---|
| **OPTIONS** | **Arm** (sticks must be centred) |
| **CIRCLE**, **CREATE/SHARE**, or **PS** | **Disarm / stop all motors** |
| Left stick | forward/back + turn |
| Right stick up/down | ascend / descend |
| Right stick left/right | sideways (only if a motor has a `sway` value) |
| R2 / L2 | ascend / descend (finer, analog) |
| R1 / L1 | speed level up / down (25 / 50 / 75 / 100 %) |

It starts at 50 % speed. The motors ramp up smoothly rather than jumping to full power.

### Thruster layout
The default mix assumes 2 horizontal thrusters (left/right) and 2 vertical ones. If yours differ, change the
numbers in each `[[motor]]` block. Motor power = `surge×forward + yaw×turn + heave×up + sway×sideways`.

## Safety behaviour
- Starts **disarmed**. The enable line stays low and nothing spins until you press OPTIONS.
- It disarms on: controller disconnect, Bluetooth link going quiet for 0.5 s (uses the PS4/PS5 motion
  sensor stream as a heartbeat), panel switch off, program stop/crash, or pressing CIRCLE.
- After any disconnect you must press OPTIONS again. A controller that reconnects will never start the motors by itself.

## Backup controller options
The program uses **any** gamepad Linux recognises, picked in the order of `preferred` in `config.toml`.
If the main one drops, it switches to whichever other controller is connected (still disarmed until you arm it).

| Controller | Works? | Notes |
|---|---|---|
| PS5 DualSense / DualSense Edge | ✅ best | built-in driver, has heartbeat |
| PS4 DualShock 4 | ✅ best backup | same buttons and same driver behaviour, has heartbeat |
| **Any of the above on a USB cable** | ✅ most reliable | no Bluetooth to drop. Keep a 2–3 m USB-C/micro-USB cable in the case |
| Xbox One / Series | ✅ USB, ⚠️ Bluetooth | over Bluetooth install `xpadneo` for proper support; no heartbeat (relies on disconnect detection) |
| 8BitDo (in XInput/Switch mode), Switch Pro | ✅ | no heartbeat |
| Cheap PS4 clones | ⚠️ | often need `ClassicBondedOnly=false` in `/etc/bluetooth/input.conf` |

## Troubleshooting
- `python3 /opt/rov/rov.py --list` shows every input device the Pi sees.
- `python3 /opt/rov/rov.py --dry-run` tests the controller without touching the GPIO pins.
- `journalctl -u rov -f` shows the service log.
- Motor hums but doesn't turn at low stick: set `min_duty = 15` in config.

