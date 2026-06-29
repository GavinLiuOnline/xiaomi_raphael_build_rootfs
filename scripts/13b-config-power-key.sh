#!/bin/bash
set -e

# 桌面版：电源键短按熄/亮屏，长按 3s 弹出 GNOME 原生关机菜单
if [ "$IS_DESKTOP" != "true" ]; then
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] [13b] ⏭️  非桌面镜像，跳过电源键配置"
	exit 0
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [13b] 🔘 配置电源键（短按熄屏 / 长按 3s GNOME 关机菜单）"

# 桌面由 GNOME/Phosh 管显示，禁用 server 版 tty 自动熄屏
chroot rootdir systemctl disable blank_screen.service 2>/dev/null || true
chroot rootdir systemctl mask blank_screen.service 2>/dev/null || true

install -d rootdir/etc/systemd/logind.conf.d
cat > rootdir/etc/systemd/logind.conf.d/raphael-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
PowerKeyIgnoreInhibited=yes
EOF

install -d rootdir/usr/local/sbin
cat > rootdir/usr/local/sbin/raphael-power-key.py << 'EOF'
#!/usr/bin/env python3
"""Raphael 电源键：短按切换屏幕，长按 3s 弹出 GNOME 原生关机菜单"""
import fcntl
import logging
import os
import pwd
import select
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

EV_KEY = 0x01
KEY_POWER = 116
EVENT_FMT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)
LONG_PRESS_SEC = 3.0
AUTO_USER = os.environ.get("RAPHAEL_AUTOLOGIN_USER", "user")

MUTTER_BUS = "org.gnome.Mutter.DisplayConfig"
MUTTER_PATH = "/org/gnome/Mutter/DisplayConfig"
MUTTER_IFACE = "org.gnome.Mutter.DisplayConfig"
POWER_PROP = "PowerSaveMode"

