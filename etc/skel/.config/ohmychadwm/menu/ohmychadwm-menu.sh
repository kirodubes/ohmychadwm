#!/usr/bin/env bash
# =============================================================================
# ohmychadwm-menu — hierarchical system menu for ohmychadwm / X11
# Inspired by omarchy-menu (basecamp/omarchy), ported from Wayland to X11.
#
# Dependencies:
#   rofi          — menu renderer  (pacman -S rofi)
#   fastcompmgr   — compositor     (pacman -S fastcompmgr)
#   notify-send   — part of libnotify
#   xclip         — clipboard      (pacman -S xclip)
#   maim + slop   — screenshots    (pacman -S maim slop)
#   xcolor        — colour picker  (pacman -S xcolor)  [optional]
#   xdotool       — window control (pacman -S xdotool) [optional]
#   xdg-open      — open URLs / files
#   pacman / yay  — package management
#   fzf           — edit  finder   (pacman -S fzf)
#   redshift      — night light    (pacman -S redshift) [optional]
#   xautolock     — idle lock      (pacman -S xautolock) [optional]
#   slock / i3lock — screen locker [optional]
#
# Install path: put this file somewhere on your PATH, e.g. ~/.local/bin/ohmychadwm-menu
# Make executable: chmod +x ~/.local/bin/ohmychadwm-menu
#
# ohmychadwm keybinding (add to your config.h or scripts/keybindings.sh):
#   Super + Alt + Space  →  ohmychadwm-menu
#   Super + Alt + Space  →  ohmychadwm-menu screenshot   (jump straight in)
#
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# User-tuneable settings — override in ~/.config/ohmychadwm/menu.conf if present
# ---------------------------------------------------------------------------
TERMINAL="${TERMINAL:-alacritty}"
EDITOR="${EDITOR:-nano}"
# Detect installed browser — use $BROWSER if already set, otherwise find first available
if [[ -z "${BROWSER:-}" ]]; then
    for _b in firefox chromium brave-browser qutebrowser epiphany midori; do
        if command -v "$_b" &>/dev/null; then
            BROWSER="$_b"
            break
        fi
    done
    BROWSER="${BROWSER:-xdg-open}"  # xdg-open as last resort
fi
PRESENT_FONT_SIZE="${PRESENT_FONT_SIZE:-14}"
MENU_WIDTH="${MENU_WIDTH:-40}"

# ohmychadwm config root
OHMYCHADWM_CONFIG="${HOME}/.config/ohmychadwm"

# Rofi theme — defaults to ohmychadwm-menu.rasi next to this script,
# then falls back to ~/.config/rofi/ohmychadwm-menu.rasi
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROFI_THEME="${ROFI_THEME:-}"
if [[ -z "$ROFI_THEME" ]]; then
    if [[ -f "${_SCRIPT_DIR}/ohmychadwm-menu.rasi" ]]; then
        ROFI_THEME="${_SCRIPT_DIR}/ohmychadwm-menu.rasi"
    elif [[ -f "${HOME}/.config/rofi/ohmychadwm-menu.rasi" ]]; then
        ROFI_THEME="${HOME}/.config/rofi/ohmychadwm-menu.rasi"
    fi
fi

# Source user overrides if they exist
[[ -f "${OHMYCHADWM_CONFIG}/menu.conf" ]] && source "${OHMYCHADWM_CONFIG}/menu.conf"

# Load user extension (can override any function defined before the source line)
USER_EXTENSION="${OHMYCHADWM_CONFIG}/menu/menu-extension.sh"

# ---------------------------------------------------------------------------
# Back-navigation flag
# When jumping directly to a submenu via CLI (ohmychadwm-menu screenshot),
# pressing Escape exits rather than returning to the parent menu.
# ---------------------------------------------------------------------------
BACK_TO_EXIT=false

go_back() {
    :
}

# ---------------------------------------------------------------------------
# Core helper: menu renderer
# Usage: menu "Prompt" "option1\noption2\noption3" ["extra rofi args"]
# Returns the selected item on stdout; exits/goes-back on cancel.
# ---------------------------------------------------------------------------
menu() {
    local prompt="$1"
    local options="$2"
    local extra="${3:-}"

    local theme_arg=()
    [[ -n "$ROFI_THEME" ]] && theme_arg=(-theme "$ROFI_THEME")

    local choice
    # Capture exit code explicitly — rofi returns 1 on Escape, not an error
    choice=$(echo -e "$options" | rofi -dmenu \
        -p "" \
        -no-show-match \
        -no-fixed-num-lines \
        -cycle \
        "${theme_arg[@]}" \
        ${extra} \
        2>/dev/null) || true

    # Empty result (Escape / no selection) → navigate back or exit
    if [[ -z "$choice" ]]; then
        go_back
        return 1
    fi

    echo "$choice"
}

# ---------------------------------------------------------------------------
# Terminal helpers
# ---------------------------------------------------------------------------

# Launch a plain terminal (for interactive TUI tools)
terminal() {
    setsid "$TERMINAL" "$@" >/dev/null 2>&1 &
    disown
}

# Launch a floating "presentation" terminal for progress output.
# Uses a WM_CLASS so you can set a ohmychadwm floating rule for it:
#   { "OhmychadwmPresent", NULL, NULL, 0, 1, 0, 0, -1 }   ← example rules entry
present_terminal() {
    local cmd="$*"
    setsid "$TERMINAL" \
        --class OhmychadwmPresent \
        -e bash -c "
            echo
            printf '  \e[1m%s\e[0m\n\n' 'ohmychadwm'
            ${cmd}
            echo
            printf '  Press any key to close...'
            read -n1 -s
        " >/dev/null 2>&1 &
    disown
}

# Like present_terminal but closes immediately when the command exits — no keypress prompt.
plain_terminal() {
    local cmd="$*"
    setsid "$TERMINAL" \
        --class OhmychadwmPresent \
        -e bash -c "
            echo
            printf '  \e[1m%s\e[0m\n\n' 'ohmychadwm'
            ${cmd}
        " >/dev/null 2>&1 &
    disown
}

# Open a file in $EDITOR inside a floating terminal
edit_in_editor() {
    local file="$1"
    notify-send -t 2000 "ohmychadwm" "Editing $(basename "$file")"
    present_terminal "${EDITOR} '${file}'"
}

# ---------------------------------------------------------------------------
# Package install helpers
# ---------------------------------------------------------------------------
install() {
    # install "Display Name" "pkg1 pkg2"
    local name="$1"
    local pkgs="$2"
    present_terminal "echo 'Installing ${name}...'; sudo pacman -S --needed --noconfirm ${pkgs} && notify-send 'ohmychadwm' '${name} installed.' || notify-send -u critical 'ohmychadwm' 'Install failed.'"
}

aur_install() {
    # aur_install "Display Name" "aur-pkg"
    local name="$1"
    local pkg="$2"
    present_terminal "echo 'Installing ${name} from AUR...'; yay -S --noconfirm ${pkg} && notify-send 'ohmychadwm' '${name} installed.' || notify-send -u critical 'ohmychadwm' 'AUR install failed.'"
}

remove_pkg() {
    local name="$1"
    local pkgs="$2"
    present_terminal "echo 'Removing ${name}...'; sudo pacman -Rns --noconfirm ${pkgs} && notify-send 'ohmychadwm' '${name} removed.' || notify-send -u critical 'ohmychadwm' 'Remove failed.'"
}

# ===========================================================================
# MENU FUNCTIONS
# ===========================================================================

# ---------------------------------------------------------------------------
# Learn
# ---------------------------------------------------------------------------
show_learn_menu() {
    case $(menu "Learn" " Keybindings\n Arch Wiki\n Chadwm source\n Bash\n Fish shell\n Man pages") in
        *Keybindings*)  kiro-keybindings ;;
        *"Arch Wiki"*)  setsid "$BROWSER" "https://wiki.archlinux.org" >/dev/null 2>&1 & disown ;;
        *Chadwm*)       setsid "$BROWSER" "https://github.com/erikdubois/ohmychadwm" >/dev/null 2>&1 & disown ;;
        *Bash*)         setsid "$BROWSER" "https://devhints.io/bash" >/dev/null 2>&1 & disown ;;
        *Fish*)         setsid "$BROWSER" "https://fishshell.com/" >/dev/null 2>&1 & disown ;;
        *"Man pages"*)  present_terminal "man -k . &>/dev/null || { echo 'Building man database (first run)...'; sudo mandb; }; man -k . | fzf --preview 'man {1}' | awk '{print \$1}' | xargs -r man" ;;
        *)              return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Trigger — Capture / Toggle
# ---------------------------------------------------------------------------
show_trigger_menu() {
    while true; do
        case $(menu "Trigger" " Capture\n Toggle\n Keybindings") in
            *Capture*)      show_capture_menu || continue; return 0 ;;
            *Toggle*)       show_toggle_menu  || continue; return 0 ;;
            *Keybindings*)  kiro-keybindings; return 0 ;;
            *)              return 1 ;;
        esac
    done
}

show_capture_menu() {
    while true; do
        case $(menu "Capture" " Screenshot\n Screenshot → clipboard\n Screenshot region\n Simplescreenrecorder\n Colour picker") in
            *"Screenshot →"*)      _screenshot_clipboard; return 0 ;;
            *"Screenshot region"*) _screenshot_region;    return 0 ;;
            *"Screenshot"*)        _screenshot_smart;     return 0 ;;
            *"Simple"*)            show_screenrecord_menu || continue; return 0 ;;
            *"Colour picker"*)     _colour_picker;        return 0 ;;
            *)                     return 1 ;;
        esac
    done
}

