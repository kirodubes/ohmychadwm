# ohmychadwm

A fully configured, keyboard-driven X11 desktop built on top of [Chadwm](https://github.com/siduck/chadwm), a fork from **dwm** (Dynamic Window Manager). We started with the code from ArcoLinux - arcolinux-chadwm package and we let us inspire by Omarchy.

Inspired by [omarchy](https://github.com/basecamp/omarchy) (Wayland/Hyprland) — ported to X11.

Even [Dusk](https://github.com/bakkeby/dusk) was at some point an inspiration to include extra functionalities.

---

## What is OMYCHADWM?

`ohmychadwm` is a complete desktop environment configuration, not just a window manager built for and on Kiro.
Kiro can be downloaded on [Sourceforge](https://sourceforge.net/projects/kiro/files/).

It combines:

| Component | Role |
| --- | --- |
| **ohmychadwm** (patched chadwm) | Tiling window manager — manages windows |
| **slstatus** | Status bar — shows time, CPU, RAM, network etc. |
| **sxhkd** | Keybinding daemon — Super/Ctrl/Alt shortcuts |
| **rofi** | App launcher + hierarchical system menu |
| **picom / fastcompmgr** | Compositor — transparency, shadows |
| **feh** | Wallpaper manager |
| **variety** | Wallpaper fetcher/manager |
| **alacritty** | Terminal emulator |

---

## Requirements

```bash
# Core (required)
sudo pacman -S base-devel libx11 libxft libxinerama imlib2 \
               rofi feh sxhkd alacritty picom notify-send xclip \
               maim slop fzf btop ncdu inxi lm_sensors

# Fonts — install at least one Nerd Font
yay -S ttf-jetbrains-mono-nerd

# Optional but recommended
sudo pacman -S redshift xautolock numlockx volctl flameshot \
               nm-applet xfce4-power-manager blueberry
```

---

## Install & Start

### 1. Add the Nemesis repository

Add the following to `/etc/pacman.conf` (before the `[core]` section or at the end):

```ini
[nemesis_repo]
SigLevel = Never
Server = https://erikdubois.github.io/$repo/$arch
```

### 2. Update and install

```bash
sudo pacman -Syu
sudo pacman -S ohmychadwm-git
```

Logout and log into ohmychadwm with sddm or other display managers.

---

## Rebuild after config changes

Any change to `chadwm/config.def.h` or a theme file requires a recompile:

```bash
cd ~/.config/ohmychadwm/chadwm
./rebuild.sh
```

or just type "rebuild" in a terminal

The rebuild script copies `config.def.h` → `config.h`, compiles, installs, and restarts the WM.

---

## Keyboard layout (AZERTY ↔ QWERTY)

ohmychadwm ships with an **AZERTY (Belgian)** layout by default. If you use a
**QWERTY** keyboard (most of the world), the workspace keys won't line up — on
QWERTY you want `Super + 1..9` to switch tags, but the AZERTY build listens for
`Super + & é " ' (` instead. Switching the layout fixes that.

**Only a few keys differ** between the two layouts — the number-row tag keys
(`Super + 1..9`), the gap-resize keys, the "view all tags" key, and the
next-monitor key. Every other shortcut is identical.

### Switch from AZERTY to QWERTY (the easy way)

Open the system menu (`Super + Alt + Space`) → **Style → Customise → Keyboard
layout**, then pick **QWERTY**. A terminal opens, rebuilds the window manager
(it asks for your password — this is the `sudo make install` step), and swaps
the keybindings cheatsheet to match.

When it finishes, press **`Super + Shift + R`** to reload ohmychadwm. Done — your
tag keys are now `Super + 1..9`.

### Switch from the terminal

```bash
ohmychadwm-keyboard-layout qwerty   # force QWERTY
ohmychadwm-keyboard-layout azerty   # force AZERTY (back to default)
ohmychadwm-keyboard-layout          # just toggle to the other one
ohmychadwm-keyboard-layout --dry-run qwerty   # preview, change nothing
```

The script flips `#define KIRO_AZERTY` in `config.def.h`, recompiles + installs
the WM, and swaps the cheatsheet. Press `Super + Shift + R` afterwards to apply.

> **Note — two different "layouts".** This switch only changes which keys
> ohmychadwm *listens for*. It does **not** change what your keyboard physically
> *types*. To change the system keymap as well (so the keys produce the right
> characters in apps), use the menu → **Update → keyboard layout**, or run
> `setxkbmap us` (QWERTY) / `setxkbmap be` (Belgian AZERTY).

---

## Key bindings (most important)

| Key | Action |
| --- | --- |
| `Super + Enter` | Open terminal |
| `Super + Shift + Enter` | Open thunar |
| `Super + 1..9` | Switch to tag/workspace |
| `Super + Shift + Q` | Quit window |
| `Super + Shift + R` | Restart ohmychadwm (reload config) |
| `Super + Alt + Space` | Open ohmychadwm system menu |
| `Super + D` | Open rofi app launcher |
| `Super + Ctrl + S` | Open the keybindings cheatsheet |

Full keybinding list: press `Super + Ctrl + S` or open the menu → Learn → Keybindings — both launch the **kiro-keybindings** searchable cheatsheet.

---

## Themes

Themes are `.h` files in `chadwm/themes/`. Switch via the menu (rebuilds automatically) or manually edit `config.def.h` and run `./rebuild.sh`.

We have 43 themes or create one more on the fly with our theme generator.

### Preview gallery

#### Default

| | | |
| :---: | :---: | :---: |
| ![catppuccin](previews/catppuccin.png) | ![dracula](previews/dracula.png) | ![dracul](previews/dracul.png) |
| **catppuccin** | **dracula** | **dracul** |
| ![everforest](previews/everforest.png) | ![gruvchad](previews/gruvchad.png) | ![onedark](previews/onedark.png) |
| **everforest** | **gruvchad** | **onedark** |
| ![prime](previews/prime.png) | ![tokyonight](previews/tokyonight.png) | ![tundra](previews/tundra.png) |
| **prime** | **tokyonight** | **tundra** |

#### Nord family

| | | |
| :---: | :---: | :---: |
| ![nord](previews/nord.png) | ![nord-polarnight](previews/nord-polarnight.png) | ![nord-snowstorm](previews/nord-snowstorm.png) |
| **nord** | **nord-polarnight** | **nord-snowstorm** |
| ![nord-frost](previews/nord-frost.png) | ![nord-aurora](previews/nord-aurora.png) | |
| **nord-frost** | **nord-aurora** | |

#### Other dark themes

| | | |
| :---: | :---: | :---: |
| ![kanagawa](previews/kanagawa.png) | ![monokai](previews/monokai.png) | ![rosepine](previews/rosepine.png) |
| **kanagawa** | **monokai** | **rosepine** |
| ![material](previews/material.png) | ![solarized](previews/solarized.png) | |
| **material** | **solarized** | |

#### Stellar

| | | |
| :---: | :---: | :---: |
| ![jupiter](previews/jupiter.png) | ![saturn](previews/saturn.png) | ![mars](previews/mars.png) |
| **jupiter** | **saturn** | **mars** |
| ![venus](previews/venus.png) | ![mercury](previews/mercury.png) | ![neptune](previews/neptune.png) |
| **venus** | **mercury** | **neptune** |
| ![uranus](previews/uranus.png) | ![pluto](previews/pluto.png) | |
| **uranus** | **pluto** | |

#### African (bottom bar, zero gaps)

| | | |
| :---: | :---: | :---: |
| ![buffalo](previews/buffalo.png) | ![hippo](previews/hippo.png) | ![rhino](previews/rhino.png) |
| **buffalo** | **hippo** | **rhino** |

#### Custom

| | | |
| :---: | :---: | :---: |
| ![bright](previews/bright.png) | ![clonewar](previews/clonewar.png) | ![doors](previews/doors.png) |
| **bright** | **clonewar** | **doors** |
| ![dragon](previews/dragon.png) | ![drwho](previews/drwho.png) | ![faraway](previews/faraway.png) |
| **dragon** | **drwho** | **faraway** |
| ![goodnight](previews/goodnight.png) | ![lookinto](previews/lookinto.png) | ![spiderwoman](previews/spiderwoman.png) |
| **goodnight** | **lookinto** | **spiderwoman** |
| ![starwars](previews/starwars.png) | ![summit](previews/summit.png) | ![tiger](previews/tiger.png) |
| **starwars** | **summit** | **tiger** |
| ![venom](previews/venom.png) | | |
| **venom** | | |

---

### Switch theme via menu

`Style → ohmychadwm → Theme`

### Switch theme manually

Edit `chadwm/config.def.h` — uncomment the theme you want:

```c
//#include "themes/catppuccin.h"
#include "themes/dracula.h"      // ← active theme
//#include "themes/nord.h"
```

Then run `./rebuild.sh`.

### Create your own theme

```bash
~/.config/ohmychadwm/scripts/generate-chadwm-theme.sh
```

The script extracts colors from your current wallpaper and generates a complete `.h` theme file.

Or run it from the menu in Style/Chadwm

### Theme parameters

Each theme `.h` file can define these values (all have sensible defaults if omitted):

| Parameter | Default | Description |
| --- | --- | --- |
| `THEME_TOPBAR` | `1` | Bar position: 1 = top, 0 = bottom |
| `THEME_GAPS` | `5` | Gap size between windows (px) |
| `THEME_BORDER` | `2` | Window border width (px) |
| `THEME_AUTOHIDE` | `0` | Auto-hide bar after N seconds (0 = off) |
| `THEME_SHOWSYSTRAY` | `1` | Show system tray: 1 = yes, 0 = no |
| `THEME_SMARTGAPS` | `0` | Remove gaps with single window: 1 = yes |
| `THEME_MFACT` | `0.50` | Master area width (0.10–0.90) |
| `THEME_NMASTER` | `1` | Number of windows in master area |
| `THEME_FONT` | `JetBrainsMono Nerd Font Mono` | Bar font family |
| `THEME_FONTSTYLE` | `Bold` | Bar font style |
| `THEME_FONTSIZE` | `13` | Bar font size (pt) |
| `THEME_ICONSIZE` | `18` | Bar icon size (pt) |
| `THEME_TAGS` | `TAGS_NERD` | Tag label style — see options below |
| `THEME_LAYOUT` | `LAYOUT_DWINDLE` | Default layout on startup — see options below |

**Tag style options for `THEME_TAGS`:**

| Constant | Labels |
| --- | --- |
| `TAGS_NERD` | Nerd Font icons (default) |
| `TAGS_ARABIC` | 1 2 3 4 5 6 7 8 9 10 |
| `TAGS_ROMAN` | I II III IV V VI VII VIII IX X |
| `TAGS_POWERLINE` | Powerline glyphs |
| `TAGS_WEBDINGS` | Web Chat Edit Meld Vb Mail Video Image Files Music |
| `TAGS_JAPANESE` | 一 二 三 四 五 六 七 八 九 十 |
| `TAGS_ALPHA` | A B C D E F G H I J |
| `TAGS_EMOJI` | 👨‍💻 🌐 🖥️ 📟 📜 👋 📺 ✉️ 💬 🎮 |
| `TAGS_GEOMETRIC` | ● ■ ▲ ◆ ◇ ★ ✗ ✓ + ○ |
| `TAGS_CHINESE` | 壹 贰 叁 肆 伍 陆 柒 捌 玖 拾 |
| `TAGS_PURPOSE` | home chat surf media game remote code mail files misc |

**Layout options for `THEME_LAYOUT`:**

| Constant | Symbol | Description |
| --- | --- | --- |
| `LAYOUT_DWINDLE` | `[\\]` | Fibonacci dwindle (default) |
| `LAYOUT_TILE` | `[]=` | Master + stack |
| `LAYOUT_SPIRAL` | `[@]` | Fibonacci spiral |
| `LAYOUT_DECK` | `H[]` | Master + tabbed stack |
| `LAYOUT_BSTACK` | `TTT` | Bottom stack |
| `LAYOUT_BSTACKH` | `===` | Bottom stack horizontal |
| `LAYOUT_GRID` | `HHH` | Grid |
| `LAYOUT_NROWGRID` | `###` | N-row grid |
| `LAYOUT_HORIZGRID` | `---` | Horizontal grid |
| `LAYOUT_GAPLESS` | `:::` | Gapless grid |
| `LAYOUT_CENTER` | `\|M\|` | Centered master |
| `LAYOUT_CFLOAT` | `>M>` | Centered floating master |
| `LAYOUT_FLOAT` | `><>` | Floating |

The `SchemeMenufg` color from the active theme is automatically synced to the rofi menu accent color (`ac:` in `ohmychadwm-menu.rasi`) when you switch themes.

---

## System Menu

Open with `Super + Alt + Space`.

```text
ohmychadwm
├── Apps          — rofi app launcher
├── Style
│   ├── ohmychadwm  — theme, tags, gaps, border, font …
│   ├── Alacritty   — terminal color scheme
│   ├── Wallpaper   — browse and set wallpapers
│   ├── Slstatus    — toggle bar modules
│   ├── Picom       — compositor config
│   └── Menu theme  — edit the rofi menu theme
├── Learn         — keybindings, Arch Wiki, Fish, Bash, man pages
├── Trigger
│   ├── Capture     — screenshot, region, screen record, color picker
│   ├── Toggle      — night light, auto-lock, picom, fastcompmgr
│   └── Keybindings — searchable cheatsheet (kiro-keybindings)
├── Setup         — sxhkd, slstatus config
├── Install       — apps, browser, dev tools, AI tools, fonts, gaming
├── Remove        — packages, dev environments
├── Update        — system, AUR, full update, keyboard layout, time sync
├── Info
│   ├── System      — inxi full hardware info
│   ├── Btop        — process manager
│   ├── Disk overview — df sorted
│   ├── Disk explorer — ncdu interactive
│   ├── Temperatures  — lm_sensors
│   ├── Battery     — upower battery info (laptops)
│   ├── Logs        — journalctl / dmesg viewer
│   └── Keybindings — searchable cheatsheet (kiro-keybindings)
└── System        — lock, suspend, restart, shutdown
```

### Extending the menu

Edit `menu/menu-extension.sh` to override any built-in menu function or add new ones.
The extension file is sourced automatically at startup.

---

## Status bar (slstatus)

Edit which modules are shown in `slstatus/config.def.h` — uncomment any block (CPU, RAM, network speed, etc.), then rebuild:

```bash
cd ~/.config/ohmychadwm/slstatus && ./rebuild.sh
```

The status text color comes from `SchemeNormfg` in the active theme.

---

## Autostart apps

Edit `scripts/run.sh`. Add your app with the `run` helper so it only starts once:

```sh
run "your-application"
```

---

## Patches included

| Patch | Effect |
| --- | --- |
| vanity gaps | Configurable inner/outer gaps |
| barpadding | Padding inside the bar |
| status2d | Per-block colors in the status bar |
| colorful tags | Each tag gets its own color |
| winicon | Window icons in the title bar |
| tag preview | Hover a tag to preview its windows |
| movestack | Move windows up/down in the stack |
| fibonacci | Fibonacci tiling layout |
| gaplessgrid | Grid layout without gaps |
| bottomstack | Stack below master |
| preserveonrestart | Windows stay on their tags after restart |
| dragmfact | Drag the master area border with mouse |

---

## Directory structure

```text
~/.config/ohmychadwm/
├── chadwm/               # Window manager source + build
│   ├── config.def.h      # Main WM configuration (edit this)
│   ├── themes/           # Color themes (.h files)
│   ├── rebuild.sh        # Recompile + reinstall + restart
│   └── dwm.c             # Core WM source (rarely needs editing)
├── scripts/
│   ├── run.sh                    # Session startup — autostart apps here
│   ├── generate-chadwm-theme.sh  # Create a theme from wallpaper colors
│   ├── generate-theme-previews.sh # Generate 1024×768 PNG previews for all themes
│   ├── preview-theme.sh          # ANSI color preview used by the fzf theme picker
│   └── show-keybindings.sh       # Legacy rofi keybindings viewer — kept as a no-dependency fallback (Super+K now opens kiro-keybindings)
├── menu/
│   ├── ohmychadwm-menu.sh        # Hierarchical system menu
│   ├── ohmychadwm-menu.rasi      # Rofi theme for the menu
│   └── menu-extension.sh         # User overrides / additions
├── slstatus/             # Status bar source + config
│   ├── config.def.h      # Enable/disable bar modules here
│   └── rebuild.sh        # Recompile slstatus
├── sxhkd/
│   └── sxhkdrc           # All keyboard shortcuts
├── rofi/                 # App launcher themes
├── picom/                # Compositor configs
├── alacritty/            # Terminal themes (230+)
├── previews/             # 1024×768 PNG theme preview images
└── wallpapers/           # Wallpaper images (named <theme>.jpg to auto-restore)
```

---

## License

MIT/X Consortium License — see [LICENSE](LICENSE).
Originally from [suckless.org/dwm](https://dwm.suckless.org) © Anselm R Garbe and contributors.

---

## Credits & Inspirations

| Project | What we took from it |
| --- | --- |
| [dwm](https://dwm.suckless.org) | The window manager this is built on |
| [chadwm](https://github.com/siduck/chadwm) by siduck | Original patched dwm base, themes, status2d coloring |
| [omarchy](https://github.com/basecamp/omarchy) by Basecamp | Menu system design, workflow philosophy, script structure |
| [dusk](https://github.com/bakkeby/dusk) by bakkeby | Patch reference, dragcfact implementation |
| [rofi themes](https://github.com/adi1090x/rofi) by Aditya Shakya | launcher2.rasi base design |
| [suckless slstatus](https://tools.suckless.org/slstatus/) | Status bar |
