#!/usr/bin/env python3
"""Cached Open-Meteo forecast; location is supplied by the private host config."""
import argparse
from datetime import date
import json
import math
import os
from pathlib import Path
import time
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REFRESH_SECONDS = 25 * 60
RETRY_SECONDS = 5 * 60
CONDITIONS = {
    0: ("Clear", "weather-clear"),
    1: ("Mostly clear", "weather-clear"),
    2: ("Partly cloudy", "weather-few-clouds"),
    3: ("Overcast", "weather-overcast"),
    45: ("Fog", "weather-fog"),
    48: ("Freezing fog", "weather-fog"),
    51: ("Light drizzle", "weather-showers-scattered"),
    53: ("Drizzle", "weather-showers-scattered"),
    55: ("Heavy drizzle", "weather-showers"),
    56: ("Freezing drizzle", "weather-showers-scattered"),
    57: ("Heavy freezing drizzle", "weather-showers"),
    61: ("Light rain", "weather-showers-scattered"),
    63: ("Rain", "weather-showers"),
    65: ("Heavy rain", "weather-showers"),
    66: ("Freezing rain", "weather-showers-scattered"),
    67: ("Heavy freezing rain", "weather-showers"),
    71: ("Light snow", "weather-snow"),
    73: ("Snow", "weather-snow"),
    75: ("Heavy snow", "weather-snow"),
    77: ("Snow grains", "weather-snow"),
    80: ("Rain showers", "weather-showers-scattered"),
    81: ("Rain showers", "weather-showers"),
    82: ("Heavy rain showers", "weather-showers"),
    85: ("Snow showers", "weather-snow"),
    86: ("Heavy snow showers", "weather-snow"),
    95: ("Thunderstorm", "weather-storm"),
    96: ("Thunderstorm with hail", "weather-storm"),
    97: ("Heavy thunderstorm", "weather-storm"),
    99: ("Thunderstorm with heavy hail", "weather-storm"),
}


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("Invalid weather value")
    return value


def condition(code, is_day=True):
    label, icon = CONDITIONS.get(number(code), ("Unknown conditions", "weather-overcast"))
    if not is_day and icon in ("weather-clear", "weather-few-clouds"):
        icon += "-night"
    return label, icon


def location():
    city = os.environ.get("YOKAI_WEATHER_CITY", "").strip()
    try:
        latitude = float(os.environ.get("YOKAI_WEATHER_LATITUDE", ""))
        longitude = float(os.environ.get("YOKAI_WEATHER_LONGITUDE", ""))
    except ValueError as error:
        raise ValueError("Weather location is not configured.") from error
    if not city or not math.isfinite(latitude) or not math.isfinite(longitude):
        raise ValueError("Weather location is not configured.")
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValueError("Weather coordinates are invalid.")
    return {"city": city, "latitude": latitude, "longitude": longitude}


def read_cache(path, place):
    try:
        cached = json.loads(path.read_text())
        if cached.get("location") != place:
            return {}
        snapshot = cached.get("snapshot", {})
        if snapshot:
            for key in ("temperature", "feelsLike", "high", "low", "updatedAt"):
                number(snapshot[key])
            if not isinstance(snapshot.get("forecast"), list):
                return {}
        number(cached.get("nextCheckAt", 0))
        return cached
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return {}


def write_cache(path, cached):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(f".{os.getpid()}.tmp")
        temporary.write_text(json.dumps(cached, allow_nan=False))
        temporary.replace(path)
    except OSError:
        # The current reading remains usable even when the cache is unwritable.
        pass


def snapshot_from_forecast(payload, city, now):
    current = payload["current"]
    daily = payload["daily"]
    label, icon = condition(current["weather_code"], bool(number(current["is_day"])))
    forecast = []
    for index, day_text in enumerate(daily["time"][:3]):
        day = date.fromisoformat(day_text)
        day_label, day_icon = condition(daily["weather_code"][index])
        forecast.append({
            "date": day_text,
            "day": ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[day.weekday()],
            "condition": day_label,
            "iconName": day_icon,
            "high": number(daily["temperature_2m_max"][index]),
            "low": number(daily["temperature_2m_min"][index]),
        })
    if not forecast:
        raise ValueError("Missing daily forecast")
    return {
        "city": city,
        "temperature": number(current["temperature_2m"]),
        "feelsLike": number(current["apparent_temperature"]),
        "condition": label,
        "iconName": icon,
        "high": forecast[0]["high"],
        "low": forecast[0]["low"],
        "forecast": forecast,
        "updatedAt": now,
    }


def fetch_forecast(place, now):
    parameters = {
        "latitude": place["latitude"],
        "longitude": place["longitude"],
        "current": "temperature_2m,apparent_temperature,weather_code,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "temperature_unit": "celsius",
        "timezone": "auto",
        "forecast_days": 3,
    }
    request = Request("https://api.open-meteo.com/v1/forecast?" + urlencode(parameters),
                      headers={"User-Agent": "Yokai-weather/1.0", "Accept": "application/json"})
    with urlopen(request, timeout=10) as response:
        payload = json.load(response)
    return snapshot_from_forecast(payload, place["city"], now)


def emit(cached, city, now):
    snapshot = cached.get("snapshot", {})
    stale = bool(snapshot) and now - snapshot["updatedAt"] >= REFRESH_SECONDS
    print(json.dumps({
        **snapshot,
        "city": city,
        "ready": bool(snapshot),
        "stale": stale,
        "error": cached.get("error", ""),
        "nextCheckAt": cached.get("nextCheckAt", 0),
    }, allow_nan=False), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cached", action="store_true", help="Read saved state without network access")
    args = parser.parse_args()
    now = int(time.time())
    try:
        place = location()
    except ValueError as error:
        emit({"error": str(error), "nextCheckAt": now + REFRESH_SECONDS}, "", now)
        return
    cache_home = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    path = cache_home / "yokai" / "weather.json"
    cached = read_cache(path, place)
    emit(cached, place["city"], now)
    if args.cached or now < cached.get("nextCheckAt", 0):
        return
    try:
        snapshot = fetch_forecast(place, now)
        cached = {"snapshot": snapshot, "error": "", "nextCheckAt": now + REFRESH_SECONDS}
    except (URLError, OSError, TimeoutError):
        cached.update(error="Weather service is unavailable.", nextCheckAt=now + RETRY_SECONDS)
    except (ValueError, KeyError, TypeError, IndexError):
        cached.update(error="Weather service returned an invalid forecast.", nextCheckAt=now + RETRY_SECONDS)
    cached["location"] = place
    write_cache(path, cached)
    emit(cached, place["city"], now)


if __name__ == "__main__":
    main()