_screenshot_smart() {
    local dir="${HOME}/Pictures/Screenshots"
    mkdir -p "$dir"
    local file="${dir}/$(date +%Y-%m-%d_%H-%M-%S).png"
    maim "$file"
    xclip -selection clipboard -t image/png < "$file"
    # Run in background: --wait blocks until the notification is dismissed or the button clicked
    (
        action=$(notify-send -t 5000 "Screenshot saved" "$(basename "$file")" \
            --action="open=Open in nomacs" --wait 2>/dev/null)
        if [[ "$action" == "open" ]]; then
            if ! command -v nomacs &>/dev/null; then
                notify-send "ohmychadwm" "Installing nomacs..."
                sudo pacman -S --needed --noconfirm nomacs
            fi
            nomacs "$file" &
        fi
    ) &
    disown
}

_screenshot_clipboard() {
    maim | xclip -selection clipboard -t image/png
    notify-send -t 2000 "Screenshot" "Copied to clipboard"
}

_screenshot_region() {
    local dir="${HOME}/Pictures/Screenshots"
    mkdir -p "$dir"
    local file="${dir}/$(date +%Y-%m-%d_%H-%M-%S).png"
    maim -s "$file"
    xclip -selection clipboard -t image/png < "$file"
    notify-send -t 3000 "Region screenshot" "Saved & copied to clipboard"
}

_colour_picker() {
    if command -v xcolor &>/dev/null; then
        local color
        color=$(xcolor)
        echo -n "$color" | xclip -selection clipboard
        notify-send -t 0 "Colour picked" "$color (copied to clipboard)"
    else
        notify-send -u critical "ohmychadwm" "xcolor not installed. Run: sudo pacman -S xcolor"
    fi
}

show_screenrecord_menu() {
    if ! command -v simplescreenrecorder &>/dev/null; then
        notify-send "ohmychadwm" "Installing SimpleScreenRecorder..."
        sudo pacman -S --needed --noconfirm simplescreenrecorder
    fi
    setsid simplescreenrecorder &>/dev/null &
    disown
}


show_toggle_menu() {
    local _nightlight_state="Enable"
    local _autolock_state="Enable"
    local _picom_state="Start"
    local _fastcompmgr_state="Start"

    [[ -f "${HOME}/.local/state/ohmychadwm/toggles/nightlight-on" ]] && _nightlight_state="Disable"
    [[ -f "${HOME}/.local/state/ohmychadwm/toggles/autolock-on" ]]   && _autolock_state="Disable"
    pgrep -x picom       &>/dev/null && _picom_state="Stop"
    pgrep -x fastcompmgr &>/dev/null && _fastcompmgr_state="Stop"

    case $(menu "Toggle" "${_nightlight_state} night light\n ${_autolock_state} auto-lock\n ${_picom_state} picom\n ${_fastcompmgr_state} fastcompmgr") in
        *"night light"*) _toggle_nightlight ;;
        *"auto-lock"*)   _toggle_autolock ;;
        *picom*)         _toggle_picom ;;
        *fastcompmgr*)   _toggle_fastcompmgr ;;
        *)               return 1 ;;
    esac
}

_toggle_picom() {
    if pgrep -x picom &>/dev/null; then
        pkill picom && notify-send "Picom" "Stopped"
    else
        if pgrep -x fastcompmgr &>/dev/null; then
            pkill fastcompmgr 2>/dev/null
            local _i=0; while pgrep -x fastcompmgr &>/dev/null && (( _i++ < 30 )); do sleep 0.1; done
        fi
        setsid picom --config "${HOME}/.config/ohmychadwm/picom/picom.conf" -b &>/dev/null &
        disown
        notify-send "Picom" "Started"
    fi
}

_toggle_fastcompmgr() {
    if pgrep -x fastcompmgr &>/dev/null; then
        pkill fastcompmgr && notify-send "Fastcompmgr" "Stopped"
    else
        if pgrep -x picom &>/dev/null; then
            pkill picom 2>/dev/null
            local _i=0; while pgrep -x picom &>/dev/null && (( _i++ < 30 )); do sleep 0.1; done
        fi
        setsid fastcompmgr -c &>/dev/null &
        disown
        notify-send "Fastcompmgr" "Started"
    fi
}

_toggle_nightlight() {
    local state_file="${HOME}/.local/state/ohmychadwm/toggles/nightlight-on"
    mkdir -p "$(dirname "$state_file")"
    if [[ -f "$state_file" ]]; then
        pkill redshift 2>/dev/null; rm -f "$state_file"
        notify-send "Night light" "Disabled"
    else
        if ! command -v redshift &>/dev/null; then
            notify-send "ohmychadwm" "Installing redshift..."
            sudo pacman -S --needed --noconfirm redshift
        fi
        touch "$state_file"
        redshift -O 4000 &>/dev/null &
        disown
        notify-send "Night light" "Enabled (4000K)"
    fi
}

_toggle_autolock() {
    local state_file="${HOME}/.local/state/ohmychadwm/toggles/autolock-on"
    mkdir -p "$(dirname "$state_file")"
    if [[ -f "$state_file" ]]; then
        pkill xautolock 2>/dev/null; rm -f "$state_file"
        notify-send "Auto-lock" "Disabled"
    else
        touch "$state_file"
        xautolock -time 10 -locker betterlockscreen -l dim -- --time-str="%H:%M" &>/dev/null &
        disown
        notify-send "Auto-lock" "Enabled (10 min)"
    fi
}

# ---------------------------------------------------------------------------
# Style
# ---------------------------------------------------------------------------
show_style_menu() {
    while true; do
        case $(menu "Style" " Ohmychadwm\n Alacritty\n Slstatus\n Wallpaper\n Apply font globally\n Hard Reset") in
            *Ohmychadwm*)           show_chadwm_menu        || continue; return 0 ;;
            *Alacritty*)            show_alacritty_menu     || continue; return 0 ;;
            *Wallpaper*)            show_wallpaper_menu     || continue; return 0 ;;
            *Slstatus*)             show_slstatus_menu      || continue; return 0 ;;

            *"Apply font globally"*) present_terminal "bash ${OHMYCHADWM_CONFIG}/scripts/apply-font-globally.sh"; return 0 ;;
            *"Hard Reset"*)          present_terminal "bash ${OHMYCHADWM_CONFIG}/scripts/backup-originals.sh --restore"; return 0 ;;
            *)                      return 1 ;;
        esac
    done
}


show_slstatus_menu() {
    local config="${OHMYCHADWM_CONFIG}/slstatus/config.def.h"
    local -a names=(datetime uptime cpu_perc disk_free disk_used hostname kernel_release load_avg netspeed_rx netspeed_tx ram_free ram_perc ram_used swap_free swap_perc)
    local -A labels=(
        [datetime]="Date & time"
        [uptime]="Uptime"
        [cpu_perc]="CPU usage %"
        [disk_free]="Disk free"
        [disk_used]="Disk used"
        [hostname]="Hostname"
        [kernel_release]="Kernel"
        [load_avg]="Load average"
        [netspeed_rx]="Net download speed"
        [netspeed_tx]="Net upload speed"
        [ram_free]="RAM free"
        [ram_perc]="RAM usage %"
        [ram_used]="RAM used"
        [swap_free]="Swap free"
        [swap_perc]="Swap usage %"
    )

    local selected_row=0

    while true; do
        local options=""
        for name in "${names[@]}"; do
            if grep -qP "^\s*\{\s*${name}," "$config"; then
                options+="✓ ${labels[$name]}\n"
            else
                options+="✗ ${labels[$name]}\n"
            fi
        done
        options+=" Apply & rebuild"

        local chosen
        chosen=$(menu "slstatus" "$options" "-lines 16 -selected-row ${selected_row}") || return 1

        if [[ "$chosen" == *"Apply"* ]]; then
            selected_row=$(( ${#names[@]} ))
            (cd "${OHMYCHADWM_CONFIG}/slstatus" && alacritty -e bash -c './rebuild.sh; exec bash')
            notify-send "ohmychadwm" "slstatus updated"
            return 0
        fi

        for i in "${!names[@]}"; do
            local name="${names[$i]}"
            if [[ "$chosen" == *"${labels[$name]}"* ]]; then
                selected_row=$i
                if grep -qP "^\s*\{\s*${name}," "$config"; then
                    sed -i "s|^\(\s*\){ ${name},|\1//{ ${name},|" "$config"
                else
                    sed -i "s|^\(\s*\)//{ ${name},|\1{ ${name},|" "$config"
                fi
                break
            fi
        done
    done
}

_random_theme() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local -a themes
    mapfile -t themes < <(grep -oP '(?<=themes/)[^"]+(?=\.h")' "$config")
    local current
    current=$(grep -oP '(?<=^#include "themes/)[^"]+(?=\.h")' "$config" | head -1)
    # filter out current theme so we always get something different
    local -a candidates=()
    for t in "${themes[@]}"; do
        [[ "$t" != "$current" ]] && candidates+=("$t")
    done
    local pick="${candidates[RANDOM % ${#candidates[@]}]}"
    notify-send "ohmychadwm" "Random theme: $pick"
    _apply_theme "$pick"
}

show_chadwm_menu() {
    while true; do
        case $(menu "chadwm" " Choose theme\n Create your own theme\n Delete theme\n Customise\n Random theme") in
            *Choose*)           show_theme_menu        || continue; return 0 ;;
            *"Delete theme"*)   show_delete_theme_menu || continue; return 0 ;;
            *"Create your own theme"*) setsid "$TERMINAL" -e bash -c "${OHMYCHADWM_CONFIG}/scripts/generate-chadwm-theme.sh; exec bash" >/dev/null 2>&1 & return 0 ;;
            *Customise*)        show_customise_menu    || continue; return 0 ;;
            *"Random theme"*)   _random_theme; return 0 ;;
            *)                  return 1 ;;
        esac
    done
}

