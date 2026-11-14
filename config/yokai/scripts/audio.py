#!/usr/bin/env python3
"""Audio devices and application volumes, including virtual PipeWire sources."""
import concurrent.futures
import json
import subprocess


def pactl(*args):
    return json.loads(subprocess.check_output(["pactl", "--format=json", *args], text=True, timeout=3))


def volume(item):
    channels = item.get("volume", {}).values()
    levels = [channel["value"] / 65536 * 100 for channel in channels]
    return round(sum(levels) / len(levels)) if levels else 0


def device(item):
    return {"id": item["index"], "name": item["name"], "description": item["description"],
            "volume": volume(item), "muted": item["mute"]}


def streams(items):
    result = []
    for item in items:
        props = item.get("properties", {})
        # Easy Effects uses its own capture/playback streams to process audio.
        # Show the applications feeding that pipeline, not its internal links.
        if props.get("application.id") == "com.github.wwmm.easyeffects":
            continue
        result.append({"id": item["index"], "description": props.get("application.name") or props.get("media.name") or "Audio stream",
                       "detail": props.get("media.name", ""), "volume": volume(item), "muted": item["mute"]})
    return sorted(result, key=lambda item: (item["description"].lower(), item["id"]))


def microphone_recording(items, sources):
    inputs = {str(item["index"]) for item in sources
              if item.get("properties", {}).get("device.class") != "monitor"}
    return any(not item.get("corked", False)
               and str(item.get("source")) in inputs
               and item.get("properties", {}).get("application.id") != "com.github.wwmm.easyeffects"
               for item in items)


def snapshot():
    requests = [("info",), ("list", "sinks"), ("list", "sources"), ("list", "sink-inputs"), ("list", "source-outputs")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(requests)) as pool:
        info, sinks, sources, playback, recording = list(pool.map(lambda args: pactl(*args), requests))
    return {"defaultOutput": info["default_sink_name"], "defaultInput": info["default_source_name"],
            "outputs": [device(item) for item in sinks],
            "inputs": [device(item) for item in sources if item.get("properties", {}).get("device.class") != "monitor"],
            "playback": streams(playback), "recording": streams(recording),
            "microphoneRecording": microphone_recording(recording, sources)}


if __name__ == "__main__":
    try:
        print(json.dumps(snapshot()))
    except (subprocess.SubprocessError, OSError, ValueError, KeyError):
        print(json.dumps({"outputs": [], "inputs": [], "playback": [], "recording": [], "error": "Audio server unavailable"}))
