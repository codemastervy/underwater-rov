#!/usr/bin/env python3
"""The ROV app. This one program is everything: it opens the screen, runs the motor program (rov.py) and pairs
controllers. Closing it stops the motors. It opens by itself when the desktop starts, or from the menu (ROV).

No mouse click can arm the motors: that takes the controller (OPTIONS), or holding Enter while a keyboard profile
is in use. It works at any size, with the mouse alone or the keyboard alone.

  --windowed            in a window instead of full screen (F11 switches)
  --size 1024x614       size of that window
  --fps 60              limit the frame rate (0 = no limit, the default)
  --show-fps            show the frame rate (F12 switches)
  --margins 32,22,32,22 left, top, right, bottom: pixels the monitor hides (instead of SYSTEM > Edge margin)
  --page camera         page to start on
  --dry-run             try it without a Pi: nothing is sent to motors
"""
import argparse
import importlib
import importlib.util
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
OLD_STATUS = "/dev/shm/rov-status.json"       # written all the time by motor programs from before the one-app version
CLOSING = 5.0                                 # seconds a program that is just closing gets
RAN_WELL = 10.0                               # seconds: an app that ran this long is opened again after a crash


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


def remove_old_services():
    """Versions before the one-app version ran as systemd services. They hold the motor pins: switch them off."""
    if any(os.path.exists(f"/etc/systemd/system/{name}.service") for name in ("rov", "rov-autopair")):
        try:
            subprocess.run(["sudo", "-n", "systemctl", "disable", "--now", "rov", "rov-autopair"],
                           stdin=subprocess.DEVNULL, timeout=30, check=False)
        except (OSError, subprocess.SubprocessError):
            pass


def old_version_runs():
    """Does a motor program from before the one-app version run? It would fight this one over the motors."""
    try:
        with open(OLD_STATUS) as f:
            return abs(time.time() - json.load(f)["ts"]) < 2.0
    except (OSError, ValueError, KeyError, TypeError):
        return False


def wait_for(get):
    """get(), tried for a few seconds until it gives something."""
    end = time.monotonic() + CLOSING
    while not (result := get()) and time.monotonic() < end:
        time.sleep(0.2)
    return result


def write_crash():
    from dashboard.program import open_log
    traceback.print_exc()
    with open_log() as log:
        log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} the app crashed\n{traceback.format_exc()}".encode())


def start_again():
    os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), *sys.argv[1:]])


def restarter():
    """A function that opens the app again. A thread that is there before the window lowers its priority does it:
    the new app, and so the motor program, must have the normal one."""
    go = threading.Event()

    def wait():
        go.wait()
        start_again()

    def open_again():
        go.set()
        time.sleep(10)                        # start_again() ends this program long before that

    threading.Thread(target=wait, daemon=True).start()
    return open_again


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument("--windowed", action="store_true")
    parser.add_argument("--size", type=lambda s: numbers(s, "x"), default=None)
    parser.add_argument("--fps", type=int, default=0)
    parser.add_argument("--show-fps", action="store_true")
    parser.add_argument("--margins", type=lambda s: numbers(s, ","))
    parser.add_argument("--page", default="drive",
                        choices=("drive", "camera", "autopilot", "profiles", "motors", "system"))
    parser.add_argument("--dry-run", action="store_true")
    args, _ = parser.parse_known_args()
    if any(importlib.util.find_spec(name) is None for name in ("pygame", "dashboard")):
        print("The dashboard is incomplete, repairing it…", flush=True)
        if not repair():
            sys.exit("Couldn't repair it. Run the setup command from the README once.")
        start_again()

    blocked, folder = "", None
    if args.dry_run:                          # its own files, so it can't reach the motors of an app that is open
        folder = os.environ["ROV_RUN_DIR"] = tempfile.mkdtemp(prefix="rov-dry-")
    import rov
    held = args.dry_run or wait_for(lambda: rov.lock("app"))           # kept until the app ends
    if not held:
        sys.exit("The ROV app is already open.")
    if not args.dry_run:
        remove_old_services()
    if not args.dry_run and old_version_runs() and not wait_for(lambda: not old_version_runs()):
        blocked = "The old 'rov' service still has the motors: run the setup command from the README once"
    from dashboard.app import App
    from dashboard.program import MotorProgram
    from dashboard.pairing import AutoPair
    app = App(not args.windowed, args.size, args.margins, args.fps, args.show_fps, args.page,
              MotorProgram(args.dry_run, blocked), [] if args.dry_run else [AutoPair()])
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda *_: app.quit())
    open_again = restarter()
    started, crashed = time.monotonic(), False
    try:
        app.run()                             # stops the motors whatever happens
    except Exception:
        crashed = True
        write_crash()
    finally:
        if folder:
            shutil.rmtree(folder, ignore_errors=True)
    if app.restart or crashed and time.monotonic() - started > RAN_WELL:
        open_again()
    sys.exit(int(crashed))


if __name__ == "__main__":
    main()