_customise_reset_defaults() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local default="${OHMYCHADWM_CONFIG}/chadwm/config.def.h.default"
    present_terminal "bash -c '
        config=\"${config}\"
        default=\"${default}\"

        if [[ ! -f \"\$default\" ]]; then
            echo \"ERROR: \$default not found.\"
            exit 1
        fi

        echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
        echo \"  Reset chadwm config to default\"
        echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
        echo \"\"
        echo \"  This will overwrite:\"
        echo \"    \$config\"
        echo \"  with:\"
        echo \"    \$default\"
        echo \"\"
        echo \"  Only the chadwm config is reset.\"
        echo \"  Themes, wallpapers and other settings are untouched.\"
        echo \"\"
        echo \"  A backup will be saved as:\"
        ts=\$(date +%Y%m%d-%H%M%S)
        backup=\"\${config}.\${ts}\"
        echo \"    \$backup\"
        echo \"\"
        read -rp \"  Continue? [y/N] \" ans
        [[ \"\$ans\" =~ ^[Yy]\$ ]] || { echo \"Cancelled.\"; exit 0; }

        cp \"\$config\" \"\$backup\"
        echo \"\"
        echo \"  Backup created.\"
        cp \"\$default\" \"\$config\"
        echo \"  config.def.h restored.\"
        echo \"\"
        cd \"${OHMYCHADWM_CONFIG}/chadwm\" && bash rebuild.sh
    '"
}

show_customise_menu() {
    while true; do
        case $(menu "Customise" " Tags\n Border\n Gaps\n Bar padding\n Bar position\n Smart gaps\n Hide systray\n New window\n Launcher icons\n Master area\n Font\n Keyboard layout\n Back to default") in
            *Tags*)             show_tags_menu         || continue; return 0 ;;
            *Border*)           show_border_menu       || continue; return 0 ;;
            *Gaps*)             show_gaps_menu         || continue; return 0 ;;
            *"Bar padding"*)    show_barpad_menu       || continue; return 0 ;;
            *"Bar position"*)   show_bar_menu          || continue; return 0 ;;
            *"Smart gaps"*)     show_smartgaps_menu    || continue; return 0 ;;
            *"Hide systray"*)   show_systray_menu      || continue; return 0 ;;
            *"New window"*)     show_newwindow_menu    || continue; return 0 ;;
            *"Launcher icons"*) show_launchers_menu    || continue; return 0 ;;
            *"Master area"*)    show_mfact_menu        || continue; return 0 ;;
            *Font*)             show_font_menu         || continue; return 0 ;;
            *"Keyboard layout"*) show_keyboard_layout_menu || continue; return 0 ;;
            *"Back to default"*) _customise_reset_defaults; return 0 ;;
            *)                  return 1 ;;
        esac
    done
}

show_tags_menu() {
    local chosen
    chosen=$(menu "Tags" "default tags\nArabic numbers\nRoman numbers\nPowerline\nWebdings\nJapanese numbers\nAlphabetic\nEmoji\nGeometric shapes\nChinese numbers\nPurposemenu") || return 1
    _apply_tags "$chosen"
}

_apply_tags() {
    local chosen="$1"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"

    python3 - "$chosen" "$config" <<'PYEOF'
import sys, re

chosen = sys.argv[1]
config = sys.argv[2]

with open(config) as f:
    content = f.read()

# Comment out any currently active tags line
content = re.sub(r'^(static char \*tags\[\])', r'//\1', content, flags=re.MULTILINE)

# Uncomment the tags line that immediately follows the matching comment
pattern = r'(//' + re.escape(chosen) + r'\n)//(static char \*tags\[\])'
new_content, n = re.subn(pattern, r'\1\2', content)

if n == 0:
    print(f"No tags entry found for '{chosen}'", file=sys.stderr)
    sys.exit(1)

with open(config, 'w') as f:
    f.write(new_content)
PYEOF

    if [[ $? -ne 0 ]]; then
        notify-send -u critical "ohmychadwm" "Tags '${chosen}' not found in config.def.h"
        return 1
    fi

    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Tags set to '${chosen}'"
}

show_keyboard_layout_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    if grep -qE '^#define KIRO_AZERTY[[:space:]]+true' "$config"; then current=AZERTY; else current=QWERTY; fi
    local chosen
    chosen=$(menu "Keyboard layout (current: ${current})" "AZERTY (Belgian)\nQWERTY (US / world)") || return 1
    local target=azerty
    [[ "$chosen" == QWERTY* ]] && target=qwerty
    # The switch script flips KIRO_AZERTY, recompiles, and swaps the cheatsheet; run it in a terminal for the sudo prompt.
    (alacritty -e bash -c "\$HOME/.bin/ohmychadwm-keyboard-layout ${target}; exec bash")
    notify-send "ohmychadwm" "Keyboard layout: ${target}. Press Super+Shift+R to apply."
}

show_border_menu() {
    local current
    current=$(grep -oP 'borderpx\s*=\s*\K[0-9]+' "${OHMYCHADWM_CONFIG}/chadwm/config.def.h")
    local chosen
    chosen=$(menu "Border (current: ${current}px)" "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10") || return 1
    _apply_border "$chosen"
}

_apply_border() {
    local px="$1"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    sed -i "s/static const unsigned int borderpx\s*=\s*[0-9]\+/static const unsigned int borderpx  = ${px}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Border set to ${px}px"
}

show_gaps_menu() {
    local current
    current=$(grep -oP 'gappih\s*=\s*\K[0-9]+' "${OHMYCHADWM_CONFIG}/chadwm/config.def.h")
    local chosen
    chosen=$(menu "Gaps (current: ${current}px)" "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10") || return 1
    _apply_gaps "$chosen"
}

_apply_gaps() {
    local px="$1"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    sed -i "s/\(gappih\s*=\s*\)[0-9]\+/\1${px}/" "$config"
    sed -i "s/\(gappiv\s*=\s*\)[0-9]\+/\1${px}/" "$config"
    sed -i "s/\(gappoh\s*=\s*\)[0-9]\+/\1${px}/" "$config"
    sed -i "s/\(gappov\s*=\s*\)[0-9]\+/\1${px}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Gaps set to ${px}px"
}

show_barpad_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    while true; do
        local cv ch
        cv=$(grep -oP 'vertpadbar\s*=\s*\K[0-9]+' "$config")
        ch=$(grep -oP 'horizpadbar\s*=\s*\K[0-9]+' "$config")
        case $(menu "Bar padding  vert:${cv}  horiz:${ch}" " Vertical padding\n Horizontal padding\n Back to default") in
            *Vertical*)
                local v
                v=$(menu "Bar vertical padding (current: ${cv})" \
                    "0\n2\n4\n6\n8\n10\n11\n12\n14\n16\n18\n20") || continue
                sed -i "s/\(static const int vertpadbar\s*=\s*\)[0-9]\+/\1${v}/" "$config"
                notify-send "ohmychadwm" "vertpadbar → ${v} — rebuilding..."
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            *Horizontal*)
                local h
                h=$(menu "Bar horizontal padding (current: ${ch})" \
                    "0\n2\n4\n5\n6\n8\n10\n12\n14\n16\n18\n20") || continue
                sed -i "s/\(static const int horizpadbar\s*=\s*\)[0-9]\+/\1${h}/" "$config"
                notify-send "ohmychadwm" "horizpadbar → ${h} — rebuilding..."
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            *"Back to default"*)
                sed -i "s/\(static const int vertpadbar\s*=\s*\)[0-9]\+/\111/" "$config"
                sed -i "s/\(static const int horizpadbar\s*=\s*\)[0-9]\+/\15/" "$config"
                notify-send "ohmychadwm" "Bar padding reset to defaults — rebuilding..."
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            *) return 1 ;;
        esac
    done
}

show_bar_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    current=$(grep -oP 'topbar\s*=\s*\K[01]' "$config")
    local current_label="top"
    [[ "$current" == "0" ]] && current_label="bottom"
    local chosen
    chosen=$(menu "Bar position (current: ${current_label})" "top\nbottom") || return 1
    local value=1
    [[ "$chosen" == "bottom" ]] && value=0
    sed -i "s/\(static const int topbar\s*=\s*\)[01]/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Bar moved to ${chosen}"
}

show_smartgaps_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    current=$(grep -oP 'smartgaps\s*=\s*\K[01]' "$config")
    local current_label="no"
    [[ "$current" == "1" ]] && current_label="yes"
    local chosen
    chosen=$(menu "Smart gaps (current: ${current_label})" "yes\nno") || return 1
    local value=0
    [[ "$chosen" == "yes" ]] && value=1
    sed -i "s/\(static const int smartgaps\s*=\s*\)[01]/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Smart gaps set to ${chosen}"
}

show_systray_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    current=$(grep -oP 'showsystray\s*=\s*\K[01]' "$config")
    local current_label="no"
    [[ "$current" == "1" ]] && current_label="yes"
    local chosen
    chosen=$(menu "Hide systray (currently hidden: ${current_label})" "yes\nno") || return 1
    local value=1
    [[ "$chosen" == "yes" ]] && value=0
    sed -i "s/\(static const int showsystray\s*=\s*\)[01]/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Systray hidden: ${chosen}"
}

show_newwindow_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    current=$(grep -oP 'new_window_attach_on_end\s*=\s*\K[01]' "$config")
    local current_label="on the front"
    [[ "$current" == "1" ]] && current_label="on the end"
    local chosen
    chosen=$(menu "New window (current: ${current_label})" "on the front\non the end") || return 1
    local value=0
    [[ "$chosen" == "on the end" ]] && value=1
    sed -i "s/\(new_window_attach_on_end\s*=\s*\)[01]/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "New windows open ${chosen}"
}

show_mfact_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    current=$(grep -oP 'mfact\s*=\s*\K[0-9.]+' "$config")
    local current_pct
    current_pct=$(printf "%.0f" "$(echo "$current * 100" | bc)")
    local chosen
    chosen=$(menu "Master area (current: ${current_pct}%)" \
        "10%\n20%\n30%\n40%\n50%\n60%\n70%\n80%\n90%") || return 1
    local pct="${chosen/\%/}"
    local value
    value=$(printf "0.%02d" "$pct")
    sed -i "s/\(static const float mfact\s*=\s*\)[0-9.]*/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Master area set to ${chosen}"
}

