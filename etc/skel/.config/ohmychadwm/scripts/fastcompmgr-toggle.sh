#!/bin/bash

if pgrep -x "fastcompmgr" > /dev/null; then
    notify-send "Fastcompmgr" "Stopping compositor..."
    killall fastcompmgr
    exit 0
fi

# kill picom if running before starting fastcompmgr
if pgrep -x "picom" > /dev/null; then
    killall picom
    sleep 0.3
fi

notify-send "Fastcompmgr" "Starting compositor..."
fastcompmgr -c -C &
