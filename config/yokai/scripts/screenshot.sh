#!/usr/bin/env bash
set -euo pipefail

case "${1:-region}" in
  region|annotate)
    # slurp reads rectangle presets from non-terminal stdin before showing its UI.
    geometry=$(slurp </dev/null) || exit 0
    [[ -n "$geometry" ]] || exit 0
    if [[ "${1:-region}" == annotate ]]; then
      grim -g "$geometry" - | satty --filename -
    else
      grim -g "$geometry" - | wl-copy
    fi
    ;;
  full) grim - | wl-copy ;;
  *) echo "Usage: screenshot.sh {region|annotate|full}" >&2; exit 2 ;;
esac