ALACRITTY_CONF="${HOME}/.config/alacritty/alacritty.toml"
ALACRITTY_THEMES_DIR="${HOME}/.config/ohmychadwm/alacritty/alacritty-themes"
ALACRITTY_DEFAULT_THEME="ohmychadwm-theme.toml"

show_alacritty_menu() {
    while true; do
        case $(menu "Alacritty" " Font family\n Font size\n Opacity\n Theme\n Shell\n Back to default") in
            *"Font family"*)    show_alacritty_font_menu    || continue; return 0 ;;
            *"Font size"*)      show_alacritty_size_menu    || continue; return 0 ;;
            *Opacity*)          show_alacritty_opacity_menu || continue; return 0 ;;
            *Theme*)            show_alacritty_theme_menu   || continue; return 0 ;;
            *Shell*)            show_alacritty_shell_menu   || continue; return 0 ;;
            *"Back to default"*) _alacritty_reset_default  ; return 0 ;;
            *)                  return 1 ;;
        esac
    done
}

_alacritty_apply_colors() {
    local theme_file="$1"
    local colors
    colors=$(sed -n '/^\[colors/,$p' "$theme_file")
    local sep_line
    sep_line=$(grep -n '^###' "$ALACRITTY_CONF" | head -1 | cut -d: -f1)
    {
        echo "$colors"
        echo ""
        tail -n +"${sep_line}" "$ALACRITTY_CONF"
    } > "${ALACRITTY_CONF}.tmp" && mv "${ALACRITTY_CONF}.tmp" "$ALACRITTY_CONF"
}

show_alacritty_theme_menu() {
    local other_themes
    other_themes=$(ls "$ALACRITTY_THEMES_DIR" | grep -v "^${ALACRITTY_DEFAULT_THEME}$" | sort)
    local chosen
    chosen=$(printf "%s\n%s" "$ALACRITTY_DEFAULT_THEME" "$other_themes" | \
        rofi -dmenu -p "Alacritty theme" -width "$MENU_WIDTH" -lines 20 2>/dev/null) || return 1
    _alacritty_apply_colors "${ALACRITTY_THEMES_DIR}/${chosen}"
    notify-send "ohmychadwm" "Alacritty theme set to '${chosen}'"
}

show_alacritty_font_menu() {
    local font_list
    font_list=$(fc-list : family | sort -u)
    local chosen
    chosen=$(echo "$font_list" | rofi -dmenu -p "Alacritty font…" -width "$MENU_WIDTH" -lines 20 2>/dev/null) || return 1
    sed -i "s|^\(family = \).*|\1\"${chosen}\"|" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "Alacritty font set to '${chosen}'"
}

show_alacritty_size_menu() {
    local current
    current=$(grep -oP 'size\s*=\s*\K[0-9.]+' "$ALACRITTY_CONF" | head -1)
    local chosen
    chosen=$(menu "Font size (current: ${current})" \
        "8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n20\n22\n24") || return 1
    sed -i "s/^\(size\s*=\s*\)[0-9.]*/\1${chosen}.0/" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "Alacritty font size set to ${chosen}"
}

show_alacritty_opacity_menu() {
    local current
    current=$(grep -oP 'opacity\s*=\s*\K[0-9.]+' "$ALACRITTY_CONF" | head -1)
    local chosen
    chosen=$(menu "Opacity (current: ${current})" \
        "0.1\n0.2\n0.3\n0.4\n0.5\n0.6\n0.7\n0.8\n0.9\n1.0") || return 1
    sed -i "s/^\(opacity\s*=\s*\)[0-9.]*/\1${chosen}/" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "Alacritty opacity set to ${chosen}"
}

