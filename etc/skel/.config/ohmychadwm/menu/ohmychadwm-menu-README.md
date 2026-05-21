# ohmyohmychadwm-menu

A hierarchical system menu for **ohmychadwm / X11**, inspired by Omarchy's `omarchy-menu`.
Renders via **rofi** (the X11 equivalent of Omarchy's Walker).

---

## Quick start

```bash
# 1. Install hard dependencies
sudo pacman -S rofi libnotify fastcompmgr maim slop xclip fzf

# 2. Put the script on your PATH
install -Dm755 ohmychadwm-menu ~/.local/bin/ohmychadwm-menu

# 3. Create the ohmychadwm config directory
mkdir -p ~/.config/ohmychadwm

# 4. Launch it
ohmychadwm-menu
```

## Keybinding (sxhkd)

```
super + alt + space
    ohmychadwm-menu
```

Or in your chadwm `config.h` / startup script, bind `Super+Alt+Space` to `ohmychadwm-menu`.

## Polybar module

```ini
[module/ohmychadwm-menu]
type         = custom/text
content      = 
click-left   = ohmychadwm-menu
click-right  = ohmychadwm-menu system
```

## Direct submenu access

Jump straight to a submenu — useful for extra keybindings:

```bash
ohmychadwm-menu screenshot      # take a screenshot immediately
ohmychadwm-menu screenrecord    # open screen-record menu
ohmychadwm-menu lock            # lock screen immediately
ohmychadwm-menu system          # power menu only
ohmychadwm-menu install         # install menu only
ohmychadwm-menu toggle          # toggle menu (nightlight, polybar, autolock)
ohmychadwm-menu ai              # AI tools submenu
```

## Configuration

Create `~/.config/ohmychadwm/menu.conf` to override defaults:

```bash
TERMINAL=alacritty        # or ghostty, kitty, xterm, urxvt
EDITOR=nvim               # or vim, emacs, nano, code
BROWSER=firefox           # or chromium, brave, qutebrowser
MENU_WIDTH=300            # rofi menu width in px
```

## Directory layout

```
~/.config/ohmychadwm/
├── menu.conf           # optional user overrides (TERMINAL, EDITOR, etc.)
├── menu-extension.sh   # optional: override/extend any menu function
├── keybindings.txt     # shown by Learn > Keybindings
├── autostart.sh        # edited by Setup > Autostart
├── themes/             # themes for Style > Theme
│   └── my-theme/
│       ├── colors.Xresources
│       └── alacritty-colors.toml
├── wallpapers/         # images for Style > Wallpaper
├── hooks/
│   ├── theme-set       # runs after a theme is applied ($1 = theme name)
│   └── font-set        # runs after a font is set ($1 = font family)
```

### ohmychadwm floating window rule for the present_terminal

Add to your `config.h` rules array so install/update progress windows float:

```c
/* class           instance  title  tags  isfloating  iscentered  monitor */
{ "OhmychadwmPresent", NULL,     NULL,  0,    1,          1,          -1 },
```

## Extending the menu

Create `~/.config/ohmychadwm/menu-extension.sh`. Any function you define there
**replaces** the function of the same name in the main script.
Any new function you add can be called from overridden menus.

```bash
# Example: override show_install_menu to add your own section
show_install_menu() {
    case $(menu "Install" "󰣇 Package\n󰣇 AUR package\n My custom tools") in
        *Package*)      present_terminal 'pacman -Slq | fzf | xargs -ro sudo pacman -S --needed' ;;
        *AUR*)          present_terminal 'yay -Slq | fzf | xargs -ro yay -S' ;;
        *"custom tools"*) show_my_custom_tools ;;
        *)              go_back ;;
    esac
}

show_my_custom_tools() {
    case $(menu "My tools" " Tool A\n Tool B") in
        *"Tool A"*) present_terminal "tool-a --setup" ;;
        *"Tool B"*) notify-send "ohmychadwm" "Tool B launched" ;;
        *)          go_back ;;
    esac
}
```

## X11 ↔ Wayland substitutions made

| Omarchy (Wayland)       | This script (X11)                 |
|-------------------------|-----------------------------------|
| `walker -dmenu`         | `rofi -dmenu`                     |
| `grim` + `slurp`        | `maim` + `slop`                   |
| `wl-copy` / `wl-paste`  | `xclip -selection clipboard`      |
| `hyprpicker`            | `xcolor`                          |
| `wf-recorder`           | `ffmpeg -f x11grab`               |
| `waybar` signals        | polybar IPC / `pkill -SIGUSR1`    |
| `hyprctl dispatch`      | `xdotool` / direct WM control     |
| `swayosd`               | `fastcompmgr -c` + `notify-send`  |
| `hypridle` + `hyprlock` | `xautolock` + `slock` / `i3lock`  |
| `hyprsunset`            | `redshift`                        |
| `setsid gtk-launch`     | `setsid xdg-open` / direct launch |
