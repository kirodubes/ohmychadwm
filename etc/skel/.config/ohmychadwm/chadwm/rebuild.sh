#!/bin/bash

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

echo
if [[ -t 0 ]]; then
    read -rp "Do you want to reboot? [Y/n] " answer
    if [[ "${answer:-Y}" =~ ^[Yy]$ ]]; then
        systemctl reboot
    fi
fi