show_alacritty_shell_menu() {
    local current
    current=$(grep -oP 'program\s*=\s*"\K[^"]+' "$ALACRITTY_CONF" | head -1)
    local shell_list
    shell_list=$(grep -v '^#' /etc/shells | grep '^/bin/')
    local chosen
    chosen=$(echo "$shell_list" | rofi -dmenu -p "Shell (current: ${current})" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    sed -i "s|^\(program\s*=\s*\)\"[^\"]*\"|\1\"${chosen}\"|" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "Alacritty shell set to ${chosen}"
}

_alacritty_reset_default() {
    local backup="${HOME}/.config/alacritty/default-arcolinux.toml"
    if [[ ! -f "$backup" ]]; then
        notify-send -u critical "ohmychadwm" "Backup not found: ${backup}"
        return 1
    fi
    cp "$backup" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "Alacritty reset to default"
}

show_launchers_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local -a names=(discord firefox brave opera mintstick pavucontrol telegram vivaldi)
    local -A labels=(
        [discord]="Discord"
        [firefox]="Firefox"
        [brave]="Brave"
        [opera]="Opera"
        [mintstick]="Mintstick"
        [pavucontrol]="Pavucontrol"
        [telegram]="Telegram"
        [vivaldi]="Vivaldi"
    )

    while true; do
        local options=""
        for name in "${names[@]}"; do
            if grep -qP "^\s*\{\s*${name}," "$config"; then
                options+="✓ ${labels[$name]}\n"
            else
                options+="✗ ${labels[$name]}\n"
            fi
        done
        options+=" Apply & rebuild"

        local chosen
        chosen=$(menu "Launcher icons" "$options") || return 1

        if [[ "$chosen" == *"Apply"* ]]; then
            (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
            notify-send "ohmychadwm" "Launcher icons updated"
            return 0
        fi

        for name in "${names[@]}"; do
            if [[ "$chosen" == *"${labels[$name]}"* ]]; then
                if grep -qP "^\s*\{\s*${name}," "$config"; then
                    sed -i "s|^\(\s*\){ ${name},|\1//{ ${name},|" "$config"
                else
                    sed -i "s|^\(\s*\)//{ ${name},|\1{ ${name},|" "$config"
                fi
                break
            fi
        done
    done
}

show_delete_theme_menu() {
    local themes_dir="${OHMYCHADWM_CONFIG}/chadwm/themes"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"

    # built-in themes: any theme registered in config.def.h (commented or not)
    local -a BUILTIN
    mapfile -t BUILTIN < <(grep -oP '(?<=themes/)[^"]+(?=\.h")' "$config")

    # build list of custom (user-created) themes only
    local custom_list=""
    for f in "$themes_dir"/*.h; do
        local name; name=$(basename "$f" .h)
        local is_builtin=0
        for b in "${BUILTIN[@]}"; do
            [[ "$name" == "$b" ]] && is_builtin=1 && break
        done
        if [[ $is_builtin -eq 0 ]]; then
            custom_list+="$name\n"
        fi
    done
    custom_list="${custom_list%\\n}"

    if [[ -z "$custom_list" ]]; then
        notify-send "ohmychadwm" "No custom themes to delete"
        return 1
    fi

    local chosen
    chosen=$(menu "Delete theme" "$custom_list") || return 1

    # confirm
    local confirm
    confirm=$(menu "Delete '$chosen'?" " Yes, delete it\n Cancel") || return 1
    [[ "$confirm" == *"Cancel"* ]] && return 1

    # check if this theme is currently active
    local active
    active=$(grep -oP '(?<=#include "themes/)[^"]+(?=\.h")' "$config" | head -1)

    # remove include line from config.def.h entirely
    sed -i "/[#/]*#\?include \"themes\/${chosen}\.h\"/d" "$config"

    # delete the theme file
    rm -f "${themes_dir}/${chosen}.h"

    # delete associated wallpaper if present
    for ext in jpg jpeg png webp; do
        rm -f "${OHMYCHADWM_CONFIG}/wallpapers/${chosen}.${ext}"
    done

    # if deleted theme was active, fall back to kanagawa
    if [[ "$active" == "$chosen" ]]; then
        notify-send "ohmychadwm" "Active theme deleted — switching to kanagawa"
        _apply_theme "kanagawa"
    else
        notify-send "ohmychadwm" "Theme '$chosen' deleted"
    fi
}

show_theme_menu() {
    local themes_dir="${OHMYCHADWM_CONFIG}/chadwm/themes"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local preview_script="${OHMYCHADWM_CONFIG}/scripts/preview-theme.sh"

    if [[ ! -d "$themes_dir" ]]; then
        notify-send "ohmychadwm" "No themes directory found at ${themes_dir}"
        return 1
    fi

    present_terminal "bash -c '
        chosen=\$(ls -1 \"$themes_dir\"/*.h 2>/dev/null \
            | xargs -n1 basename \
            | sed \"s/\\.h\$//\" \
            | fzf \
                --prompt=\"Theme > \" \
                --layout=reverse \
                --border \
                --ansi \
                --preview=\"bash \\\"$preview_script\\\" {}\" \
                --preview-window=right:45%:wrap \
            2>/dev/null) || exit 0
        [[ -z \"\$chosen\" ]] && exit 0

        # ── font availability check ───────────────────────────────────────────
        theme_font=\$(grep -oP \"#define THEME_FONT\\s+\\\"\\K[^\\\"]+\" \"$themes_dir/\${chosen}.h\" | head -1)
        if [[ -n \"\$theme_font\" ]]; then
            if ! fc-list : family | grep -qi \"\$theme_font\"; then
                echo \"\"
                echo \"  ⚠  Font not installed: \$theme_font\"
                echo \"  Install it first, or the bar will fall back to a system font.\"
                echo \"\"
                read -rp \"  Apply theme anyway? [y/N] \" _fc
                [[ \"\$_fc\" =~ ^[Yy]\$ ]] || exit 0
            fi
        fi

        # deactivate all, activate chosen
        sed -i \"s|^#include \\\"themes/\(.*\)\\.h\\\"|//#include \\\"themes/\1.h\\\"|\" \"$config\"
        sed -i \"s|^//#include \\\"themes/\${chosen}\\.h\\\"|#include \\\"themes/\${chosen}.h\\\"|\" \"$config\"

        # sync rasi accent color — enforce contrast against dark bg (#101010, lum≈16)
        color=\$(grep -oP \"SchemeMenufg\[\]\s*=\s*\\\"\K[^\\\"]+\" \"$themes_dir/\${chosen}.h\" | head -1)
        if [[ -n \"\$color\" ]]; then
            _h=\"\${color#\\#}\"
            _r=\$((16#\${_h:0:2})) _g=\$((16#\${_h:2:2})) _b=\$((16#\${_h:4:2}))
            _lum=\$(( (299*_r + 587*_g + 114*_b) / 1000 ))
            while (( _lum < 120 )); do
                _r=\$(( _r+20 < 255 ? _r+20 : 255 ))
                _g=\$(( _g+20 < 255 ? _g+20 : 255 ))
                _b=\$(( _b+20 < 255 ? _b+20 : 255 ))
                _lum=\$(( (299*_r + 587*_g + 114*_b) / 1000 ))
                (( _r==255 && _g==255 && _b==255 )) && break
            done
            color=\$(printf \"#%02x%02x%02x\" \$_r \$_g \$_b)
            safe=\"\${color//&/\\\\&}\"
            sed -i \"s|ac:.*\\/\\* selected item text.*|ac:     \${safe};   /* selected item text   (synced from SchemeMenufg)  */|\" \
                \"${OHMYCHADWM_CONFIG}/menu/ohmychadwm-menu.rasi\"
        fi

        # restore wallpaper if one exists for this theme
        for ext in jpg jpeg png webp; do
            wp=\"${OHMYCHADWM_CONFIG}/wallpapers/\${chosen}.\${ext}\"
            if [[ -f \"\$wp\" ]]; then feh --bg-fill \"\$wp\" 2>/dev/null; break; fi
        done

        # ── optional font sync ────────────────────────────────────────────────
        theme_file=\"${OHMYCHADWM_CONFIG}/chadwm/themes/\${chosen}.h\"
        t_font=\$(grep -oP \"#define THEME_FONT\\s+\\\"\\K[^\\\"]+\" \"\$theme_file\" | head -1)
        if [[ -n \"\$t_font\" ]]; then
            t_style=\$(grep -oP \"#define THEME_FONTSTYLE\\s+\\\"\\K[^\\\"]+\" \"\$theme_file\" | head -1)
            t_size=\$(grep -oP \"#define THEME_FONTSIZE\\s+\\K[0-9]+\" \"\$theme_file\" | head -1)
            [[ -z \"\$t_style\" ]] && t_style=\"Bold\"
            [[ -z \"\$t_size\"  ]] && t_size=\"13\"
            rofi_font=\"\$t_font \$t_style \$t_size\"
            echo \"\"
            echo \"Theme font: \$rofi_font\"
            echo \"Apply to other apps? (alacritty, kitty, GTK, rofi) [y/N]:\"
            read -rp \"> \" _af
            if [[ \"\$_af\" =~ ^[Yy]\$ ]]; then
                _ala=\"\${HOME}/.config/alacritty/alacritty.toml\"
                if [[ -f \"\$_ala\" ]]; then
                    sed -i \"s|^\(family = \)\\\"[^\\\"]*\\\"|\1\\\"\$t_font\\\"|\" \"\$_ala\"
                    sed -i \"s|^\(size = \)[0-9.]*|\1\${t_size}.0|\" \"\$_ala\"
                fi
                if command -v kitty &>/dev/null; then
                    _kit=\"\${HOME}/.config/kitty/kitty.conf\"
                    if [[ -f \"\$_kit\" ]]; then
                        sed -i \"s|^font_family.*|font_family      \$t_font|\" \"\$_kit\"
                        sed -i \"s|^font_size.*|font_size        \${t_size}.0|\" \"\$_kit\"
                    fi
                fi
                for _gtk in \"\${HOME}/.config/gtk-3.0/settings.ini\" \"\${HOME}/.config/gtk-4.0/settings.ini\"; do
                    [[ -f \"\$_gtk\" ]] && sed -i \"s|^gtk-font-name=.*|gtk-font-name=\$rofi_font|\" \"\$_gtk\"
                done
                command -v xfconf-query &>/dev/null && \
                    xfconf-query -c xsettings -p /Gtk/FontName -s \"\$rofi_font\" 2>/dev/null || true
                for _rasi in \
                    \"${OHMYCHADWM_CONFIG}/menu/ohmychadwm-menu.rasi\" \
                    \"${OHMYCHADWM_CONFIG}/rofi/config.rasi\" \
                    \"${OHMYCHADWM_CONFIG}/rofi/launcher2.rasi\" \
                    \"\${HOME}/.config/rofi/config.rasi\"; do
                    [[ -f \"\$_rasi\" ]] && sed -i \"s|\(\s*font:\s*\)\\\"[^\\\"]*\\\"|\1\\\"\$rofi_font\\\"|g\" \"\$_rasi\"
                done
                echo \"Fonts applied.\"
            fi
        fi

        notify-send \"ohmychadwm\" \"Theme \${chosen} applied — rebuilding...\"
        cd \"${OHMYCHADWM_CONFIG}/chadwm\" && bash rebuild.sh
    '"
}

_rasi_readable_color() {
    # Ensure a hex color is readable on the dark menu background (#101010).
    # Lightens the color in steps until luminance >= 120, returns the result.
    local color="$1"
    local hex="${color#'#'}"
    local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    local lum=$(( (299*r + 587*g + 114*b) / 1000 ))
    while (( lum < 120 )); do
        r=$(( r + 20 < 255 ? r + 20 : 255 ))
        g=$(( g + 20 < 255 ? g + 20 : 255 ))
        b=$(( b + 20 < 255 ? b + 20 : 255 ))
        lum=$(( (299*r + 587*g + 114*b) / 1000 ))
        (( r == 255 && g == 255 && b == 255 )) && break
    done
    printf '#%02x%02x%02x' $r $g $b
}

_sync_rasi_accent() {
    # Extract SchemeMenufg from a theme .h file and write it into the menu .rasi ac: token
    local theme_file="$1"
    local rasi="${OHMYCHADWM_CONFIG}/menu/ohmychadwm-menu.rasi"
    [[ -f "$theme_file" ]] || return
    [[ -f "$rasi" ]] || return
    local color
    color=$(grep -oP 'SchemeMenufg\[\]\s*=\s*"\K[^"]+' "$theme_file" | head -1)
    [[ -z "$color" ]] && return
    color=$(_rasi_readable_color "$color")
    local safe_color="${color//&/\\&}"
    sed -i "s|ac:.*\/\* selected item text.*|ac:     ${safe_color};   /* selected item text   (synced from SchemeMenufg)  */|" "$rasi"
}

_apply_theme() {
    local theme="$1"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    if [[ ! -f "${OHMYCHADWM_CONFIG}/chadwm/themes/${theme}.h" ]]; then
        notify-send -u critical "ohmychadwm" "Theme '${theme}' not found"
        return 1
    fi
    # Comment out any active theme include
    sed -i "s|^#include \"themes/\(.*\)\.h\"|//#include \"themes/\1.h\"|" "$config"
    # Uncomment the chosen theme
    sed -i "s|^//#include \"themes/${theme}\.h\"|#include \"themes/${theme}.h\"|" "$config"
    # Sync SchemeMenufg → rofi menu accent color
    _sync_rasi_accent "${OHMYCHADWM_CONFIG}/chadwm/themes/${theme}.h"
    # Apply Xresources if present
    local xres="${OHMYCHADWM_CONFIG}/chadwm/themes/${theme}.Xresources"
    [[ -f "$xres" ]] && xrdb -merge "$xres"
    # Apply alacritty colours if present
    local alacritty_theme="${OHMYCHADWM_CONFIG}/chadwm/themes/alacritty/${theme}.toml"
    [[ -f "$alacritty_theme" ]] && cp "$alacritty_theme" "${HOME}/.config/alacritty/colors.toml"
    # Restore theme wallpaper if one was saved during generation
    local theme_wp="${OHMYCHADWM_CONFIG}/wallpapers/${theme}.jpg"
    [[ -f "$theme_wp" ]] && feh --bg-fill "$theme_wp"
    # Rebuild chadwm
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c 'cd ~/.config/ohmychadwm/chadwm && ./rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Theme '${theme}' applied — reboot your system"
}

show_font_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local active_theme
    active_theme=$(grep -oP '(?<=#include "themes/)[^"]+(?=\.h")' "$config" | head -1)
    local theme_file="${OHMYCHADWM_CONFIG}/chadwm/themes/${active_theme}.h"

    present_terminal "bash -c '
        # ── font family ──────────────────────────────────────────────────────
        family=\$(fc-list : family \
            | sed \"s/,.*//\" \
            | sed \"s/^[[:space:]]*//;s/[[:space:]]*\$//\" \
            | grep -v \"^\\.\" \
            | sort -uf \
            | fzf --prompt=\"Font family > \" --height=40% --layout=reverse --border 2>/dev/null) || exit 0
        [[ -z \"\$family\" ]] && exit 0

        # ── font style — real styles for chosen family ───────────────────────
        styles=\$(fc-list \":family=\$family\" style 2>/dev/null \
            | grep -oP \"(?<=style=)[^\n]+\" \
            | tr \",\" \"\n\" \
            | sed \"s/^[[:space:]]*//;s/[[:space:]]*\$//\" \
            | sort -u)
        style_count=\$(echo \"\$styles\" | grep -c .)
        if [[ \$style_count -le 1 ]]; then
            style=\$(echo \"\$styles\" | head -1)
            [[ -z \"\$style\" ]] && style=\"Bold\"
        else
            style=\$(echo \"\$styles\" | fzf --prompt=\"Font style > \" --height=40% --layout=reverse --border 2>/dev/null) || style=\"Bold\"
            [[ -z \"\$style\" ]] && style=\"Bold\"
        fi

        # ── font size ────────────────────────────────────────────────────────
        echo -e \"\nFont size? [default 13]:\"
        read -rp \"> \" size
        [[ \"\$size\" =~ ^[0-9]+\$ ]] && (( size >= 6 && size <= 72 )) || size=13

        # ── icon size ────────────────────────────────────────────────────────
        echo \"Bar icon size? [default 18]:\"
        read -rp \"> \" iconsize
        [[ \"\$iconsize\" =~ ^[0-9]+\$ ]] && (( iconsize >= 8 && iconsize <= 72 )) || iconsize=18

        # ── apply to active theme + config.def.h ─────────────────────────────
        for f in \"${theme_file}\" \"${config}\"; do
            sed -i \"s|#define THEME_FONT \\\"[^\\\"]*\\\"|#define THEME_FONT    \\\"\$family\\\"|\" \"\$f\"
            sed -i \"s|#define THEME_FONTSTYLE \\\"[^\\\"]*\\\"|#define THEME_FONTSTYLE   \\\"\$style\\\"|\" \"\$f\"
            sed -i \"s|#define THEME_FONTSIZE [0-9]*|#define THEME_FONTSIZE    \$size|\" \"\$f\"
            sed -i \"s|#define THEME_ICONSIZE [0-9]*|#define THEME_ICONSIZE    \$iconsize|\" \"\$f\"
        done

        notify-send \"ohmychadwm\" \"Font: \$family \$style \$size — rebuilding...\"
        cd \"${OHMYCHADWM_CONFIG}/chadwm\" && bash rebuild.sh
    '"
}

_apply_font() {
    local font="$1"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    # Update THEME_FONT in the active theme .h file
    local active_theme
    active_theme=$(grep -oP '(?<=#include "themes/)[^"]+(?=\.h")' "$config" | head -1)
    if [[ -n "$active_theme" ]]; then
        local theme_file="${OHMYCHADWM_CONFIG}/chadwm/themes/${active_theme}.h"
        if [[ -f "$theme_file" ]]; then
            sed -i "s|#define THEME_FONT \"[^\"]*\"|#define THEME_FONT    \"${font}\"|" "$theme_file"
        fi
    fi
    # Also update the fallback in config.def.h
    sed -i "s|#define THEME_FONT \"[^\"]*\"|#define THEME_FONT \"${font}\"|" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "Font set to '${font}'"
}

show_wallpaper_menu() {
    local walls_dir="${OHMYCHADWM_CONFIG}/wallpapers"
    local extra_dir="${HOME}/Templates/wallpapers"

    local -a all_images=()
    while IFS= read -r f; do all_images+=("$f"); done \
        < <(find "$walls_dir" -maxdepth 1 -type f 2>/dev/null | grep -E '\.(jpg|jpeg|png|webp)$' | sort)
    if [[ -d "$extra_dir" ]]; then
        while IFS= read -r f; do all_images+=("$f"); done \
            < <(find "$extra_dir" -maxdepth 1 -type f 2>/dev/null | grep -E '\.(jpg|jpeg|png|webp)$' | sort)
    fi

    if [[ ${#all_images[@]} -eq 0 ]]; then
        notify-send "ohmychadwm" "No wallpaper images found"
        return 1
    fi

    local chosen
    chosen=$(for f in "${all_images[@]}"; do
        printf '%s\0icon\x1f%s\n' "$f" "$f"
    done | rofi -dmenu -p "Wallpaper…" -show-icons -width "$MENU_WIDTH" 2>/dev/null) || return 1

    feh --bg-fill "$chosen" && \
        notify-send "ohmychadwm" "Wallpaper set to '$(basename "$chosen")'"

    # save as the active wallpaper in ohmychadwm wallpapers folder
    cp "$chosen" "${OHMYCHADWM_CONFIG}/wallpapers/wallpaper.jpg"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
show_setup_menu() {
    while true; do
        local options=" Edit Autostart\n Edit Alacritty\n Edit Picom\n Edit Rofi\n Edit Sxhkdrc\n Edit Config.def.h\n Edit Menu theme\n Display\n Lan/Wifi\n Defaults"

        # Show Xresources option only if the file exists
        [[ -f "${HOME}/.Xresources" ]] && options+="\n Xresources"

        case $(menu "Setup" "$options") in
            *"Edit Autostart"*) edit_in_editor "${OHMYCHADWM_CONFIG}/scripts/run.sh"; return 0 ;;
            *"Edit Picom"*)     edit_in_editor "${HOME}/.config/ohmychadwm/picom/picom.conf"; return 0 ;;
            *"Edit Rofi"*)      edit_in_editor "${HOME}/.config/ohmychadwm/rofi/config.rasi"; return 0 ;;
            *"Edit Alacritty"*) edit_in_editor "${HOME}/.config/alacritty/alacritty.toml"; return 0 ;;
            *"Edit Sxhkdrc"*)   edit_in_editor "${OHMYCHADWM_CONFIG}/sxhkd/sxhkdrc"; return 0 ;;
            *"Edit Config.def.h"*) edit_in_editor "${OHMYCHADWM_CONFIG}/chadwm/config.def.h"; return 0 ;;
            *"Edit Menu theme"*) present_terminal "nano ${OHMYCHADWM_CONFIG}/menu/ohmychadwm-menu.rasi"; return 0 ;;
            *Display*)      show_display_menu  || continue; return 0 ;;
            *"Lan/Wifi"*)   show_lanwifi_menu  || continue; return 0 ;;
            *Defaults*)     show_defaults_menu || continue; return 0 ;;
            *)              return 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Display management
# ---------------------------------------------------------------------------
show_display_menu() {
    while true; do
        # detect connected outputs at menu-open time
        local -a outputs
        mapfile -t outputs < <(xrandr | awk '/ connected/{print $1}')
        local out_count=${#outputs[@]}
        local primary="${outputs[0]:-}"
        local secondary="${outputs[1]:-}"

        local options=" arandr (GUI)\n Auto-detect\n Rotate display"
        if (( out_count >= 2 )); then
            options=" arandr (GUI)\n Auto-detect\n Mirror displays\n Extend right\n Extend left\n Extend above\n Extend below\n Primary only\n Secondary only\n Rotate display"
        fi

        case $(menu "Display (${out_count} connected)" "$options") in
            *arandr*)
                if ! command -v arandr &>/dev/null; then
                    notify-send "ohmychadwm" "Installing arandr..."
                    sudo pacman -S --needed --noconfirm arandr
                fi
                setsid arandr &>/dev/null &
                disown
                return 0
                ;;
            *"Auto-detect"*)
                xrandr --auto
                notify-send "ohmychadwm" "Display auto-detected"
                return 0
                ;;
            *"Mirror"*)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --same-as "$primary" --auto
                notify-send "ohmychadwm" "Mirroring ${primary} → ${secondary}"
                return 0
                ;;
            *"Extend right"*)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --right-of "$primary"
                notify-send "ohmychadwm" "${secondary} right of ${primary}"
                return 0
                ;;
            *"Extend left"*)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --left-of "$primary"
                notify-send "ohmychadwm" "${secondary} left of ${primary}"
                return 0
                ;;
            *"Extend above"*)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --above "$primary"
                notify-send "ohmychadwm" "${secondary} above ${primary}"
                return 0
                ;;
            *"Extend below"*)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --below "$primary"
                notify-send "ohmychadwm" "${secondary} below ${primary}"
                return 0
                ;;
            *"Primary only"*)
                xrandr --output "$primary" --auto
                for _o in "${outputs[@]:1}"; do xrandr --output "$_o" --off; done
                notify-send "ohmychadwm" "Primary only: ${primary}"
                return 0
                ;;
            *"Secondary only"*)
                xrandr --output "$secondary" --auto
                xrandr --output "$primary" --off
                notify-send "ohmychadwm" "Secondary only: ${secondary}"
                return 0
                ;;
            *Rotate*)
                show_rotate_menu "${outputs[@]}" || continue
                return 0
                ;;
            *) return 1 ;;
        esac
    done
}

show_rotate_menu() {
    local -a outputs=("$@")

    # if more than one display, ask which one to rotate
    local target
    if (( ${#outputs[@]} == 1 )); then
        target="${outputs[0]}"
    else
        target=$(printf '%s\n' "${outputs[@]}" | \
            rofi -dmenu -p "Rotate which display?" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    fi
    [[ -z "$target" ]] && return 1

    case $(menu "Rotate ${target}" " Normal\n Left (90°)\n Right (270°)\n Inverted (180°)") in
        *Normal*)   xrandr --output "$target" --rotate normal   ;;
        *Left*)     xrandr --output "$target" --rotate left     ;;
        *Right*)    xrandr --output "$target" --rotate right    ;;
        *Inverted*) xrandr --output "$target" --rotate inverted ;;
        *) return 1 ;;
    esac
    notify-send "ohmychadwm" "${target} rotated"
}

show_lanwifi_menu() {
    case $(menu "Lan/Wifi" " Network Manager\n nmtui") in
        *"Network Manager"*)
            if ! command -v nm-connection-editor &>/dev/null; then
                notify-send "ohmychadwm" "Installing network-manager-applet..."
                sudo pacman -S --needed --noconfirm network-manager-applet
            fi
            setsid nm-connection-editor &>/dev/null &
            disown
            ;;
        *nmtui*)
            if ! command -v nmtui &>/dev/null; then
                notify-send "ohmychadwm" "Installing networkmanager..."
                sudo pacman -S --needed --noconfirm networkmanager
            fi
            present_terminal "nmtui"
            ;;
        *) return 1 ;;
    esac
}

# binary→package name map + silent install
_ensure_installed() {
    local bin="$1"
    command -v "$bin" &>/dev/null && return 0
    local pkg
    case "$bin" in
        nvim) pkg="neovim" ;;
        *)    pkg="$bin" ;;
    esac
    notify-send "ohmychadwm" "Installing '${pkg}'..."
    present_terminal "sudo pacman -S --noconfirm ${pkg}"
    command -v "$bin" &>/dev/null || { notify-send -u critical "ohmychadwm" "Installation of '${pkg}' failed"; return 1; }
}

show_defaults_menu() {
    case $(menu "Defaults" " Terminal\n Editor\n Browser") in
        *Terminal*) _set_default_terminal; return 0 ;;
        *Editor*)   _set_default_editor;   return 0 ;;
        *Browser*)  _set_default_browser;  return 0 ;;
        *)          return 1 ;;
    esac
}

_set_default_terminal() {
    local terminals="alacritty\nghostty\nkitty\nxterm\nurxvt"
    local chosen
    chosen=$(echo -e "$terminals" | rofi -dmenu -p "Terminal…" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    _ensure_installed "$chosen" || return 1
    mkdir -p "${OHMYCHADWM_CONFIG}"
    sed -i "s|^TERMINAL=.*|TERMINAL=${chosen}|" "${OHMYCHADWM_CONFIG}/menu.conf" 2>/dev/null || \
        echo "TERMINAL=${chosen}" >> "${OHMYCHADWM_CONFIG}/menu.conf"
    # update super + t keybinding in sxhkdrc
    local sxhkdrc="${OHMYCHADWM_CONFIG}/sxhkd/sxhkdrc"
    if [[ -f "$sxhkdrc" ]]; then
        sed -i '/^super + t$/{n; s|.*|    '"${chosen}"'|}' "$sxhkdrc"
        sleep 0.2 && pkill -USR1 sxhkd 2>/dev/null
    fi
    notify-send "ohmychadwm" "Default terminal set to ${chosen} — Super+T updated"
}

_set_default_editor() {
    local editors="code\nnvim\nvim\nemacs\ngedit"
    local chosen
    chosen=$(echo -e "$editors" | rofi -dmenu -p "Editor…" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    _ensure_installed "$chosen" || return 1
    mkdir -p "${OHMYCHADWM_CONFIG}"
    sed -i "s|^EDITOR=.*|EDITOR=${chosen}|" "${OHMYCHADWM_CONFIG}/menu.conf" 2>/dev/null || \
        echo "EDITOR=${chosen}" >> "${OHMYCHADWM_CONFIG}/menu.conf"
    # update super + e keybinding in sxhkdrc
    # terminal editors must be wrapped in a terminal emulator
    local launch
    case "$chosen" in
        nvim|vim) launch="${TERMINAL} -e ${chosen}" ;;
        *)        launch="${chosen}" ;;
    esac
    local sxhkdrc="${OHMYCHADWM_CONFIG}/sxhkd/sxhkdrc"
    if [[ -f "$sxhkdrc" ]]; then
        sed -i '/^super + e$/{n; s|.*|    '"${launch}"'|}' "$sxhkdrc"
        sleep 0.2 && pkill -USR1 sxhkd 2>/dev/null
    fi
    notify-send "ohmychadwm" "Default editor set to ${chosen} — Super+E updated"
}

_set_default_browser() {
    local browsers="firefox\nchromium\nbrave\nqutebrowser\nvivaldi"
    local chosen
    chosen=$(echo -e "$browsers" | rofi -dmenu -p "Browser…" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    _ensure_installed "$chosen" || return 1
    mkdir -p "${OHMYCHADWM_CONFIG}"
    sed -i "s|^BROWSER=.*|BROWSER=${chosen}|" "${OHMYCHADWM_CONFIG}/menu.conf" 2>/dev/null || \
        echo "BROWSER=${chosen}" >> "${OHMYCHADWM_CONFIG}/menu.conf"
    # update super + w keybinding in sxhkdrc
    local sxhkdrc="${OHMYCHADWM_CONFIG}/sxhkd/sxhkdrc"
    if [[ -f "$sxhkdrc" ]]; then
        sed -i '/^super + w$/{n; s|.*|    '"${chosen}"'|}' "$sxhkdrc"
        sleep 0.2 && pkill -USR1 sxhkd 2>/dev/null
    fi
    notify-send "ohmychadwm" "Default browser set to ${chosen} — Super+W updated"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
show_pamac_menu() {
    if ! command -v pamac &>/dev/null; then
        present_terminal "yay -S pamac-aur"
        return 0
    fi
    pamac-manager &
}

show_install_menu() {
    while true; do
        local items=" Pamac"
        command -v octopi &>/dev/null && items+="\n Octopi"
        items+="\n AI tools\n Aur package\n Browser\n Dev environment\n Editor\n Extras\n Gaming\n Package\n Terminal"
        case $(menu "Install" "$items") in
            *"Package"*)  present_terminal 'pacman -Slq | fzf --multi --preview "pacman -Si {}" | xargs -ro sudo pacman -S --needed'; return 0 ;;
            *"Aur"*)      present_terminal 'yay -Slq | fzf --multi --preview "yay -Si {}" | xargs -ro yay -S'; return 0 ;;
            *Pamac*)      show_pamac_menu || continue; return 0 ;;
            *Octopi*)     octopi & return 0 ;;
            *Terminal*)   show_install_terminal_menu || continue; return 0 ;;
            *Editor*)     show_install_editor_menu   || continue; return 0 ;;
            *Browser*)    show_install_browser_menu  || continue; return 0 ;;
            *"Dev"*)      show_install_dev_menu      || continue; return 0 ;;
            *AI*)         show_install_ai_menu       || continue; return 0 ;;
            *Gaming*)     show_install_gaming_menu   || continue; return 0 ;;
            *Extras*)     show_install_extras_menu   || continue; return 0 ;;
            *)            return 1 ;;
        esac
    done
}

