#!/bin/bash

# Messages go through the menu's gettext catalog (domain ohmychadwm-menu); English is the fallback.
export TEXTDOMAIN=ohmychadwm-menu
TEXTDOMAINDIR="$(dirname "$(readlink -f "$0")")/../menu/locale"
export TEXTDOMAINDIR
if command -v gettext &>/dev/null; then
    _t() { gettext "$1"; }
else
    _t() { printf '%s' "$1"; }
fi

if pgrep -x "fastcompmgr" > /dev/null; then
    notify-send "Fastcompmgr" "$(_t "Stopping compositor…")"
    killall fastcompmgr
    exit 0
fi

# kill picom if running before starting fastcompmgr
if pgrep -x "picom" > /dev/null; then
    killall picom
    sleep 0.3
fi

notify-send "Fastcompmgr" "$(_t "Starting compositor…")"
fastcompmgr -c -C &
