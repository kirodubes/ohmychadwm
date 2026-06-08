# Changelog

## 2026.06.08

### What Changed
- Rebound `Super + F9` from `lollypop` to `virt-manager` in the sxhkd config (committed earlier today) and regenerated the keybindings cheatsheet to match. This change is ohmychadwm-only — the other Kiro TWMs still bind `Super + F9` to their own app (mostly `lollypop`).

### Technical Details
- Updated `Super + F9` in both `keybindings-azerty.txt` and `keybindings-qwerty.txt` (the F9 app launchers live in the shared sxhkd layer, identical across layouts), then copied the active AZERTY variant over `keybindings.txt` (shipped default, `KIRO_AZERTY true`). Re-rendered `keybindings.html` + `keybindings.pdf` via `kiro-keybindings-html.py`. Generated cheatsheets are a pure transform of the `.txt` — never hand-edited.

### Files Modified
- `etc/skel/.config/ohmychadwm/keybindings.txt`
- `etc/skel/.config/ohmychadwm/keybindings-azerty.txt`
- `etc/skel/.config/ohmychadwm/keybindings-qwerty.txt`
- `etc/skel/.config/ohmychadwm/keybindings.html`
- `etc/skel/.config/ohmychadwm/keybindings.pdf`

## 2026.06.02

### What Changed
- **AZERTY ⇄ QWERTY switching for ohmychadwm.** chadwm is compiled dwm — its keybindings live in `config.def.h`, not a runtime config — so the rest of the Kiro ecosystem's startup auto-detection approach (kiro-bspwm/kiro-qtile detect `be` via `setxkbmap -query`) does not apply. Instead a single compile-time toggle `#define KIRO_AZERTY true|false` selects the tag, gap-resize, view-all and focus-monitor keysyms (only those differ between layouts), and a one-command switch script flips it and rebuilds. Ships AZERTY by default (Erik's build); QWERTY for the rest of the world.
- Added `.bin/ohmychadwm-keyboard-layout` — toggles AZERTY⇄QWERTY (or `azerty`/`qwerty` to force, `--dry-run` to preview): flips the `#define`, recompiles + `sudo make install`s the WM, swaps the matching keybindings cheatsheet, and prompts for `Super+Shift+R`.
- Added a **Keyboard layout** entry to the rofi system menu (Style → Customise) so users can switch without the CLI, alongside the other config-editing entries (Tags/Border/Gaps).
- Generated `keybindings-azerty.txt` / `keybindings-qwerty.txt` cheatsheet variants; the switch script copies the active one over `keybindings.txt`.
- Documented the AZERTY↔QWERTY switch for end users in the config-dir `README.md` (new "Keyboard layout" section: why it matters, the menu route, the `ohmychadwm-keyboard-layout` CLI, and the distinction between the WM binding layout and the system keymap).
- Fixed a stale `README.md` keybinding reference: the cheatsheet opener is `Super + Ctrl + S` (the universal Kiro hotkey), not the old `Super + K` — the table and the prose under it were never updated when the binding moved on 2026.06.01.
- Aligned `scripts/run.sh` to the canonical [TWM autostart standard](/home/erik/Insync/Kiro/Kiro-HQ/AUTOSTART_TEMPLATE.md) `run()` — ohmychadwm is the gold-standard file, but it was still using the older loose `run()` (`pgrep $1`), the one place the reference diverged from the rule it inspired. Now matches.
- Dropped the `ckb-next` special-case workaround: the loose `pgrep` used to false-match `ckb-next-daemon`, which forced a manual `! pgrep -x ckb-next` guard. The robust `run()` (exact-match `pgrep -x`) distinguishes the GUI from the daemon, so ckb-next is now a normal guarded `run` call (`command -v ckb-next … && run ckb-next --background`).

