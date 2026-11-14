#!/usr/bin/env python3
"""Small system snapshots, sampled only while the control panel is open."""
import csv
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def cpu():
    values = [int(value) for value in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
    return sum(values), values[3] + values[4]


def cpu_name():
    for line in Path('/proc/cpuinfo').read_text().splitlines():
        key, separator, value = line.partition(':')
        if separator and key.strip() in ('model name', 'Hardware'):
            return value.strip()
    return ''


def cpu_temperature():
    readings = []
    for sensor in Path('/sys/class/hwmon').glob('hwmon*'):
        try:
            driver = (sensor / 'name').read_text().strip()
        except OSError:
            continue
        if driver not in ('coretemp', 'k10temp', 'zenpower', 'cpu_thermal'):
            continue
        for source in sensor.glob('temp*_input'):
            try:
                value = float(source.read_text()) / 1000
                label_file = source.with_name(source.name.replace('_input', '_label'))
                label = label_file.read_text().strip() if label_file.exists() else ''
            except (OSError, ValueError):
                continue
            # Prefer package/die temperature over individual cores or CCDs.
            if label.startswith('Package') or label == 'Tdie':
                priority = 0
            elif label == 'Tctl':
                priority = 1
            else:
                priority = 2
            if math.isfinite(value):
                readings.append((priority, value))
    if not readings:
        return {}
    priority = min(item[0] for item in readings)
    return {'cpuTemp': round(max(value for rank, value in readings if rank == priority), 1)}


def memory():
    values = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        values[key] = int(value.split()[0])
    total = values['MemTotal']
    used = total - values['MemAvailable']
    return {'ram': round(100 * used / total), 'ramUsed': round(used / 1048576, 1), 'ramTotal': round(total / 1048576, 1)}


def gpu():
    if not shutil.which('nvidia-smi'):
        return {}
    try:
        query = 'name,temperature.gpu,utilization.gpu,memory.used,memory.total'
        raw = subprocess.check_output(
            ['nvidia-smi', f'--query-gpu={query}', '--format=csv,noheader,nounits'],
            text=True, stderr=subprocess.DEVNULL, timeout=1)
        name, temperature, load, used, total = next(csv.reader(raw.splitlines()))
        result = {'gpuName': name.strip()}
        fields = [('gpuTemp', temperature, 1), ('gpu', load, 1),
                  ('gpuUsed', used, 1024), ('gpuTotal', total, 1024)]
        for key, raw_value, divisor in fields:
            try:
                value = float(raw_value.strip()) / divisor
            except ValueError:
                continue
            if math.isfinite(value):
                result[key] = round(value) if key == 'gpu' else round(value, 1)
        return result
    except (OSError, ValueError, StopIteration, csv.Error, subprocess.SubprocessError):
        return {}


def mount_path(value):
    # /proc/mounts escapes whitespace and backslashes as octal sequences.
    return re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), value)


def storage():
    mounts = []
    for line in Path('/proc/mounts').read_text().splitlines():
        device, mount, *_ = line.split()
        device, mount = mount_path(device), mount_path(mount)
        if device.startswith('/dev/') or mount == '/':
            mounts.append((device, mount))
    # Root wins over its /nix/store bind mount; shortest paths win other binds.
    mounts.sort(key=lambda entry: (entry[1] != '/', len(entry[1]), entry[1]))
    result = []
    seen = set()
    for device, mount in mounts:
        try:
            device_id = os.stat(mount).st_dev
            if device_id in seen:
                continue
            stat = os.statvfs(mount)
        except OSError:
            continue
        total = stat.f_blocks * stat.f_frsize
        if total <= 0:
            continue
        # Allocated bytes exclude all free blocks, including reserved blocks.
        used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize
        seen.add(device_id)
        result.append({'id': str(device_id), 'mount': mount, 'device': device,
                       'used': round(used / 1073741824, 2), 'total': round(total / 1073741824, 2),
                       'percent': round(100 * used / total, 1)})
    return result


def network_counters():
    counters = {}
    for line in Path('/proc/net/dev').read_text().splitlines()[2:]:
        name, values = line.split(':', 1)
        name = name.strip()
        if name == 'lo' or name.startswith(('veth', 'docker', 'br-')):
            continue
        values = values.split()
        counters[name] = (int(values[0]), int(values[8]))
    return counters


def network_rates(current, previous, elapsed):
    result = []
    for name, (received, sent) in sorted(current.items()):
        old_received, old_sent = previous.get(name, (received, sent))
        # New interfaces and reset counters establish a new baseline.
        download = (received - old_received) / elapsed if received >= old_received and elapsed > 0 else 0
        upload = (sent - old_sent) / elapsed if sent >= old_sent and elapsed > 0 else 0
        result.append({'name': name, 'download': round(download, 1), 'upload': round(upload, 1),
                       'received': received, 'sent': sent})
    return result


def optional(collector, fallback):
    try:
        return collector()
    except (OSError, ValueError, KeyError, IndexError):
        return fallback


if __name__ == '__main__':
    model = optional(cpu_name, '')
    previous_cpu = optional(cpu, None)
    previous_network = optional(network_counters, {})
    previous_time = time.monotonic()
    next_sample = previous_time + 2
    while True:
        time.sleep(max(0, next_sample - time.monotonic()))
        now = time.monotonic()
        next_sample = now + 2
        current_cpu = optional(cpu, None)
        current_network = optional(network_counters, {})
        sample = {'cpuName': model, 'gpuName': '',
                  'storage': optional(storage, []),
                  'network': network_rates(current_network, previous_network, now - previous_time),
                  **optional(memory, {}), **optional(cpu_temperature, {}), **gpu()}
        if current_cpu is not None and previous_cpu is not None:
            total = current_cpu[0] - previous_cpu[0]
            idle = current_cpu[1] - previous_cpu[1]
            if total > 0 and idle >= 0:
                sample['cpu'] = round(max(0, min(100, 100 * (1 - idle / total))))
        print(json.dumps(sample), flush=True)
        previous_cpu, previous_network, previous_time = current_cpu, current_network, now
