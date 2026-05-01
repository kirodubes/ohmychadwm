# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**ohmychadwm** is an X11 desktop environment built on chadwm (a patched dwm fork). It ships as the `ohmychadwm-git` package from the Nemesis repo. The repo contains: compiled C source for the WM and status bar, bash scripts, config files, and 43 color themes. It is deployed by copying `/etc/skel/.config/ohmychadwm/` to `~/.config/ohmychadwm/` on first login.

## Build commands

All builds happen inside the config directories, not the repo root.

```bash
# Rebuild chadwm (window manager)
cd etc/skel/.config/ohmychadwm/chadwm
make && sudo make install

# Rebuild slstatus (status bar)
cd etc/skel/.config/ohmychadwm/slstatus
make && sudo make install

# Convenience rebuild script (prompts for reboot)
bash etc/skel/.config/ohmychadwm/chadwm/rebuild.sh
```

Apply changes at runtime: `Super+Shift+R` restarts ohmychadwm without rebooting.

## Architecture

### Config → compile → run flow

dwm (and slstatus) are configured entirely via C header files — no runtime config parsing. The flow is:

1. Edit `config.def.h` (or a `themes/*.h` file)
2. `make` copies `config.def.h` → `config.h`, compiles
3. `sudo make install` puts the binary in `/usr/local/bin/ohmychadwm`

**Never edit `config.h` directly** — it is overwritten by `make`.

### Theme system

Themes live in `etc/skel/.config/ohmychadwm/chadwm/themes/*.h`. Each is a C header defining color constants and `THEME_*` macros (gaps, font, layout, tags, etc.). The active theme is set via `#include "themes/dracul.h"` inside `config.def.h`. Changing theme = changing that include line + rebuild.

Theme macros of note:
- `THEME_LAYOUT` — default tiling layout (13 options, e.g. `LAYOUT_DWINDLE`)
- `THEME_TAGS` — workspace label style (e.g. `TAGS_NERD`, `TAGS_ROMAN`)
- `THEME_GAPS`, `THEME_BORDER`, `THEME_MFACT` — geometry defaults
- `THEME_TOPBAR`, `THEME_SHOWSYSTRAY`, `THEME_AUTOHIDE` — bar behavior

### Applied patches (compiled into dwm)

vanity gaps, barpadding, status2d, colorful tags, winicon, tag preview, movestack, fibonacci layouts, gaplessgrid, bottomstack, preserveonrestart, dragmfact.

Patch source files are in `etc/skel/.config/ohmychadwm/chadwm/patches/` and included via `config.def.h` or directly compiled into `dwm.c`.

### Session startup

`usr/bin/exec-ohmychadwm` is the display manager entry point. It calls `scripts/run.sh`, which:
- Loads arandr display layout
- Starts tray applets, compositor (picom or fastcompmgr), sxhkd, slstatus
- Restores wallpaper via feh
- Enters the ohmychadwm loop (keeps WM alive across `Super+Shift+R` restarts)

### Keyboard shortcuts — two daemons

Shortcuts come from two sources:
- **dwm keybindings**: defined in `config.def.h` `keys[]` array (compiled in)
- **sxhkd keybindings**: `etc/skel/.config/ohmychadwm/sxhkd/sxhkdrc` (hot-reloadable, F1–F12 app launchers live here)

### System menu

`Super+Alt+Space` opens a hierarchical rofi menu defined in `etc/skel/.config/ohmychadwm/menu/ohmychadwm-menu.sh`. User extensions go in `menu/menu-extension.sh`.

## Key files to edit for common tasks

| Task | File |
|------|------|
| Change theme | `chadwm/config.def.h` — the `#include "themes/X.h"` line |
| Add/change WM keybinding | `chadwm/config.def.h` — `keys[]` array |
| Add/change app shortcut | `sxhkd/sxhkdrc` |
| Change status bar modules | `slstatus/config.def.h` |
| Change compositor settings | `picom/picom.conf` |
| Change autostart apps | `scripts/run.sh` |
| Add menu entry | `menu/ohmychadwm-menu.sh` or `menu/menu-extension.sh` |
| Create/edit theme | `chadwm/themes/<name>.h` |

## Scripts

All scripts in `scripts/` and `chadwm/` start with `set -euo pipefail` (or should). Key ones:

- `scripts/generate-chadwm-theme.sh` — generates a new `.h` theme from wallpaper colors
- `scripts/generate-theme-previews.sh` — renders 1024×768 PNG previews for all themes
- `scripts/preview-theme.sh` — ANSI preview for fzf picker
- `up.sh` — copies README + previews, commits, pushes (Erik's publish workflow)

## Packaging note

The repo mirrors what gets installed on Kiro Linux. The `etc/skel/` path maps to `/etc/skel/` on the target system. Files under `usr/` map to `/usr/`. Do not restructure this layout — package scripts depend on it.
