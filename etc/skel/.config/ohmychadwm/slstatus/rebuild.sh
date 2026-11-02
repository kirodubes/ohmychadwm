#!/bin/bash

make clean
# Stop on a failed build: restarting slstatus would only keep the old binary and hide the error.
if ! make; then
    echo
    echo "Build failed — nothing was installed. Fix the error above and run rebuild.sh again."
    make clean
    exit 1
fi
sudo make install || { echo "Install failed."; make clean; exit 1; }
make clean

pkill slstatus
sleep 1
slstatus &