logging.basicConfig(
    level=logging.INFO,
    format="raphael-power-key: %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("raphael-power-key")


def find_power_input():
    base = Path("/sys/class/input")
    for name_path in sorted(base.glob("input*/name")):
        name = name_path.read_text().strip()
        if name == "pm8941_pwrkey":
            num = name_path.parent.name.replace("input", "")
            dev = Path(f"/dev/input/event{num}")
            if dev.exists():
                return dev
    return Path("/dev/input/event0")


def user_env():
    uid = pwd.getpwnam(AUTO_USER).pw_uid
    runtime = Path(f"/run/user/{uid}")
    env = os.environ.copy()
    env.update(
        {
            "HOME": f"/home/{AUTO_USER}",
            "USER": AUTO_USER,
            "LOGNAME": AUTO_USER,
            "XDG_RUNTIME_DIR": str(runtime),
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path={runtime / 'bus'}",
        }
    )
    for disp in ("wayland-0", "wayland-1"):
        if (runtime / disp).exists():
            env["WAYLAND_DISPLAY"] = disp
            break
    return env


def run_as_user(args):
    env = user_env()
    env_cmd = [
        "env",
        f"HOME={env['HOME']}",
        f"USER={env['USER']}",
        f"LOGNAME={env['LOGNAME']}",
        f"XDG_RUNTIME_DIR={env['XDG_RUNTIME_DIR']}",
        f"DBUS_SESSION_BUS_ADDRESS={env['DBUS_SESSION_BUS_ADDRESS']}",
    ]
    if "WAYLAND_DISPLAY" in env:
        env_cmd.append(f"WAYLAND_DISPLAY={env['WAYLAND_DISPLAY']}")
    return subprocess.run(
        ["runuser", "-u", AUTO_USER, "--", *env_cmd, *args],
        check=False,
        capture_output=True,
        text=True,
    )


def get_power_save_mode():
    r = run_as_user(
        [
            "busctl",
            "--user",
            "get-property",
            MUTTER_BUS,
            MUTTER_PATH,
            MUTTER_IFACE,
            POWER_PROP,
        ]
    )
    if r.returncode != 0:
        log.warning("get PowerSaveMode failed: %s", r.stderr.strip())
        return 0
    return int(r.stdout.split()[1])


def set_power_save_mode(mode):
    r = run_as_user(
        [
            "busctl",
            "--user",
            "set-property",
            MUTTER_BUS,
            MUTTER_PATH,
            MUTTER_IFACE,
            POWER_PROP,
            "i",
            str(mode),
        ]
    )
    if r.returncode != 0:
        log.warning("set PowerSaveMode failed: %s", r.stderr.strip())
        return False
    return True


def toggle_screen():
    try:
        current = get_power_save_mode()
        target = 0 if current else 1
        log.info("toggle screen PowerSaveMode %s -> %s", current, target)
        set_power_save_mode(target)
    except Exception as exc:
        log.error("toggle_screen failed: %s", exc)


def show_shutdown_dialog():
    log.info("show GNOME native shutdown dialog")
    r = run_as_user(
        [
            "busctl",
            "--user",
            "call",
            "org.gnome.Shell",
            "/org/gnome/Shell",
            "org.gnome.Shell",
            "ShowShutdownDialog",
        ]
    )
    if r.returncode != 0:
        log.warning("ShowShutdownDialog failed: %s", r.stderr.strip())
        run_as_user(["gnome-session-quit", "--power-off"])


def grab_device(fd):
    EVIOCGRAB = 0x40044590
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
        log.info("grabbed input device")
    except OSError as exc:
        log.warning("EVIOCGRAB failed: %s", exc)


def main():
    dev = find_power_input()
    fd = os.open(str(dev), os.O_RDONLY | os.O_NONBLOCK)
    grab_device(fd)
    log.info("listening on %s", dev)

    press_time = None
    long_fired = False
    long_timer = None
    is_pressed = False

    def cancel_long_timer():
        nonlocal long_timer
        if long_timer is not None:
            long_timer.cancel()
            long_timer = None

    def on_long_press():
        nonlocal long_fired
        if not is_pressed:
            return
        long_fired = True
        show_shutdown_dialog()

    while True:
        r, _, _ = select.select([fd], [], [], 0.5)
        if not r:
            continue
        data = os.read(fd, EVENT_SIZE)
        if len(data) < EVENT_SIZE:
            continue
        _sec, _usec, ev_type, code, value = struct.unpack(EVENT_FMT, data)
        if ev_type != EV_KEY or code != KEY_POWER:
            continue

        log.info("KEY_POWER value=%s", value)

        if value == 1:
            if not is_pressed:
                is_pressed = True
                press_time = time.monotonic()
                long_fired = False
                cancel_long_timer()
                long_timer = threading.Timer(LONG_PRESS_SEC, on_long_press)
                long_timer.daemon = True
                long_timer.start()
        elif value == 0 and press_time is not None:
            is_pressed = False
            cancel_long_timer()
            if not long_fired:
                duration = time.monotonic() - press_time
                if duration < LONG_PRESS_SEC:
                    toggle_screen()
            press_time = None


if __name__ == "__main__":
    main()
EOF
chmod 755 rootdir/usr/local/sbin/raphael-power-key.py

cat > rootdir/etc/systemd/system/raphael-power-key.service << 'EOF'
[Unit]
Description=Raphael power key handler (screen toggle / shutdown menu)
After=gdm.service network.target
Wants=gdm.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/sbin/raphael-power-key.py
Restart=on-failure
RestartSec=2
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

chroot rootdir systemctl enable raphael-power-key.service
chroot rootdir usermod -aG input user 2>/dev/null || true

# GNOME：禁用自带电源键处理，交给 raphael-power-key
if [ "$DESKTOP_ENV" = "gnome" ]; then
	install -d rootdir/etc/dconf/db/local.d rootdir/etc/dconf/profile
	cat > rootdir/etc/dconf/db/local.d/01-power-key << 'EOF'
[org/gnome/settings-daemon/plugins/power]
power-button-action='nothing'
EOF
	if [ ! -f rootdir/etc/dconf/profile/user ]; then
		cat > rootdir/etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF
	fi
	chroot rootdir dconf update 2>/dev/null || true
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [13b] ✅ 电源键配置完成"