### Technical Details
- `config.def.h`: `#if KIRO_AZERTY` block defines `KEY_TAG0..8`, `KEY_GAP_IH/IV/OH/OV`, `KEY_VIEWALL`, `KEY_FOCUSMON_NEXT` as AZERTY keysyms (`XK_ampersand`, `XK_eacute`, …, `XK_agrave`, `XK_semicolon`); the `#else` branch maps them to QWERTY (`XK_1`..`XK_9`, `XK_0`, `XK_period`). `TAGKEYS()` and the gap/view/focusmon bindings reference the `KEY_*` macros so the same `keys[]` array serves both layouts. Local `true`/`false` macros are guarded with `#ifndef`. Verified both branches compile cleanly (`make` AZERTY → OK, flipped to QWERTY → OK) in a throwaway copy.
- `ohmychadwm-keyboard-layout` follows the standard bash template; `swap_cheatsheet` warns (not fails) if a variant cheatsheet is missing. Validated with `bash -n`.
- `menu/ohmychadwm-menu.sh`: new `show_keyboard_layout_menu` mirrors `_apply_border` (edit → rebuild in terminal) but delegates to the switch script via `$HOME/.bin/ohmychadwm-keyboard-layout <target>`, run in alacritty for the sudo prompt. Validated with `bash -n`.
- `run()` → `if ! pgrep -x "$(basename "$1" | head -c 15)" >/dev/null; then "$@" &`. Because it now uses quoted `"$@"`, all `run "…"` calls were **unquoted** to canonical style (`run nm-applet`, `run numlockx on`, …) — the two-word `run "numlockx on"` would otherwise have been treated as a single command name and failed.
- No behavior change to which apps autostart; AZERTY default, slstatus, and the hq-host Claude terminal are untouched.
- Validated with `sh -n`.

### Files Modified
- etc/skel/.config/ohmychadwm/chadwm/config.def.h
- etc/skel/.bin/ohmychadwm-keyboard-layout
- etc/skel/.config/ohmychadwm/menu/ohmychadwm-menu.sh
- etc/skel/.config/ohmychadwm/keybindings-azerty.txt
- etc/skel/.config/ohmychadwm/keybindings-qwerty.txt
- etc/skel/.config/ohmychadwm/keybindings.txt
- etc/skel/.config/ohmychadwm/README.md
- etc/skel/.config/ohmychadwm/scripts/run.sh

## 2026.06.01

### What Changed
- Repointed the "show keybindings" action to the new **kiro-keybindings** app (a slick PySide6/QML
  searchable cheatsheet) instead of the local `scripts/show-keybindings.sh` rofi script. The opener
  is `Super + Ctrl + S` — the universal cheatsheet hotkey shared across all Kiro tiling window
  managers ("S" = Shortcuts; AZERTY-safe). The Learn / Trigger / System menu "Keybindings" entries
  also launch `kiro-keybindings`.
- Removed the old `super + k → kiro-keybindings` block from `sxhkd/sxhkdrc`, so `super + k` reverts
  to its native chadwm meaning.
- `scripts/show-keybindings.sh` is intentionally left in place as a no-dependency fallback (not deleted).

### Technical Details
- `sxhkd/sxhkdrc`: added `super + ctrl + s` → `kiro-keybindings` and removed the previous
  `super + k` → `kiro-keybindings` binding (super+k now falls back to chadwm's native action).
- `menu/ohmychadwm-menu.sh`: the three `*Keybindings*)` cases now call `kiro-keybindings`.
- `keybindings.txt`: fully regenerated via `/kiro-keybindings-all-twms` — now lists
  `super + ctrl + s → kiro-keybindings` under Applications & Launchers, with no `super + k` opener.
- kiro-keybindings ships from `nemesis_repo`.

### Files Modified
- etc/skel/.config/ohmychadwm/sxhkd/sxhkdrc
- etc/skel/.config/ohmychadwm/menu/ohmychadwm-menu.sh
- etc/skel/.config/ohmychadwm/keybindings.txt

## 2026.05.31

### What Changed
- Fixed a name-leakage / breakage bug: the pristine chadwm template `config.def.h.default` hardcoded `/home/erik` in the right-click root menu spawn, while the live `config.def.h` already used `~`. Because `config.def.h.default` is the template that lands in `/etc/skel` and is copied verbatim into every new user's home, the menu binding was broken for any user not named `erik` (it pointed at a non-existent `/home/erik/...` path). Caught by the `/kiro-syscheck` step-19 runtime name-leakage scan on a Kiro install.

### Technical Details
- `chadwm/config.def.h.default` line 238: `ohmychadwm_menu[]` changed `"/home/erik/.config/ohmychadwm/menu/ohmychadwm-menu.sh"` → `"~/.config/ohmychadwm/menu/ohmychadwm-menu.sh"`, matching `config.def.h`. `/bin/sh -c` performs tilde expansion to `$HOME`, so it resolves correctly for any user. `config.h` left untouched (regenerated by `make`).

### Files Modified
- etc/skel/.config/ohmychadwm/chadwm/config.def.h.default

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
