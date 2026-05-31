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
# section. The pgrep guard is defensive: it avoids duplicates only if run.sh is
# ever launched again while these processes are still alive.
run() {
 if ! pgrep $1 ;
  then
    $@&
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
#run "signal-in-tray"                                  # Signal Desktop tray icon
run "nm-applet"                                       # NetworkManager wifi/eth tray
run "pamac-tray"                                      # Manjaro/Arch package manager tray
#run "variety"                                         # Wallpaper rotator (optional)
run "flameshot"                                       # Screenshot tool (tray + daemon)
run "xfce4-power-manager"                             # Battery / display power management
run "xfce4-clipman"                                   # Clipboard manager
run "blueberry-tray"                                  # Bluetooth manager tray
# Corsair keyboard control (RGB + remap) — only start if the package is installed.
# Note: can't use run() here — its `pgrep ckb-next` (loose substring) matches the
# already-running `ckb-next-daemon` and falsely concludes the GUI is up. Use -x.
command -v ckb-next >/dev/null 2>&1 && ! pgrep -x ckb-next >/dev/null && ckb-next --background &
run "/usr/lib/xfce4/notifyd/xfce4-notifyd"           # Desktop notification daemon
run "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"  # Polkit auth popups (sudo GUI)

# ── Compositor ────────────────────────────────────────────────────────────────
# Provides transparency, shadows and smooth window rendering.
# Switch between fastcompmgr (lightweight) and picom (feature-rich) here.
# Only one compositor should run at a time.
run fastcompmgr -c
#run picom --config ~/.config/ohmychadwm/picom/picom.conf

# ── Keyboard ──────────────────────────────────────────────────────────────────
run "numlockx on"                                     # Enable numlock on login
# sxhkd reads keybindings from sxhkdrc and executes them independently of dwm.
# Edit ~/.config/ohmychadwm/sxhkd/sxhkdrc to add or change keybindings.
sxhkd -c ~/.config/ohmychadwm/sxhkd/sxhkdrc &

# ── Volume control ────────────────────────────────────────────────────────────
run "volctl"                                          # PipeWire/PulseAudio volume tray

# ── Wallpaper ─────────────────────────────────────────────────────────────────
# Restore the last wallpaper set by feh (saved to ~/.fehbg automatically).
# Falls back to the default ohmychadwm wallpaper if no history exists yet.
if [ -f "$HOME/.fehbg" ]; then
    sh "$HOME/.fehbg" &
else
    feh --bg-scale ~/.config/ohmychadwm/wallpapers/kiro-swirl.png &
fi

# ── Cloud sync ────────────────────────────────────────────────────────────────
#run "insync start"                                    # Google Drive sync (optional)

# ── Status bar ────────────────────────────────────────────────────────────────
# slstatus writes system info (time, CPU, RAM, …) to the dwm bar via XSetRoot.
# Configure what is shown in ~/.config/ohmychadwm/slstatus/config.def.h
run "slstatus"

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

# ── Window manager loop ───────────────────────────────────────────────────────
# Keeps restarting ohmychadwm as long as it exits with code 0 (Super+Shift+R).
# Exits the session when ohmychadwm exits with a non-zero code (Super+Shift+Q).
while type ohmychadwm >/dev/null; do ohmychadwm && continue || break; done
