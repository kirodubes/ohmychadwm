#!/bin/sh
# =============================================================================
# run.sh — ohmychadwm session startup script
#
# This file is executed by your display manager or startx to launch the
# full ohmychadwm desktop session. It starts all background services,
# then enters the window manager loop at the bottom.
#
# To autostart your own apps, add:  run "your-app"
# To stop an autostart entry, comment it out with #
# =============================================================================

# run() — start a program only if it is not already running.
# run.sh runs once per session login (via exec-ohmychadwm); Super+Shift+R only
# re-execs the ohmychadwm binary in the loop at the bottom, not this autostart
# section. The exact-match (-x) pgrep on the 15-char process name avoids false
# "already up" hits from loose substring matching, so no per-app special-casing.
run() {
  if ! pgrep -x "$(basename "$1" | head -c 15)" >/dev/null; then
    "$@" &
  fi
}

# ── Backup original app configs (one-time, before ohmychadwm first modifies them)
bash "$HOME/.config/ohmychadwm/scripts/backup-originals.sh"

# ── Default home folders ────────────────────────────────────────────────────────
# Create the standard XDG user dirs (Desktop, Downloads, Documents, …) the same
# way XFCE does on login. Reads /etc/xdg/user-dirs.defaults and is idempotent:
# it only creates missing folders and won't restore ones you deleted on purpose.
command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update

# ── Monitor layout ────────────────────────────────────────────────────────────
# Apply a saved arandr/xrandr screen layout named after the current user.
# Generate your layout with arandr, save it to ~/.screenlayout/<username>.sh
# Uncomment the xrandr line below if you are running inside VirtualBox.
#run xrandr --output Virtual-1 --primary --mode 1920x1080 --pos 0x0 --rotate normal
# screen layout generated with arandr
[ -f "$HOME/.screenlayout/$(whoami).sh" ] && sh "$HOME/.screenlayout/$(whoami).sh"

# ── System tray applets ───────────────────────────────────────────────────────
#run signal-in-tray                                   # Signal Desktop tray icon
run nm-applet                                         # NetworkManager wifi/eth tray
run pamac-tray                                        # Manjaro/Arch package manager tray
#run variety                                          # Wallpaper rotator (optional)
run flameshot                                         # Screenshot tool (tray + daemon)
run xfce4-power-manager                               # Battery / display power management
run xfce4-clipman                                     # Clipboard manager
run blueberry-tray                                    # Bluetooth manager tray
# Corsair keyboard control (RGB + remap) — only if the package is installed.
# run()'s exact-match pgrep -x now tells the ckb-next GUI from ckb-next-daemon,
# so the old manual guard is gone.
command -v ckb-next >/dev/null 2>&1 && run ckb-next --background
run /usr/lib/xfce4/notifyd/xfce4-notifyd              # Desktop notification daemon
run /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1  # Polkit auth popups (sudo GUI)

# ── Compositor ────────────────────────────────────────────────────────────────
# Provides transparency, shadows and smooth window rendering.
# Switch between fastcompmgr (lightweight) and picom (feature-rich) here.
# Only one compositor should run at a time.
run fastcompmgr -c
#run picom --config ~/.config/ohmychadwm/picom/picom.conf

# ── Keyboard ──────────────────────────────────────────────────────────────────
run numlockx on                                       # Enable numlock on login
# sxhkd reads keybindings from sxhkdrc and executes them independently of dwm.
# Edit ~/.config/ohmychadwm/sxhkd/sxhkdrc to add or change keybindings.
sxhkd -c ~/.config/ohmychadwm/sxhkd/sxhkdrc &

# ── Volume control ────────────────────────────────────────────────────────────
run volctl                                            # PipeWire/PulseAudio volume tray

# ── Wallpaper ─────────────────────────────────────────────────────────────────
# Restore the last wallpaper set by feh (saved to ~/.fehbg automatically).
# Falls back to the default ohmychadwm wallpaper if no history exists yet.
if [ -f "$HOME/.fehbg" ]; then
    sh "$HOME/.fehbg" &
else
    feh --bg-scale ~/.config/ohmychadwm/wallpapers/kiro-swirl.png &
fi

# ── Cloud sync ────────────────────────────────────────────────────────────────
#run insync start                                     # Google Drive sync (optional)

# ── Status bar ────────────────────────────────────────────────────────────────
# slstatus writes system info (time, CPU, RAM, …) to the dwm bar via XSetRoot.
# Configure what is shown in ~/.config/ohmychadwm/slstatus/config.def.h
run slstatus

# ── Claude assistant terminal ─────────────────────────────────────────────────
# Open an Alacritty window in Kiro-HQ and drop straight into Claude Code.
# fish -i -C claude keeps an interactive shell around, so the window survives
# claude exiting. The pgrep guard prevents a duplicate window only if run.sh is
# re-run while claude is already up (it does not re-run on Super+Shift+R).
# Only auto-launch on the "hq" host — other machines skip it.
if [ "$(hostname)" = "hq" ] && ! pgrep -x claude >/dev/null; then
    alacritty --working-directory "$HOME/Insync/Kiro/Kiro-HQ" \
              -e fish -i -C claude &
fi

# ── Window manager loop (with crash guard) ────────────────────────────────────
# Normal exits are preserved:
#   exit 0           → Super+Shift+R restart → relaunch ohmychadwm.
#   exit !0 (uptime) → Super+Shift+Q logout  → end the session.
# Crash guard: a fatal config/build error exits the same way a logout does
# (dwm's die() returns EXIT_FAILURE, like quit()), so *uptime* — not the exit
# code — is what tells a crash-on-launch from a deliberate logout. If ohmychadwm
# dies within MIN_UPTIME seconds it is counted as a crash; after MAX_CRASHES we
# stop relaunching and open a terminal, so you land in a usable X session to run
# `rebuild` / `kiro-skell` instead of being locked out in an autologin loop.
# stderr is captured to session.log for diagnosis.
LOG_DIR="$HOME/.cache/ohmychadwm"
SESSION_LOG="$LOG_DIR/session.log"
MIN_UPTIME=5
MAX_CRASHES=3
mkdir -p "$LOG_DIR"
: > "$SESSION_LOG"
crashes=0

while type ohmychadwm >/dev/null 2>&1; do
    start=$(date +%s)
    ohmychadwm 2>> "$SESSION_LOG"
    code=$?
    uptime=$(( $(date +%s) - start ))

    if [ "$code" -eq 0 ]; then
        crashes=0
        continue                          # Super+Shift+R restart
    fi

    if [ "$uptime" -ge "$MIN_UPTIME" ]; then
        break                             # ran a while → deliberate logout
    fi

    crashes=$((crashes + 1))
    printf '%s ohmychadwm exited %s after %ss — crash %s/%s\n' \
        "$(date '+%F %T')" "$code" "$uptime" "$crashes" "$MAX_CRASHES" >> "$SESSION_LOG"

    if [ "$crashes" -ge "$MAX_CRASHES" ]; then
        for term in alacritty xterm; do
            command -v "$term" >/dev/null 2>&1 || continue
            "$term" -e sh -c 'printf "\n  ohmychadwm failed to start (see log below).\n\n  >>> Type:  rebuild      to restore the config + recompile <<<\n      or:    kiro-skell   to just restore the config\n\n  Crash log: ~/.cache/ohmychadwm/session.log\n\n"; exec "${SHELL:-sh}"'
            break
        done
        break
    fi
done