show_install_terminal_menu() {
    case $(menu "Terminal" " Alacritty\n Ghostty\n Kitty\n Terminator\n Urxvt\n WezTerm\n Xterm") in
        *Alacritty*)   install     "Alacritty"  "alacritty" ;;
        *Ghostty*)     install     "Ghostty"    "ghostty" ;;
        *Kitty*)       install     "Kitty"      "kitty" ;;
        *Terminator*)  install     "Terminator" "terminator" ;;
        *Urxvt*)       install     "Urxvt"      "rxvt-unicode" ;;
        *WezTerm*)     aur_install "WezTerm"    "wezterm" ;;
        *Xterm*)       install     "Xterm"      "xterm" ;;
        *)           return 1 ;;
    esac
}

show_install_editor_menu() {
    case $(menu "Editor" " Cursor\n Emacs\n Helix\n Neovim\n VSCode\n Zed") in
        *Cursor*) aur_install "Cursor" "cursor-bin" ;;
        *Emacs*)  install    "Emacs"  "emacs" ;;
        *Helix*)  install    "Helix"  "helix" ;;
        *Neovim*) install    "Neovim"  "neovim" ;;
        *VSCode*) aur_install "VSCode" "visual-studio-code-bin" ;;
        *Zed*)    install    "Zed"    "zed" ;;
        *)        return 1 ;;
    esac
}

