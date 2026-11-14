#!/usr/bin/env python3
"""Read one Hyprland IPC batch and normalize numeric and named identities."""
import json
import subprocess


def decode_batch(text):
    decoder = json.JSONDecoder()
    values = []
    while text.strip():
        text = text.lstrip()
        value, end = decoder.raw_decode(text)
        values.append(value)
        text = text[end:]
    return values


def address(workspace):
    return str(workspace.get("address") or workspace.get("name") or workspace.get("id", ""))


def normalize(monitors, workspaces, clients, devices):
    focused = next((monitor for monitor in monitors if monitor.get("focused")), {})
    active = focused.get("activeWorkspace", {})
    focused_address = address(active)
    result = []
    for item in workspaces:
        identity = address(item)
        special = identity.startswith("special:")
        count = sum(address(client["workspace"]) == identity for client in clients)
        result.append({"address": identity, "id": item.get("id", int(identity) if identity.isdecimal() else 0), "special": special,
                       "windows": count, "focused": identity == focused_address, "monitor": item.get("monitor", "")})
    keyboards = devices.get("keyboards", [])
    keyboard = next((item for item in keyboards if item.get("main")), keyboards[0] if keyboards else {})
    return {"monitors": monitors, "workspaces": result, "clients": clients,
            "keyboardLayout": keyboard.get("active_keymap", "")}


if __name__ == "__main__":
    raw = subprocess.check_output(["hyprctl", "-j", "--batch", "monitors;workspaces;clients;devices"], text=True, timeout=3)
    print(json.dumps(normalize(*decode_batch(raw))))
