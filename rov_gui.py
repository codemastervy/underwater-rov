#!/usr/bin/env python3
"""ROV dashboard. Full screen at any resolution; works with the mouse alone or the keyboard alone.

It shows what rov.py (the systemd service) is doing. No mouse click can arm the motors: that takes the
controller (OPTIONS), or holding Enter while a keyboard profile is in use. If this window closes, the ROV
keeps running with a controller profile and disarms with a keyboard profile.

  --windowed            in a window instead of full screen (F11 switches)
  --size 1024x614       size of that window
  --fps 60              limit the frame rate (0 = no limit, the default)
  --show-fps            show the frame rate (F12 switches)
  --margins 32,22,32,22 left, top, right, bottom: pixels the monitor hides
  --page camera         page to start on
"""
import argparse
import importlib
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def numbers(text, separator):
    return tuple(int(n) for n in text.split(separator))


def repair():
    """After an update that couldn't install everything: fetch what the dashboard needs. True if it's all there."""
    def missing(name):
        importlib.invalidate_caches()
        return importlib.util.find_spec(name) is None
    if missing("dashboard"):
        import updater
        with tempfile.TemporaryDirectory() as folder:
            updater.copy_program(updater.download(updater.local_version() or updater.latest_version(), folder), HERE)
    for command in (["sudo", "-n", "apt-get", "install", "-y", "python3-pygame"],
                    [sys.executable, "-m", "pip", "install", "--user", "--break-system-packages", "pygame"]):
        if missing("pygame"):
            subprocess.run(command, check=False)
    return not missing("pygame") and not missing("dashboard")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--windowed", action="store_true")
    parser.add_argument("--size", type=lambda s: numbers(s, "x"), default=(1024, 614))
    parser.add_argument("--fps", type=int, default=0)
    parser.add_argument("--show-fps", action="store_true")
    parser.add_argument("--margins", type=lambda s: numbers(s, ","))
    parser.add_argument("--page", default="drive",
                        choices=("drive", "camera", "autopilot", "profiles", "motors", "system"))
    args, _ = parser.parse_known_args()
    if any(importlib.util.find_spec(name) is None for name in ("pygame", "dashboard")):
        print("The dashboard is incomplete, repairing it…", flush=True)
        if not repair():
            sys.exit("Couldn't repair it. Run the setup command from the README once.")
        os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), *sys.argv[1:]])
    from dashboard.app import App
    App(not args.windowed, args.size, args.margins, args.fps, args.show_fps, args.page).run()


if __name__ == "__main__":
    main()