show_install_browser_menu() {
    case $(menu "Browser" " Brave\n Chromium\n Firefox\n Qutebrowser") in
        *Brave*)       aur_install "Brave"       "brave-bin" ;;
        *Chromium*)    install    "Chromium"    "chromium" ;;
        *Firefox*)     install    "Firefox"     "firefox" ;;
        *Qutebrowser*) install    "Qutebrowser" "qutebrowser" ;;
        *)             return 1 ;;
    esac
}

show_install_dev_menu() {
    case $(menu "Dev environment" " Docker\n Go\n Node.js + mise\n Podman\n Python + mise\n Ruby + mise\n Rust") in
        *Docker*) install "Docker" "docker docker-compose" && \
                  present_terminal "sudo systemctl enable --now docker && sudo usermod -aG docker \$USER && echo 'Log out and back in for group change'" ;;
        *Go*)     install "Go" "go" ;;
        *Node*)   present_terminal "mise use -g node@lts && node --version" ;;
        *Podman*) install "Podman" "podman" ;;
        *Python*) present_terminal "mise use -g python@latest && python --version" ;;
        *Ruby*)   present_terminal "mise use -g ruby@latest && ruby --version" ;;
        *Rust*)   present_terminal "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" ;;
        *)        return 1 ;;
    esac
}

show_install_ai_menu() {
    # Detect GPU for appropriate Ollama package
    local ollama_pkg="ollama"
    command -v nvidia-smi &>/dev/null && ollama_pkg="ollama-cuda"
    command -v rocminfo   &>/dev/null && ollama_pkg="ollama-rocm"

    case $(menu "AI tools" " Claude Code\n Ollama (${ollama_pkg})\n OpenCode") in
        *"Claude Code"*)
            present_terminal "sudo pacman -S --needed --noconfirm nodejs npm && npm install -g @anthropic-ai/claude-code && echo 'Done. Run: claude'"
            ;;
        *Ollama*)
            present_terminal "sudo pacman -S --needed --noconfirm ${ollama_pkg} && sudo systemctl enable --now ollama && echo 'Ollama running. Try: ollama run llama3'"
            ;;
        *OpenCode*)
            present_terminal "sudo pacman -S --needed --noconfirm opencode && echo 'Done. Run: opencode'"
            ;;
        *)  return 1 ;;
    esac
}

show_install_gaming_menu() {
    case $(menu "Gaming" " Steam\n Lutris\n RetroArch\n Heroic (Epic Games)\n Bottles (Wine)") in
        *Steam*)   install "Steam"  "steam" ;;
        *Lutris*)  install "Lutris" "lutris" ;;
        *Retro*)   install "RetroArch" "retroarch" ;;
        *Heroic*)  aur_install "Heroic" "heroic-games-launcher-bin" ;;
        *Bottles*) install "Bottles" "bottles" ;;
        *)         return 1 ;;
    esac
}

show_install_extras_menu() {
    case $(menu "Extras" " Bitwarden\n OBS Studio\n Obsidian\n Signal\n Spotify") in
        *Bitwarden*)  install    "Bitwarden"  "bitwarden" ;;
        *OBS*)        install    "OBS Studio" "obs-studio" ;;
        *Obsidian*)   aur_install "Obsidian"  "obsidian" ;;
        *Signal*)     install    "Signal"    "signal-desktop" ;;
        *Spotify*)    aur_install "Spotify"   "spotify" ;;
        *)            return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Remove
