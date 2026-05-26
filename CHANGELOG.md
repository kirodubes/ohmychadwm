# Changelog

## 2026.05.26

### What Changed
- Added a unified `super + g` keybinding to toggle **fastcompmgr** (the default compositor), matching the binding used across the other Kiro window managers. picom is intentionally kept here — ohmychadwm remains dual-compositor — so `super + p` still toggles picom.
- Relabeled the mislabeled `#Picom Toggle` comment on the `ctrl + alt + o` → `opera` binding to `#Opera` (it never toggled picom).

### Technical Details
- Created `scripts/fastcompmgr-toggle.sh` — a start/stop toggle that kills picom first (mutual exclusion, mirroring `picom-toggle.sh`) so only one compositor runs at a time.
- `sxhkd/sxhkdrc`: added the `#Compositor Toggle (fastcompmgr)` block on `super + g`; kept the `#Picom Toggle` block on `super + p`; `#Opera` relabel.

### Files Modified
- etc/skel/.config/ohmychadwm/scripts/fastcompmgr-toggle.sh (created)
- etc/skel/.config/ohmychadwm/sxhkd/sxhkdrc

## 2026.05.25

### What Changed
- De-brand (user-visible): the `Print` screenshot binding in `sxhkdrc` saved files
  as `ArcoLinux-<date>_screenshot.jpg`. Changed the prefix to `Kiro-`. Part of the
  ecosystem-wide arcolinux de-brand sweep.

### Files Modified
- `etc/skel/.config/ohmychadwm/sxhkd/sxhkdrc`

## 2026.05.21

### What Changed
- Added the four other required markdown scaffold files (created stubs for whichever of `IDEAS.md` / `TODO.md` / `CLAUDE.md` were missing) per the new ecosystem MD-scaffold rule codified in [Kiro-HQ/CLAUDE.md](/home/erik/Insync/Kiro/Kiro-HQ/CLAUDE.md#required-markdown-scaffold-every-repo). README was already substantial; left untouched.

### Files Modified
- CHANGELOG.md
- IDEAS.md (created where missing)
- TODO.md (created where missing)
- CLAUDE.md (created where missing)

## 2026.05.21

**What Changed**
Ported the ckb-next (Corsair keyboard) autostart line from the live `~/.config/ohmychadwm/` into the EDU skel mirror so new installs launch ckb-next when the package is installed.

**Technical Details**
Added a guarded one-liner in `scripts/run.sh` right after `blueberry-tray`. Bypasses the local `run()` helper because `pgrep ckb-next` (loose substring) matches the already-running `ckb-next-daemon` and falsely concludes the GUI is up — uses `pgrep -x ckb-next` instead. Whole line is gated by `command -v ckb-next` so it's a silent no-op on machines without the package.

**Files Modified**
- etc/skel/.config/ohmychadwm/scripts/run.sh

## 2026.05.01

**What Changed**
Added CLAUDE.md to provide Claude Code with architectural context for this repository.

**Technical Details**
Documents the config→compile→run flow (dwm uses C headers, not runtime config), the two-daemon keybinding split (dwm keys compiled in, sxhkd hot-reloadable), the theme system (43 `.h` files included at compile time), and a quick-reference table for common edit targets.

**Files Modified**
- CLAUDE.md (created)
- CHANGELOG.md (created)
