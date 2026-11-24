"""Pairs controllers: while none is connected, it looks for one in pairing mode and pairs and trusts it, so that
never takes a keyboard. PS5: hold CREATE + PS until the light flashes fast. PS4: hold SHARE + PS.
Once paired, a controller reconnects by itself when PS is pressed."""
import re
import subprocess
import threading
import time

NAMES = re.compile(r"DualSense|Wireless Controller|Xbox|8BitDo|Pro Controller")
DEVICE = re.compile(r"^Device (\S+) (.+)$", re.M)
CONNECTED, AGAIN = 5.0, 2.0          # seconds to wait


def run(*command, seconds=20):
    """What a command prints ("" if it fails)."""
    try:
        return subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              text=True, errors="replace", timeout=seconds).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def bluetooth(*command, timeout=0):
    return run("bluetoothctl", *(["--timeout", str(timeout)] if timeout else []), *command)


def controllers(listing):
    """[address] of the controllers in what bluetoothctl lists."""
    return [address for address, name in DEVICE.findall(listing) if NAMES.search(name)]


class AutoPair(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)

    def run(self):
        # Raspberry Pi OS can start with Bluetooth blocked
        run("rfkill", "unblock", "bluetooth")
        run("sudo", "-n", "rfkill", "unblock", "bluetooth")
        while True:
            time.sleep(CONNECTED if self.round() else AGAIN)

    @staticmethod
    def round():
        """Look for a controller once. True if one is connected already."""
        if controllers(bluetooth("devices", "Connected")):
            return True
        bluetooth("power", "on")
        bluetooth("scan", "on", timeout=8)
        for address in controllers(bluetooth("devices")):
            if "Paired: yes" not in bluetooth("info", address):
                print(f"Pairing new controller {address}", flush=True)
                bluetooth("pair", address, timeout=15)
            bluetooth("trust", address)
            bluetooth("connect", address, timeout=5)
        return False
