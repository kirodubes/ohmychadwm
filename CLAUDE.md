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

| Task                       | File                                                     |
|----------------------------|----------------------------------------------------------|
| Change theme               | `chadwm/config.def.h` — the `#include "themes/X.h"` line |
| Add/change WM keybinding   | `chadwm/config.def.h` — `keys[]` array                   |
| Add/change app shortcut    | `sxhkd/sxhkdrc`                                          |
| Change status bar modules  | `slstatus/config.def.h`                                  |
| Change compositor settings | `picom/picom.conf`                                       |
| Change autostart apps      | `scripts/run.sh`                                         |
| Add menu entry             | `menu/ohmychadwm-menu.sh` or `menu/menu-extension.sh`    |
| Create/edit theme          | `chadwm/themes/<name>.h`                                 |

## Scripts

All scripts in `scripts/` and `chadwm/` start with `set -euo pipefail` (or should). Key ones:

- `scripts/generate-chadwm-theme.sh` — generates a new `.h` theme from wallpaper colors
- `scripts/generate-theme-previews.sh` — renders 1024×768 PNG previews for all themes
- `scripts/preview-theme.sh` — ANSI preview for fzf picker
- `up.sh` — copies README + previews, commits, pushes (Erik's publish workflow)

## Tests

`bash tests/check.sh` (about 1 minute; `--quick` skips the 46 theme builds) — run it after any change to the menu,
config.def.h, a theme or slstatus. `up.sh` runs it before every push and blocks the push on a failure.

- Lints every `.sh`, builds chadwm against every theme and `config.def.h.default`, builds slstatus with every module on.
- `tests/theme_gen.py [--quick] [--out dir]` runs `generate-chadwm-theme.sh` in throwaway homes on synthetic
  wallpapers (dark, bright, grey, neon, 16-bit, one colour) plus every shipped wallpaper, answering its questions by
  matching the yellow question line. It checks the written theme, config.def.h, the chadwm build and text contrast
  (title and status text 3:1, tags 2:1). Themes, previews and `overview.png` are kept in
  `~/.cache/ohmychadwm/theme-gen/<time>/`; `--recover <dir> [--as name]` installs one into the real config, listed
  but not active. check.sh step 6 runs it (`--quick` there = synthetic wallpapers only).
- Showcase scripts for videos live in `usr/share/ohmychadwm/showcase/` (packaged as `/usr/share/ohmychadwm/showcase/`,
  never in skel: they are not user config). Not part of check.sh.
  - `showcase-languages.sh [-t] [-k] [-i sec] [-s dir]` shows the menu in every shipped language on the running
    session; `-t` tours Appearance/Theme/search/Setup/Windows per language, `-s` saves every step, `variety -n` per
    language unless `-k`.
  - `showcase-themes.sh [-i sec] [-k] [theme …]` switches theme, rebuilds chadwm in a visible terminal, installs it
    and restarts chadwm live per theme, then goes back to the starting theme unless `-k`. One sudo prompt at the
    start; over ssh set `SUDO_ASKPASS`.
- `tests/menu_crawl.py` clicks every row of the system menu in a throwaway home with a stub rofi. System commands are
  recorder stubs on an allowlisted PATH, so nothing touches the machine; terminal commands and rebuilds run for real.
  A row fails on errors, critical notifications, a ✓/✗ row that does not flip, or a value menu where no choice changes
  a setting before the rebuild.
- `SCENARIOS` in `menu_crawl.py` chain several menu trips in one home and check the end state (e.g. Border 10 →
  Back to default must restore the border). Add one whenever a bug only shows across two actions.
- Menu rows dispatch on keys from `pick`; never match on a label (labels are translated).
- Tags, border, gaps, smart gaps, systray, bar position and master area are `THEME_*` defines in the active theme;
  change them with `_set_theme_define`, never by editing the `config.def.h` lines that read them.

## Translations (system menu)

- Every user-visible menu string goes through `_t "Text"` or, with a value in it, `_tf 'Text with $var'`
  (gettext's `eval_gettext`: whole sentence, translators can move `$var`). Text shown inside a terminal command
  is exported as an `OHM_MSG_*` / `OHM_T_*` variable first, never spliced into the command.
- `scripts/picom-toggle.sh` and `scripts/fastcompmgr-toggle.sh` share the menu's catalog (same domain, `_t`/`_tf`,
  `TEXTDOMAINDIR` = `../menu/locale`); `po/make-mo.sh` extracts from them too. A new translated script joins the same way.
- After changing menu text run `bash po/make-mo.sh`: it rebuilds `po/ohmychadwm-menu.pot`, merges the 13
  `po/<lang>.po` and compiles `etc/skel/.config/ohmychadwm/menu/locale/<lang>/LC_MESSAGES/ohmychadwm-menu.mo`.
  New or changed strings show as untranslated/fuzzy until translated; English is the fallback.
- Rules, registers and the review step: `~/Insync/Kiro/Kiro-HQ/TRANSLATIONS/README.md` (ROADMAP §4 row 13).
- Keys of `pick` rows double as hidden English search words (rofi `meta`), so keep them readable English.

## Packaging note

The repo mirrors what gets installed on Kiro Linux. The `etc/skel/` path maps to `/etc/skel/` on the target system. Files under `usr/` map to `/usr/`. Do not restructure this layout — package scripts depend on it.
