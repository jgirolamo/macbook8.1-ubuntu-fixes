#!/usr/bin/env python3
"""MacBook Battery — AlDente-style charge limit + health dashboard for Intel MacBooks."""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk, Pango  # noqa: E402

BAT = Path("/sys/class/power_supply/BAT0")
ADP = Path("/sys/class/power_supply/ADP1")
END_THRESH = BAT / "charge_control_end_threshold"
HELPER = Path("/usr/local/sbin/macbook-bclm")
STATE_DIR = Path.home() / ".local" / "share" / "macbook-battery"
HISTORY = STATE_DIR / "history.jsonl"
CONF = STATE_DIR / "config.json"
APP_ID = "com.macbook81.BatteryDashboard"


def _read_int(path: Path, default: int | None = None) -> int | None:
    try:
        return int(path.read_text().strip())
    except Exception:
        return default


def _read_str(path: Path, default: str = "") -> str:
    try:
        return path.read_text().strip()
    except Exception:
        return default


@dataclass
class BatterySnapshot:
    capacity: int = 0
    status: str = "Unknown"
    ac_online: bool = False
    charge_now: int = 0
    charge_full: int = 0
    charge_design: int = 0
    voltage_now: int = 0
    current_now: int = 0
    temp_c: float | None = None
    cycles: int | None = None
    manufacturer: str = ""
    model: str = ""
    end_threshold: int | None = None
    threshold_supported: bool = False
    power_w: float = 0.0
    health_pct: float | None = None
    time_hours: float | None = None
    time_label: str = "—"

    @classmethod
    def capture(cls) -> "BatterySnapshot":
        s = cls()
        s.capacity = _read_int(BAT / "capacity", 0) or 0
        s.status = _read_str(BAT / "status", "Unknown")
        s.ac_online = (_read_int(ADP / "online", 0) or 0) == 1
        s.charge_now = _read_int(BAT / "charge_now", 0) or 0
        s.charge_full = _read_int(BAT / "charge_full", 0) or 0
        s.charge_design = _read_int(BAT / "charge_full_design", 0) or 0
        s.voltage_now = _read_int(BAT / "voltage_now", 0) or 0
        s.current_now = _read_int(BAT / "current_now", 0) or 0
        temp = _read_int(BAT / "temp")
        s.temp_c = (temp / 10.0) if temp is not None else None
        s.cycles = _read_int(BAT / "cycle_count")
        s.manufacturer = _read_str(BAT / "manufacturer")
        s.model = _read_str(BAT / "model_name")
        s.threshold_supported = END_THRESH.exists()
        s.end_threshold = _read_int(END_THRESH) if s.threshold_supported else None
        if s.voltage_now and s.current_now:
            s.power_w = (s.voltage_now / 1e6) * (s.current_now / 1e6)
        if s.charge_design > 0 and s.charge_full > 0:
            s.health_pct = 100.0 * s.charge_full / s.charge_design
        # Estimate time
        cur = abs(s.current_now)
        if cur > 50_000:  # µA
            if s.status.lower() == "charging" and s.charge_full > s.charge_now:
                target = s.charge_full
                if s.end_threshold and s.end_threshold < 100:
                    target = min(target, int(s.charge_full * s.end_threshold / 100))
                rem = max(0, target - s.charge_now)
                s.time_hours = rem / cur
                s.time_label = _fmt_hours(s.time_hours) + " to limit"
            elif s.status.lower() == "discharging" and s.charge_now > 0:
                s.time_hours = s.charge_now / cur
                s.time_label = _fmt_hours(s.time_hours) + " left"
            else:
                s.time_label = "—"
        else:
            s.time_label = "Idle" if s.ac_online else "—"
        return s


def _fmt_hours(h: float | None) -> str:
    if h is None or not math.isfinite(h):
        return "—"
    m = int(round(h * 60))
    if m < 60:
        return f"{m}m"
    return f"{m // 60}h {m % 60:02d}m"


def _load_conf() -> dict:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if CONF.exists():
        try:
            return json.loads(CONF.read_text())
        except Exception:
            pass
    return {"limit_enabled": True, "limit": 80, "presets": [60, 70, 80, 90]}


