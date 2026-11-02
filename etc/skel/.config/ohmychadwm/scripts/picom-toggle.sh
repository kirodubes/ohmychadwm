#!/bin/bash

# Messages go through the menu's gettext catalog (domain ohmychadwm-menu); English is the fallback.
export TEXTDOMAIN=ohmychadwm-menu
TEXTDOMAINDIR="$(dirname "$(readlink -f "$0")")/../menu/locale"
export TEXTDOMAINDIR
if command -v gettext &>/dev/null && command -v gettext.sh &>/dev/null; then
    _t() { gettext "$1"; }
    # shellcheck source=/dev/null
    . gettext.sh
    _tf() { eval_gettext "$1"; }
else
    _t() { printf '%s' "$1"; }
    _tf() { local _s="$1"; eval "printf '%s' \"${_s//\"/\\\"}\""; }
fi

CONFIG_DIR="$HOME/.config/ohmychadwm/picom"

if pgrep -x "picom" > /dev/null; then
    notify-send "Picom" "$(_t "Stopping picom…")"
    killall picom
    exit 0
fi

# kill fastcompmgr if running before starting picom
if pgrep -x "fastcompmgr" > /dev/null; then
    killall fastcompmgr
    sleep 0.3
fi

# Get list of .conf files (basename only)
options=$(basename -a "$CONFIG_DIR"/*.conf)

# Use rofi to prompt the user
chosen=$(echo "$options" | rofi -dmenu -p "$(_t "Choose picom config:")")

if [[ -n "$chosen" && -f "$CONFIG_DIR/$chosen" ]]; then
    # TRANSLATORS: $chosen is the name of a picom config file, e.g. picom.conf
    notify-send "Picom" "$(_tf 'Starting picom with: $chosen')"
    picom -b --config "$CONFIG_DIR/$chosen" &
else
    notify-send "Picom" "$(_t "No valid selection made.")"
fi
