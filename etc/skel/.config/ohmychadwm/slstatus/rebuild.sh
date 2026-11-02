#!/bin/bash

# One rebuild at a time: a second rebuild's "make clean" would delete this one's object files.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/slstatus-rebuild.lock"
if ! flock -n 9; then
    echo "Waiting for the other rebuild to finish…"
    flock 9
fi

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
exec 9>&-

pkill slstatus
sleep 1
slstatus &
