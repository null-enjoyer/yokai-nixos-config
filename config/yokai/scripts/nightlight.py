#!/usr/bin/env python3
"""Persist night-light settings and control the managed hyprsunset instance."""
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time

DEFAULTS = {"temperature": 4000, "schedule": True, "start": "20:30", "end": "07:00", "enabled": False}
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "yokai"
SETTINGS_PATH = CONFIG_DIR / "nightlight.json"
PROFILE_PATH = CONFIG_DIR.parent / "hypr" / "hyprsunset.conf"


def request(command):
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr"
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    path = runtime / signature / ".hyprsunset.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(1)
        connection.connect(str(path))
        connection.sendall(command.encode())
        connection.shutdown(socket.SHUT_WR)
        return connection.recv(4096).decode().strip()


def validate(settings):
    if type(settings["temperature"]) is not int or not 1000 <= settings["temperature"] <= 6500:
        raise ValueError("Temperature must be between 1000 and 6500 K")
    if any(type(settings[key]) is not bool for key in ("schedule", "enabled")):
        raise ValueError("Invalid night-light mode")
    for key in ("start", "end"):
        if not isinstance(settings[key], str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", settings[key]):
            raise ValueError("Use a time in HH:MM format")
    if settings["start"] == settings["end"]:
        raise ValueError("Start and end times must be different")
    return settings


def read_settings():
    settings = dict(DEFAULTS)
    if SETTINGS_PATH.exists():
        settings.update(json.loads(SETTINGS_PATH.read_text()))
    return validate(settings)


def atomic_write(path, text):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_settings(settings):
    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    def profile(at, enabled):
        return f"profile {{\n  time = {at}\n  temperature = {settings['temperature']}\n  identity = {'false' if enabled else 'true'}\n}}\n"
    if settings["schedule"]:
        profiles = profile(settings["end"], False) + "\n" + profile(settings["start"], True)
    else:
        profiles = profile("00:00", settings["enabled"])
    atomic_write(SETTINGS_PATH, json.dumps(settings, indent=2) + "\n")
    atomic_write(PROFILE_PATH, "# Managed by YŌKAI night-light settings.\nmax-gamma = 100\n\n" + profiles)


def status():
    settings = read_settings()
    try:
        identity = request("identity get")
        if identity not in ("true", "false"):
            raise ValueError("Unsupported night-light response")
        enabled = identity == "false"
        temperature = int(request("temperature"))
        return {"settings": settings, "ready": True, "enabled": enabled, "temperature": temperature, "error": ""}
    except (OSError, ValueError):
        return {"settings": settings, "ready": False, "enabled": False, "temperature": settings["temperature"], "error": "Night light is unavailable"}


def wait_ready():
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            if request("identity get") in ("true", "false"):
                return
        except OSError:
            pass
        time.sleep(.05)
    raise RuntimeError("Night light did not start")


def set_enabled(enabled, temperature):
    response = request(f"temperature {temperature}" if enabled else "identity true")
    if response != "ok":
        raise RuntimeError(response)


def control(action, changes):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    # Keep the JSON and generated profiles consistent. Release before restarting:
    # hyprsunset's ExecStartPre uses the same initialization path and lock.
    with (CONFIG_DIR / "nightlight.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        settings = read_settings()
        if action == "ensure":
            write_settings(settings)
            return
        before = status()
        if action == "toggle":
            settings["enabled"] = not before["enabled"]
            write_settings(settings)
        elif action == "configure":
            if not isinstance(changes, dict) or changes.keys() - {"temperature", "schedule", "start", "end"}:
                raise ValueError("Invalid night-light setting")
            settings.update(changes)
            settings["enabled"] = before["enabled"]
            validate(settings)
            write_settings(settings)
    if action == "toggle":
        if not before["ready"]:
            subprocess.run(["systemctl", "--user", "start", "hyprsunset.service"], check=True, timeout=10)
            wait_ready()
        set_enabled(settings["enabled"], settings["temperature"])
    elif action == "configure":
        # hyprsunset reads profiles at startup; it has no profile-reload command.
        subprocess.run(["systemctl", "--user", "restart", "hyprsunset.service"], check=True, timeout=10)
        wait_ready()
        schedule_changed = bool(changes.keys() & {"schedule", "start", "end"})
        if not settings["schedule"] or (not schedule_changed and before["ready"]):
            set_enabled(before["enabled"], settings["temperature"])


if __name__ == "__main__":
    try:
        action = sys.argv[1] if len(sys.argv) > 1 else "status"
        if action not in {"status", "ensure", "toggle", "configure"}:
            raise ValueError("Unknown night-light action")
        if action != "status":
            control(action, json.loads(sys.argv[2]) if len(sys.argv) > 2 else {})
        print(json.dumps(status() if action != "ensure" else {"ready": True}))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
