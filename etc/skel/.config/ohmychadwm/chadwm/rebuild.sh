#!/bin/bash

# One rebuild at a time: two menu choices in quick succession start two rebuilds, and the
# second one's "make clean" deleted the first one's object files halfway through its build.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/ohmychadwm-rebuild.lock"
if ! flock -n 9; then
    echo "Waiting for the other rebuild to finish…"
    flock 9
fi

make clean
# Stop on a failed build: installing or rebooting would only keep the old binary and hide the error.
if ! make; then
    echo
    echo "Build failed — nothing was installed. Fix the error above and run rebuild.sh again."
    make clean
    exit 1
fi
sudo make install || { echo "Install failed."; make clean; exit 1; }
make clean
exec 9>&-

echo
if [[ -t 0 ]]; then
    read -rp "Do you want to reboot? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
        systemctl reboot
    fi
fi