def _save_conf(cfg: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    CONF.write_text(json.dumps(cfg, indent=2))


def _append_history(snap: BatterySnapshot) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    row = {
        "t": datetime.now().isoformat(timespec="seconds"),
        "capacity": snap.capacity,
        "status": snap.status,
        "power_w": round(snap.power_w, 2),
        "temp_c": snap.temp_c,
        "threshold": snap.end_threshold,
    }
    with HISTORY.open("a") as f:
        f.write(json.dumps(row) + "\n")
    # keep last ~2000 lines
    try:
        lines = HISTORY.read_text().splitlines()
        if len(lines) > 2000:
            HISTORY.write_text("\n".join(lines[-2000:]) + "\n")
    except Exception:
        pass


def set_end_threshold(value: int) -> tuple[bool, str]:
    value = max(20, min(100, int(value)))
    if not END_THRESH.exists():
        return False, "Charge limit not available — install applesmc-next DKMS."
    # Prefer installed helper (polkit / setuid-ish via pkexec policy)
    if HELPER.exists() and os.access(HELPER, os.X_OK):
        try:
            r = subprocess.run(
                ["pkexec", str(HELPER), str(value)],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if r.returncode == 0:
                return True, f"Charge limit set to {value}%"
            return False, (r.stderr or r.stdout or "pkexec failed").strip()
        except Exception as e:
            return False, str(e)
    # Fallback: direct write if root, else pkexec tee
    try:
        if os.access(END_THRESH, os.W_OK):
            END_THRESH.write_text(f"{value}\n")
            return True, f"Charge limit set to {value}%"
        r = subprocess.run(
            ["pkexec", "tee", str(END_THRESH)],
            input=f"{value}\n",
            text=True,
            capture_output=True,
            timeout=60,
        )
        if r.returncode == 0:
            return True, f"Charge limit set to {value}%"
        return False, (r.stderr or "Permission denied").strip()
    except Exception as e:
        return False, str(e)


def power_profile() -> str:
    try:
        return subprocess.check_output(["powerprofilesctl", "get"], text=True).strip()
    except Exception:
        return "—"


def set_power_profile(name: str) -> None:
    subprocess.run(["powerprofilesctl", "set", name], check=False)


class Ring(Gtk.DrawingArea):
    def __init__(self):
        super().__init__()
        self.pct = 0
        self.limit = 80
        self.limit_on = True
        self.status = ""
        self.set_content_width(220)
        self.set_content_height(220)
        self.set_draw_func(self._draw)

    def update(self, pct: int, limit: int, limit_on: bool, status: str) -> None:
        self.pct = pct
        self.limit = limit
        self.limit_on = limit_on
        self.status = status
        self.queue_draw()

    def _draw(self, area, cr, w, h):
        cx, cy = w / 2, h / 2
        radius = min(w, h) / 2 - 12
        # track
        cr.set_line_width(14)
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.25)
        cr.arc(cx, cy, radius, 0, 2 * math.pi)
        cr.stroke()
        # limit marker
        if self.limit_on and 20 <= self.limit <= 100:
            ang = -math.pi / 2 + 2 * math.pi * (self.limit / 100)
            cr.set_source_rgba(0.95, 0.55, 0.15, 0.9)
            cr.set_line_width(3)
            cr.move_to(cx + (radius - 18) * math.cos(ang), cy + (radius - 18) * math.sin(ang))
            cr.line_to(cx + (radius + 8) * math.cos(ang), cy + (radius + 8) * math.sin(ang))
            cr.stroke()
        # fill
        frac = max(0, min(1, self.pct / 100))
        if self.pct <= 15:
            cr.set_source_rgb(0.90, 0.25, 0.22)
        elif self.status.lower() == "charging":
            cr.set_source_rgb(0.20, 0.72, 0.42)
        else:
            cr.set_source_rgb(0.25, 0.62, 0.95)
        cr.set_line_width(14)
        cr.set_line_cap(1)  # ROUND
        cr.arc(cx, cy, radius, -math.pi / 2, -math.pi / 2 + 2 * math.pi * frac)
        cr.stroke()


class BatteryDashboard(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application):
        super().__init__(application=app, title="MacBook Battery")
        self.set_default_size(520, 700)
        self.cfg = _load_conf()
        self._applying = False

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_title_widget(Gtk.Label(label="MacBook Battery"))
        refresh = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        refresh.set_tooltip_text("Refresh")
        refresh.connect("clicked", lambda *_: self.refresh())
        header.pack_end(refresh)
        toolbar.add_top_bar(header)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_top(16)
        box.set_margin_bottom(24)
        box.set_margin_start(20)
        box.set_margin_end(20)
        scroller.set_child(box)
        toolbar.set_content(scroller)

        self._toast_overlay = Adw.ToastOverlay()
        self._toast_overlay.set_child(toolbar)
        self.set_content(self._toast_overlay)

        # Hero
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hero.set_halign(Gtk.Align.CENTER)
        self.ring = Ring()
        hero.append(self.ring)
        self.pct_label = Gtk.Label()
        self.pct_label.add_css_class("title-1")
        self.status_label = Gtk.Label()
        self.status_label.add_css_class("dim-label")
        self.eta_label = Gtk.Label()
        self.eta_label.add_css_class("dim-label")
        hero.append(self.pct_label)
        hero.append(self.status_label)
        hero.append(self.eta_label)
        box.append(hero)

        # Charge limit card
        limit_group = Adw.PreferencesGroup(title="Charge limit", description="Like AlDente — stop charging at a ceiling. Stored in SMC NVRAM.")
        self.limit_row = Adw.ActionRow(title="Enable charge limit")
        self.limit_switch = Gtk.Switch()
        self.limit_switch.set_valign(Gtk.Align.CENTER)
        self.limit_switch.set_active(bool(self.cfg.get("limit_enabled", True)))
        self.limit_switch.connect("notify::active", self._on_toggle)
        self.limit_row.add_suffix(self.limit_switch)
        self.limit_row.set_activatable_widget(self.limit_switch)
        limit_group.add(self.limit_row)

        slider_row = Adw.ActionRow(title="Stop charging at")
        self.limit_value = Gtk.Label()
        self.limit_value.add_css_class("title-3")
        slider_row.add_suffix(self.limit_value)
        limit_group.add(slider_row)

        self.slider = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 20, 100, 1)
        self.slider.set_value(int(self.cfg.get("limit", 80)))
        self.slider.set_draw_value(False)
        self.slider.set_hexpand(True)
        self.slider.connect("value-changed", self._on_slider)
        pad = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        pad.set_margin_start(12)
        pad.set_margin_end(12)
        pad.set_margin_bottom(8)
        pad.append(self.slider)
        # presets
        presets = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        presets.set_halign(Gtk.Align.CENTER)
        presets.set_margin_bottom(12)
        for p in self.cfg.get("presets", [60, 70, 80, 90]):
            b = Gtk.Button(label=f"{p}%")
            b.add_css_class("pill")
            b.connect("clicked", self._preset, p)
            presets.append(b)
        travel = Gtk.Button(label="100% trip")
        travel.add_css_class("pill")
        travel.connect("clicked", self._preset, 100)
        presets.append(travel)
        pad.append(presets)
        self.apply_btn = Gtk.Button(label="Apply limit")
        self.apply_btn.add_css_class("suggested-action")
        self.apply_btn.set_halign(Gtk.Align.CENTER)
        self.apply_btn.connect("clicked", self._apply)
        pad.append(self.apply_btn)
        self.limit_hint = Gtk.Label()
        self.limit_hint.add_css_class("dim-label")
        self.limit_hint.set_wrap(True)
        self.limit_hint.set_margin_top(6)
        pad.append(self.limit_hint)
        # embed pad under group via a clamp
        wrap = Gtk.ListBox()
        wrap.add_css_class("boxed-list")
        fake = Gtk.ListBoxRow()
        fake.set_activatable(False)
        fake.set_selectable(False)
        fake.set_child(pad)
        wrap.append(fake)
        box.append(limit_group)
        box.append(wrap)

        # Stats
        stats = Adw.PreferencesGroup(title="Battery health")
        self.rows = {}
        for key, title in [
            ("health", "Health"),
            ("cycles", "Cycle count"),
            ("capacity", "Full charge capacity"),
            ("design", "Design capacity"),
            ("voltage", "Voltage"),
            ("current", "Current"),
            ("power", "Power"),
            ("temp", "Temperature"),
            ("ac", "Power adapter"),
            ("chem", "Chemistry"),
            ("profile", "Power profile"),
            ("module", "Charge control"),
        ]:
            row = Adw.ActionRow(title=title)
            lab = Gtk.Label()
            lab.add_css_class("dim-label")
            row.add_suffix(lab)
            stats.add(row)
            self.rows[key] = lab
        box.append(stats)

        # Power profiles
        prof = Adw.PreferencesGroup(title="Power profile")
        btnbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btnbox.set_halign(Gtk.Align.CENTER)
        btnbox.set_margin_top(8)
        btnbox.set_margin_bottom(8)
        self._prof_btns: dict[str, Gtk.ToggleButton] = {}
        self._prof_guard = False
        for name, label in [
            ("power-saver", "Power Saver"),
            ("balanced", "Balanced"),
            ("performance", "Performance"),
        ]:
            b = Gtk.ToggleButton(label=label)
            b.connect("toggled", self._profile_toggled, name)
            btnbox.append(b)
            self._prof_btns[name] = b
        prow = Gtk.ListBox()
        prow.add_css_class("boxed-list")
        pr = Gtk.ListBoxRow()
        pr.set_activatable(False)
        pr.set_child(btnbox)
        prow.append(pr)
        box.append(prof)
        box.append(prow)

        self._update_limit_label()
        self.refresh()
        GLib.timeout_add_seconds(5, self._tick)

    def _tick(self):
        self.refresh(log=True)
        return True

    def _on_slider(self, *_):
        self.cfg["limit"] = int(self.slider.get_value())
        self._update_limit_label()
        self._save_local()

    def _on_toggle(self, *_):
        self.cfg["limit_enabled"] = self.limit_switch.get_active()
        self._save_local()
        self.refresh()

    def _preset(self, _btn, value: int):
        self.slider.set_value(value)
        if value < 100:
            self.limit_switch.set_active(True)
        self._apply()

    def _update_limit_label(self):
        self.limit_value.set_text(f"{int(self.slider.get_value())}%")

    def _save_local(self):
        _save_conf(self.cfg)

    def _apply(self, *_):
        if self._applying:
            return
        self._applying = True
        self.apply_btn.set_sensitive(False)
        target = 100
        if self.limit_switch.get_active():
            target = int(self.slider.get_value())
        ok, msg = set_end_threshold(target)
        self.cfg["limit"] = int(self.slider.get_value())
        self.cfg["limit_enabled"] = self.limit_switch.get_active()
        self._save_local()
        self._toast(msg if ok else f"Failed: {msg}", ok)
        self.apply_btn.set_sensitive(True)
        self._applying = False
        self.refresh()

    def _toast(self, text: str, ok: bool = True):
        t = Adw.Toast.new(text)
        t.set_timeout(4)
        self._toast_overlay.add_toast(t)

    def _profile_toggled(self, btn: Gtk.ToggleButton, name: str):
        if self._prof_guard or not btn.get_active():
            return
        self._prof_guard = True
        for n, b in self._prof_btns.items():
            b.set_active(n == name)
        self._prof_guard = False
        set_power_profile(name)
        self.refresh()

    def refresh(self, log: bool = False):
        snap = BatterySnapshot.capture()
        if log:
            _append_history(snap)

        self.pct_label.set_text(f"{snap.capacity}%")
        ac = " · AC" if snap.ac_online else " · Battery"
        self.status_label.set_text(f"{snap.status}{ac}")
        self.eta_label.set_text(snap.time_label)

        lim = snap.end_threshold or int(self.cfg.get("limit", 80))
        lim_on = bool(snap.end_threshold and snap.end_threshold < 100)
        if snap.threshold_supported and snap.end_threshold is not None:
            # sync switch from hardware if not mid-edit
            if not self.slider.get_focus_child():
                pass
        self.ring.update(snap.capacity, lim, lim_on or self.limit_switch.get_active(), snap.status)

        if snap.health_pct is not None:
            self.rows["health"].set_text(f"{snap.health_pct:.0f}%")
        else:
            self.rows["health"].set_text("—")
        self.rows["cycles"].set_text(str(snap.cycles) if snap.cycles is not None else "—")
        self.rows["capacity"].set_text(f"{snap.charge_full/1000:.0f} mAh" if snap.charge_full else "—")
        self.rows["design"].set_text(f"{snap.charge_design/1000:.0f} mAh" if snap.charge_design else "—")
        self.rows["voltage"].set_text(f"{snap.voltage_now/1e6:.2f} V")
        sign = ""
        if snap.status.lower() == "charging":
            sign = "+"
        elif snap.status.lower() == "discharging":
            sign = "−"
        self.rows["current"].set_text(f"{sign}{abs(snap.current_now)/1e6:.2f} A")
        self.rows["power"].set_text(f"{sign}{abs(snap.power_w):.1f} W")
        self.rows["temp"].set_text(f"{snap.temp_c:.1f} °C" if snap.temp_c is not None else "—")
        self.rows["ac"].set_text("Connected" if snap.ac_online else "Disconnected")
        tech = _read_str(BAT / "technology")
        self.rows["chem"].set_text(f"{tech} · {snap.manufacturer} {snap.model}".strip(" ·"))

        prof = power_profile()
        self.rows["profile"].set_text(prof)
        self._prof_guard = True
        for n, b in self._prof_btns.items():
            b.set_active(n == prof)
        self._prof_guard = False

        if snap.threshold_supported:
            self.rows["module"].set_text(f"Active · BCLM {snap.end_threshold}%")
            self.limit_hint.set_text(
                "Limit is stored in the SMC (survives reboot & macOS). Apply after changing the slider."
            )
            self.apply_btn.set_sensitive(True)
        else:
            self.rows["module"].set_text("Missing applesmc-next")
            self.limit_hint.set_text(
                "Install applesmc-next DKMS to enable charge limiting (sudo ./scripts/07-battery-dashboard.sh)."
            )
            self.apply_btn.set_sensitive(False)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        win = self.props.active_window
        if not win:
            win = BatteryDashboard(self)
        win.present()


def main():
    Adw.init()
    app = App()
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