# ---------------------------------------------------------------------------
show_remove_menu() {
    while true; do
        case $(menu "Remove" " Edit Autostart entry\n Dev environment\n Package") in
            *Package*)          present_terminal 'pacman -Qq | fzf --multi --preview "pacman -Qi {}" | xargs -ro sudo pacman -Rns'; return 0 ;;
            *"Dev"*)            show_remove_dev_menu   || continue; return 0 ;;
            *"Edit Autostart"*) edit_in_editor "${OHMYCHADWM_CONFIG}/scripts/run.sh"; return 0 ;;
            *)           return 1 ;;
        esac
    done
}

show_remove_dev_menu() {
    case $(menu "Remove dev" " Docker\n Go\n Rust") in
        *Go*)     remove_pkg "Go" "go" ;;
        *Rust*)   present_terminal "rustup self uninstall" ;;
        *Docker*) remove_pkg "Docker" "docker docker-compose" ;;
        *)        return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------
show_update_menu() {
    while true; do
        case $(menu "Update" " Aur packages\n Full update\n Hardware\n Keyboard\n Restart process\n Time sync\n Timezone") in
            *"Aur"*)       present_terminal "yay -Sua"; return 0 ;;
            *"Full"*)      present_terminal "yay -Syu"; return 0 ;;
            *"Restart"*)   show_restart_process_menu  || continue; return 0 ;;
            *Hardware*)    show_restart_hardware_menu || continue; return 0 ;;
            *Timezone*)    present_terminal "tzselect && echo 'Run: sudo timedatectl set-timezone <zone>'"; return 0 ;;
            *Keyboard*)    show_keyboard_menu || continue; return 0 ;;
            *"Time sync"*) present_terminal "sudo timedatectl set-ntp true && timedatectl status"; return 0 ;;
            *)             return 1 ;;
        esac
    done
}

show_keyboard_menu() {
    local keymap
    keymap=$(localectl list-keymaps | rofi -dmenu -p "Keyboard layout" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    [[ -z "$keymap" ]] && return 1
    present_terminal "sudo localectl set-keymap '$keymap' && localectl status"
}

show_restart_process_menu() {
    case $(menu " Restart process" " Picom\n Fastcompmgr\n Sxhkd") in
        *Picom*)      _restart_picom ;;
        *Fastcompmgr*)  _restart_fastcompmgr ;;
        *Sxhkd*)      pkill sxhkd; setsid sxhkd -c "${HOME}/.config/ohmychadwm/sxhkd/sxhkdrc" &>/dev/null & disown; notify-send "ohmychadwm" "Sxhkd restarted" ;;
        *)            return 1 ;;
    esac
}

show_restart_hardware_menu() {
    case $(menu "Restart hardware" " Audio (PipeWire)\n Audio (PulseAudio)\n WiFi\n Bluetooth") in
        *PipeWire*)  _restart_pipewire ;;
        *PulseAudio*) _restart_pulseaudio ;;
        *WiFi*)      present_terminal "printf 'Running: sudo systemctl restart NetworkManager\n\n'; sudo systemctl restart NetworkManager && echo Done" ;;
        *Bluetooth*) present_terminal "printf 'Running: sudo systemctl restart bluetooth\n\n'; sudo systemctl restart bluetooth && echo Done" ;;
        *)           return 1 ;;
    esac
}

_restart_picom() {
    local run="${HOME}/.config/ohmychadwm/scripts/run.sh"
    sed -i 's|^#run "picom|run "picom|' "$run"
    sed -i 's|^run "fastcompmgr|#run "fastcompmgr|' "$run"
    pkill fastcompmgr 2>/dev/null
    pkill picom 2>/dev/null
    setsid picom --config "${HOME}/.config/ohmychadwm/picom/picom.conf" -b &>/dev/null &
    disown
    notify-send "ohmychadwm" "Picom restarted"
}

_restart_fastcompmgr() {
    local run="${HOME}/.config/ohmychadwm/scripts/run.sh"
    sed -i 's|^#run "fastcompmgr|run "fastcompmgr|' "$run"
    sed -i 's|^run "picom|#run "picom|' "$run"
    pkill picom 2>/dev/null
    pkill fastcompmgr 2>/dev/null
    setsid fastcompmgr -c &>/dev/null &
    disown
    notify-send "ohmychadwm" "Fastcompmgr restarted"
}

_restart_pipewire() {
    present_terminal "printf 'Running: systemctl --user restart pipewire pipewire-pulse wireplumber\n\n'; systemctl --user restart pipewire pipewire-pulse wireplumber && notify-send 'ohmychadwm' 'PipeWire restarted' && echo Done"
}

_restart_pulseaudio() {
    present_terminal "printf 'Running: systemctl --user restart pulseaudio\n\n'; systemctl --user restart pulseaudio && notify-send 'ohmychadwm' 'PulseAudio restarted' && echo Done"
}

# ---------------------------------------------------------------------------
# System — power management
# ---------------------------------------------------------------------------
show_system_menu() {
    local options=" Lock\n Suspend\n Restart\n Shutdown"

    # Add Hibernate only if a swap partition/file is available
    if swapon --show | grep -q partition 2>/dev/null || \
       swapon --show | grep -q file      2>/dev/null; then
        options+=" \n Hibernate"
    fi

    case $(menu "System" "$options") in
        *Lock*)      _lock_screen ;;
        *Suspend*)   systemctl suspend ;;
        *Hibernate*) systemctl hibernate ;;
        *Restart*)   systemctl reboot ;;
        *Shutdown*)  systemctl poweroff ;;
        *)           return 1 ;;
    esac
}

_lock_screen() {
    if command -v betterlockscreen &>/dev/null; then
        betterlockscreen -l dim -- --time-str="%H:%M"
    elif command -v slock &>/dev/null; then
        slock
    else
        notify-send -u critical "ohmychadwm" "No screen locker found. Install slock or i3lock."
    fi
}

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------
show_info_menu() {
    while true; do
        local options=" System\n Btop\n Disk overview\n Disk explorer\n Temperatures\n Logs\n Keybindings"
        upower -e 2>/dev/null | grep -qi bat && options+=" \n Battery"

        case $(menu "Info" "$options") in
            *System*)       present_terminal "inxi -Fxxx"; return 0 ;;
            *Btop*)         command -v btop &>/dev/null || install "btop" "btop"; present_terminal "btop"; return 0 ;;
            *"Disk overview"*) present_terminal "df -h | (read -r header; echo \"\$header\"; sort)"; return 0 ;;
            *"Disk explorer"*) command -v ncdu &>/dev/null || install "ncdu" "ncdu"; present_terminal "ncdu ${HOME}"; return 0 ;;
            *Temp*)         present_terminal "sensors 2>/dev/null || echo 'Run: sudo pacman -S lm_sensors && sudo sensors-detect'" ; return 0 ;;
            *Battery*)      present_terminal "upower -i \$(upower -e | grep -i bat | head -1)"; return 0 ;;
            *Logs*)         show_logs_menu || continue; return 0 ;;
            *Keybindings*)  kiro-keybindings; return 0 ;;
            *)              return 1 ;;
        esac
    done
}

show_logs_menu() {
    case $(menu "Logs" " System log\n Boot log\n Errors only\n Kernel (dmesg)\n Follow live") in
        *System*)  plain_terminal "journalctl -n 200 --no-pager | less -R"; return 0 ;;
        *Boot*)    plain_terminal "journalctl -b --no-pager | less -R"; return 0 ;;
        *Errors*)  plain_terminal "journalctl -p err -b --no-pager | less -R"; return 0 ;;
        *Kernel*)  plain_terminal "sudo dmesg --color=always | less -R"; return 0 ;;
        *Follow*)  plain_terminal "journalctl -f"; return 0 ;;
        *)         return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# MAIN MENU
# ---------------------------------------------------------------------------
show_main_menu() {
    while true; do
        case $(menu "ohmychadwm" " Apps\n Style\n Learn\n Trigger\n Setup\n Install\n Remove\n Update\n Info\n System") in
            *Apps*)    rofi -no-config -no-lazy-grab -show drun -modi drun -theme ~/.config/ohmychadwm/rofi/launcher2.rasi; break ;;
            *Learn*)   show_learn_menu   || continue; break ;;
            *Trigger*) show_trigger_menu || continue; break ;;
            *Style*)   show_style_menu   || continue; break ;;
            *Setup*)   show_setup_menu   || continue; break ;;
            *Install*) show_install_menu || continue; break ;;
            *Remove*)  show_remove_menu  || continue; break ;;
            *Update*)  show_update_menu  || continue; break ;;
            *Info*)    show_info_menu    || continue; break ;;
            *System*)  show_system_menu  || continue; break ;;
            *)         break ;;
        esac
    done
}

# ===========================================================================
# ENTRY POINT — direct submenu access or full menu
# ===========================================================================

# Load user extension (can override any function above)
[[ -f "$USER_EXTENSION" ]] && source "$USER_EXTENSION"

if [[ -n "${1:-}" ]]; then
    case "${1,,}" in
        *screenshot*)    _screenshot_smart ;;
        *screenrecord*)  show_screenrecord_menu ;;
        *capture*)       show_capture_menu ;;
        *trigger*)       show_trigger_menu ;;
        *style*)         show_style_menu ;;
        *theme*)         show_theme_menu ;;
        *install*)       show_install_menu ;;
        *remove*)        show_remove_menu ;;
        *update*)        show_update_menu ;;
        *system*)        show_system_menu ;;
        *setup*)         show_setup_menu ;;
        *learn*)         show_learn_menu ;;
        *info*)          show_info_menu ;;
        *logs*)          show_logs_menu ;;
        *lock*)          _lock_screen ;;
        *toggle*)        show_toggle_menu ;;
        *ai*)            show_install_ai_menu ;;
        *gaming*)        show_install_gaming_menu ;;
        *)               show_main_menu ;;
    esac
else
    show_main_menu
fi
