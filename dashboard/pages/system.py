"""SYSTEM: arm sound, updates, the screen, and power."""
import subprocess

from ..dialogs import ConfirmDialog, HelpDialog, TextDialog
from ..layout import columns, rows
from ..theme import ACCENT, AMBER, BODY, GAP, GREEN, LABEL, MUTED, RED, SMALL
from . import Page

UPDATE_COLORS = {"ready": ACCENT, "failed": RED, "offline": AMBER, "current": GREEN, "done": GREEN}
TUNE_LENGTH = 2000


class SystemPage(Page):
    name, title = "system", "SYSTEM"

    def draw(self, area):
        ui = self.ui
        if ui.portrait:
            sound, update, screen, power = rows(area, 1.5, 1, 1, 1, gap=ui.px(GAP))
        else:
            left, right = columns(area, 1.1, 1, gap=ui.px(GAP))
            sound, screen = rows(left, 1.9, 1, gap=ui.px(GAP))
            update, power = rows(right, 1, 1.15, gap=ui.px(GAP))
        self._draw_sound(ui.card(sound, "ARM SOUND"))
        self._draw_update(ui.card(update, "SOFTWARE UPDATE"))
        self._draw_screen(ui.card(screen, "SCREEN"))
        self._draw_power(ui.card(power, "POWER"))

    def _labelled(self, line, label):
        ui = self.ui
        text, control = columns(line, 1, 1.3, gap=ui.px(GAP))
        ui.text(label, text, LABEL)
        return control

    def _draw_sound(self, area):
        ui, status, online = self.ui, self.status, self.status.online
        switch, volume, tune, buttons = rows(area, 1, 1, 0.8, 1, gap=ui.px(7))
        if ui.toggle(self._labelled(switch, "Tune when armed"), status.arm_sound, "sound", online):
            self.link.send(f"sound:{int(not status.arm_sound)}")
        new = ui.number(self._labelled(volume, "Volume"), status.sound_volume, 1, 15, 1, lambda v: f"{v:.0f}", "volume",
                        online)
        if new is not None:
            self.link.set("volume", int(new))
        ui.text(f"{status.tune_name} ({status.tune_secs:.0f} s{', yours' if status.tune_custom else ''}) · "
                "any control stops it", tune, SMALL, MUTED)
        change, default, test = columns(buttons, 1.1, 1, 1, gap=ui.px(6))
        if ui.button(change, "SET TUNE", size=BODY, enabled=online):
            self.app.open_dialog(TextDialog(self.app, "PASTE AN RTTTL RINGTONE", "", self._set_tune, TUNE_LENGTH))
        if ui.button(default, "DEFAULT", "default tune", size=BODY, enabled=online):
            self.link.send("tune:")
        label, icon, command = ("END", "square", "sound_stop") if status.playing else ("TEST", "play", "sound_test")
        if ui.button(test, label, "test tune", icon=icon, size=BODY,
                     enabled=online and (status.playing or not status.armed)):
            self.link.send(command)

    def _set_tune(self, text):
        if text:
            self.link.send("tune:" + " ".join(text.split()))

    def _draw_update(self, area):
        ui, update = self.ui, self.app.updater
        text, button = rows(area, 1, ui.px(42), gap=ui.px(6))
        if not update:
            ui.paragraph("Auto-update isn't installed: run the setup command once.", text)
            return
        ui.paragraph(update.text, text, BODY, UPDATE_COLORS.get(update.state, MUTED))
        label = "UPDATE NOW" if update.ready else "…" if update.busy else "CHECK NOW"
        if ui.button(button, label, "update", "good" if update.ready else "normal",
                     enabled=not update.busy and update.state != "done"):
            if not update.ready:
                update.check()
            elif self.status.armed:
                self.app.notice("Press STOP first: updates only install while SAFE", AMBER)
            else:
                update.install()

    def _draw_screen(self, area):
        ui, app = self.ui, self.app
        full, fps, keys = columns(area, 1.2, 1.2, 0.8, gap=ui.px(6))
        if ui.button(full, "FULL SCREEN" if app.fullscreen else "WINDOW", "fullscreen",
                     "selected" if app.fullscreen else "normal", sub="F11", size=BODY):
            app.set_fullscreen(not app.fullscreen)
        if ui.button(fps, "FRAME RATE", style="selected" if app.show_fps else "normal", sub="F12", size=BODY):
            app.show_fps = not app.show_fps
        if ui.button(keys, "KEYS", sub="F10", size=BODY):
            app.open_dialog(HelpDialog(app))

    def _draw_power(self, area):
        ui = self.ui
        top, close = rows(area, 1.2, 1, gap=ui.px(6))
        off, restart = columns(top, 1, 1, gap=ui.px(6))
        unlocked = not self.status.armed
        if ui.button(off, "SHUT DOWN", icon="power", size=BODY, enabled=unlocked):
            self._confirm("Shut the Pi down?", "Motors off first. Wait 20 s before unplugging.", "SHUT DOWN",
                          lambda: self._power("off"))
        if ui.button(restart, "RESTART", icon="restart", size=BODY, enabled=unlocked):
            self._confirm("Restart the Pi?", "Takes about a minute.", "RESTART", lambda: self._power("reboot"))
        if ui.button(close, "CLOSE DASHBOARD", size=BODY):
            self._confirm("Close the dashboard?", "The motor program keeps running. A keyboard profile disarms.",
                          "CLOSE", self.app.quit)

    def _confirm(self, title, text, action, do):
        self.app.open_dialog(ConfirmDialog(self.app, title, text, action, do))

    def _power(self, what):
        if self.status.armed:
            self.app.notice("Press STOP first", AMBER)
            return
        self.app.notice("Shutting down…" if what == "off" else "Restarting…", AMBER, 60)
        if self.status.online:
            self.link.send(f"power:{what}")       # rov.py switches the motors off first
        else:
            subprocess.Popen(["sudo", "-n", "systemctl", "poweroff" if what == "off" else "reboot"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
