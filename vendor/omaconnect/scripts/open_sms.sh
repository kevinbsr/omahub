#!/usr/bin/env bash
set -Eeuo pipefail

device_id="${1:-}"
command -v kdeconnect-sms >/dev/null 2>&1 || exit 127
if [[ -n "$device_id" ]]; then
    nohup kdeconnect-sms --device "$device_id" >/dev/null 2>&1 &
else
    nohup kdeconnect-sms >/dev/null 2>&1 &
fi
exit 0
