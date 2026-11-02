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
    local search
    search="$(_t "Search…")"

    local choice
    # Capture exit code explicitly — rofi returns 1 on Escape, not an error
    choice=$(echo -e "$options" | rofi -dmenu \
        -p "" \
        -i \
        -no-show-match \
        -no-fixed-num-lines \
        -cycle \
        "${theme_arg[@]}" \
        -theme-str "entry { placeholder: \"${search//\"/}\"; }" \
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
# Translation: labels go through gettext (domain ohmychadwm-menu); English is the fallback.
# ---------------------------------------------------------------------------
export TEXTDOMAIN=ohmychadwm-menu
# Catalogs ship next to the menu (menu/locale/<lang>/LC_MESSAGES), so they come with kiro-skell.
export TEXTDOMAINDIR="${_SCRIPT_DIR}/locale"
# _t "Text" translates; _tf 'Text with $var' translates a whole sentence and then fills in $var
# (gettext's eval_gettext), so translators can move the value where their language needs it.
if command -v gettext &>/dev/null && command -v gettext.sh &>/dev/null; then
    _t() { gettext "$1"; }
    # shellcheck source=/dev/null
    . gettext.sh
    _tf() { eval_gettext "$1"; }
else
    _t() { printf '%s' "$1"; }
    _tf() { local _s="$1"; eval "printf '%s' \"${_s//\"/\\\"}\""; }
fi

# ---------------------------------------------------------------------------
# Keyed menu: pick "Prompt" key1 "Label 1" key2 "Label 2" ...
# Prints the key of the chosen row, so dispatch never depends on the (translated) label.
# An optional trailing "--" followed by rofi args is passed through.
# ---------------------------------------------------------------------------
pick() {
    local prompt="$1"; shift
    local -a _pk=() _pl=()
    while (( $# >= 2 )) && [[ "$1" != "--" ]]; do
        _pk+=("$1"); _pl+=("$2"); shift 2
    done
    [[ "${1:-}" == "--" ]] && shift
    local extra="-format i $*"
    # Each row carries its key as hidden search words (rofi "meta"): keys are English,
    # so typing "appear" finds Appearance whatever language the labels are in.
    local options="" i
    for i in "${!_pl[@]}"; do
        options+=" ${_pl[$i]//\\/\\\\}\0meta\x1f${_pk[$i]//_/ }\n"
    done
    local idx
    idx=$(menu "$prompt" "${options%\\n}" "$extra") || return 1
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#_pk[@]} )) || return 1
    echo "${_pk[$idx]}"
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
# Translated text reaches the terminal through exported OHM_MSG* variables, never spliced
# into the command, so quotes in a translation cannot break it.
present_terminal() {
    local cmd="$*"
    OHM_MSG_PRESS="$(_t "Press any key to close…")"
    export OHM_MSG_PRESS
    setsid "$TERMINAL" \
        --class OhmychadwmPresent \
        -e bash -c "
            echo
            printf '  \e[1m%s\e[0m\n\n' 'ohmychadwm'
            ${cmd}
            echo
            printf '  %s' \"\$OHM_MSG_PRESS\"
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
    local name
    name="$(basename "$file")"
    notify-send -t 2000 "ohmychadwm" "$(_tf 'Editing $name')"
    present_terminal "${EDITOR} '${file}'"
}

# ---------------------------------------------------------------------------
# Package install helpers
# ---------------------------------------------------------------------------
# _pkg_messages "Doing $name…" "$name done." "Failed." — exported for the terminal command
_pkg_messages() {
    OHM_MSG_START="$1" OHM_MSG_OK="$2" OHM_MSG_FAIL="$3"
    export OHM_MSG_START OHM_MSG_OK OHM_MSG_FAIL
}

_PKG_SHOW='echo "$OHM_MSG_START"'
_PKG_DONE='notify-send ohmychadwm "$OHM_MSG_OK" || notify-send -u critical ohmychadwm "$OHM_MSG_FAIL"'

install() {
    # install "Display Name" "pkg1 pkg2"
    local name="$1"
    local pkgs="$2"
    _pkg_messages "$(_tf 'Installing $name…')" "$(_tf '$name installed.')" "$(_t "Install failed.")"
    present_terminal "${_PKG_SHOW}; sudo pacman -S --needed --noconfirm ${pkgs} && ${_PKG_DONE}"
}

aur_install() {
    # aur_install "Display Name" "aur-pkg"
    local name="$1"
    local pkg="$2"
    _pkg_messages "$(_tf 'Installing $name from the AUR…')" "$(_tf '$name installed.')" "$(_t "AUR install failed.")"
    present_terminal "${_PKG_SHOW}; yay -S --noconfirm ${pkg} && ${_PKG_DONE}"
}

remove_pkg() {
    local name="$1"
    local pkgs="$2"
    _pkg_messages "$(_tf 'Removing $name…')" "$(_tf '$name removed.')" "$(_t "Remove failed.")"
    present_terminal "${_PKG_SHOW}; sudo pacman -Rns --noconfirm ${pkgs} && ${_PKG_DONE}"
}

# ===========================================================================
# MENU FUNCTIONS
# ===========================================================================

# ---------------------------------------------------------------------------
# Learn
# ---------------------------------------------------------------------------
show_learn_menu() {
    case $(pick "$(_t "Learn")" \
            keybindings "$(_t "Keybindings")" \
            ohmychadwm  "Ohmychadwm" \
            archwiki    "Arch Wiki" \
            bash        "Bash" \
            fish        "Fish shell" \
            man         "$(_t "Man pages")") in
        keybindings) kiro-keybindings ;;
        ohmychadwm)  setsid "$BROWSER" "https://github.com/erikdubois/ohmychadwm" >/dev/null 2>&1 & disown ;;
        archwiki)    setsid "$BROWSER" "https://wiki.archlinux.org" >/dev/null 2>&1 & disown ;;
        bash)        setsid "$BROWSER" "https://devhints.io/bash" >/dev/null 2>&1 & disown ;;
        fish)        setsid "$BROWSER" "https://fishshell.com/" >/dev/null 2>&1 & disown ;;
        man)         OHM_T_HINT="$(_t "Building the man page index (first run)…")"; export OHM_T_HINT; present_terminal "man -k . &>/dev/null || { echo \"\$OHM_T_HINT\"; sudo mandb; }; man -k . | fzf --preview 'man {1}' | awk '{print \$1}' | xargs -r man" ;;
        *)           return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Trigger — Capture / Toggle
# ---------------------------------------------------------------------------
show_trigger_menu() {
    while true; do
        case $(pick "$(_t "Trigger")" \
                capture "$(_t "Capture")" \
                toggle  "$(_t "Toggle")") in
            capture) show_capture_menu || continue; return 0 ;;
            toggle)  show_toggle_menu  || continue; return 0 ;;
            *)       return 1 ;;
        esac
    done
}

show_capture_menu() {
    while true; do
        case $(pick "$(_t "Capture")" \
                screenshot "$(_t "Screenshot")" \
                clipboard  "$(_t "Screenshot → clipboard")" \
                region     "$(_t "Screenshot region")" \
                record     "$(_t "Screenrecord")" \
                color      "$(_t "Color picker")") in
            screenshot) _screenshot_smart;     return 0 ;;
            clipboard)  _screenshot_clipboard; return 0 ;;
            region)     _screenshot_region;    return 0 ;;
            record)     show_screenrecord_menu; return 0 ;;
            color)      _colour_picker;        return 0 ;;
            *)          return 1 ;;
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
        action=$(notify-send -t 5000 "$(_t "Screenshot saved")" "$(basename "$file")" \
            --action="open=$(_t "Open in nomacs")" --wait 2>/dev/null)
        if [[ "$action" == "open" ]]; then
            if ! command -v nomacs &>/dev/null; then
                notify-send "ohmychadwm" "$(_t "Installing nomacs…")"
                sudo pacman -S --needed --noconfirm nomacs
            fi
            nomacs "$file" &
        fi
    ) &
    disown
}

_screenshot_clipboard() {
    maim | xclip -selection clipboard -t image/png
    notify-send -t 2000 "$(_t "Screenshot")" "$(_t "Copied to clipboard")"
}

_screenshot_region() {
    local dir="${HOME}/Pictures/Screenshots"
    mkdir -p "$dir"
    local file="${dir}/$(date +%Y-%m-%d_%H-%M-%S).png"
    maim -s "$file"
    xclip -selection clipboard -t image/png < "$file"
    notify-send -t 3000 "$(_t "Region screenshot")" "$(_t "Saved & copied to clipboard")"
}

_colour_picker() {
    if command -v xcolor &>/dev/null; then
        local color
        color=$(xcolor)
        echo -n "$color" | xclip -selection clipboard
        notify-send -t 0 "$(_t "Color picked")" "$(_tf '$color (copied to clipboard)')"
    else
        notify-send -u critical "ohmychadwm" "$(_t "xcolor not installed. Run: sudo pacman -S xcolor")"
    fi
}

show_screenrecord_menu() {
    if ! command -v simplescreenrecorder &>/dev/null; then
        notify-send "ohmychadwm" "$(_t "Installing SimpleScreenRecorder…")"
        sudo pacman -S --needed --noconfirm simplescreenrecorder
    fi
    setsid simplescreenrecorder &>/dev/null &
    disown
}


show_toggle_menu() {
    local nightlight autolock picom fastcompmgr
    nightlight=$(_t "Enable night light")
    autolock=$(_t "Enable auto-lock")
    picom=$(_t "Start picom")
    fastcompmgr=$(_t "Start fastcompmgr")
    [[ -f "${HOME}/.local/state/ohmychadwm/toggles/nightlight-on" ]] && nightlight=$(_t "Disable night light")
    [[ -f "${HOME}/.local/state/ohmychadwm/toggles/autolock-on" ]]   && autolock=$(_t "Disable auto-lock")
    pgrep -x picom       &>/dev/null && picom=$(_t "Stop picom")
    pgrep -x fastcompmgr &>/dev/null && fastcompmgr=$(_t "Stop fastcompmgr")

    case $(pick "$(_t "Toggle")" \
            nightlight  "$nightlight" \
            autolock    "$autolock" \
            picom       "$picom" \
            fastcompmgr "$fastcompmgr") in
        nightlight)  _toggle_nightlight ;;
        autolock)    _toggle_autolock ;;
        picom)       _toggle_picom ;;
        fastcompmgr) _toggle_fastcompmgr ;;
        *)           return 1 ;;
    esac
}

_toggle_picom() {
    if pgrep -x picom &>/dev/null; then
        pkill picom && notify-send "$(_t "Picom")" "$(_t "Stopped")"
    else
        if pgrep -x fastcompmgr &>/dev/null; then
            pkill fastcompmgr 2>/dev/null
            local _i=0; while pgrep -x fastcompmgr &>/dev/null && (( _i++ < 30 )); do sleep 0.1; done
        fi
        setsid picom --config "${HOME}/.config/ohmychadwm/picom/picom.conf" -b &>/dev/null &
        disown
        notify-send "$(_t "Picom")" "$(_t "Started")"
    fi
}

_toggle_fastcompmgr() {
    if pgrep -x fastcompmgr &>/dev/null; then
        pkill fastcompmgr && notify-send "$(_t "Fastcompmgr")" "$(_t "Stopped")"
    else
        if pgrep -x picom &>/dev/null; then
            pkill picom 2>/dev/null
            local _i=0; while pgrep -x picom &>/dev/null && (( _i++ < 30 )); do sleep 0.1; done
        fi
        setsid fastcompmgr -c -C &>/dev/null &
        disown
        notify-send "$(_t "Fastcompmgr")" "$(_t "Started")"
    fi
}

_toggle_nightlight() {
    local state_file="${HOME}/.local/state/ohmychadwm/toggles/nightlight-on"
    mkdir -p "$(dirname "$state_file")"
    if [[ -f "$state_file" ]]; then
        pkill redshift 2>/dev/null; rm -f "$state_file"
        notify-send "$(_t "Night light")" "$(_t "Disabled")"
    else
        if ! command -v redshift &>/dev/null; then
            notify-send "ohmychadwm" "$(_t "Installing redshift…")"
            sudo pacman -S --needed --noconfirm redshift
        fi
        touch "$state_file"
        redshift -O 4000 &>/dev/null &
        disown
        notify-send "$(_t "Night light")" "$(_t "Enabled (4000K)")"
    fi
}

_toggle_autolock() {
    local state_file="${HOME}/.local/state/ohmychadwm/toggles/autolock-on"
    mkdir -p "$(dirname "$state_file")"
    if [[ -f "$state_file" ]]; then
        pkill xautolock 2>/dev/null; rm -f "$state_file"
        notify-send "$(_t "Auto-lock")" "$(_t "Disabled")"
    else
        touch "$state_file"
        xautolock -time 10 -locker betterlockscreen -l dim -- --time-str="%H:%M" &>/dev/null &
        disown
        notify-send "$(_t "Auto-lock")" "$(_t "Enabled (10 min)")"
    fi
}

# ---------------------------------------------------------------------------
# Appearance — how things look
# ---------------------------------------------------------------------------
show_appearance_menu() {
    while true; do
        case $(pick "$(_t "Appearance")" \
                theme     "$(_t "Theme")" \
                wallpaper "$(_t "Wallpaper")" \
                font      "$(_t "Font")" \
                bar       "$(_t "Bar")" \
                windows   "$(_t "Windows")" \
                tags      "$(_t "Tags")" \
                alacritty "Alacritty" \
                default   "$(_t "Back to default")") in
            theme)     show_themes_menu     || continue; return 0 ;;
            wallpaper) show_wallpaper_menu  || continue; return 0 ;;
            font)      show_fonts_menu      || continue; return 0 ;;
            bar)       show_bar_menu        || continue; return 0 ;;
            windows)   show_windows_look_menu || continue; return 0 ;;
            tags)      show_tags_menu       || continue; return 0 ;;
            alacritty) show_alacritty_menu  || continue; return 0 ;;
            default)   _customise_reset_defaults; return 0 ;;
            *)         return 1 ;;
        esac
    done
}

# Old name, kept for user extensions and the "style" shortcut.
show_style_menu() { show_appearance_menu "$@"; }

show_themes_menu() {
    while true; do
        case $(pick "$(_t "Theme")" \
                choose "$(_t "Choose theme")" \
                create "$(_t "Create your own theme")" \
                delete "$(_t "Delete theme")" \
                random "$(_t "Random theme")") in
            choose) show_theme_menu        || continue; return 0 ;;
            create) setsid "$TERMINAL" -e bash -c "${OHMYCHADWM_CONFIG}/scripts/generate-chadwm-theme.sh; exec bash" >/dev/null 2>&1 & return 0 ;;
            delete) show_delete_theme_menu || continue; return 0 ;;
            random) _random_theme; return 0 ;;
            *)      return 1 ;;
        esac
    done
}

show_fonts_menu() {
    while true; do
        case $(pick "$(_t "Font")" \
                bar        "$(_t "Bar font")" \
                everywhere "$(_t "Apply everywhere")") in
            bar)        show_font_menu || continue; return 0 ;;
            everywhere) present_terminal "bash ${OHMYCHADWM_CONFIG}/scripts/apply-font-globally.sh"; return 0 ;;
            *)          return 1 ;;
        esac
    done
}

show_bar_menu() {
    while true; do
        case $(pick "$(_t "Bar")" \
                position  "$(_t "Position")" \
                padding   "$(_t "Padding")" \
                systray   "$(_t "Hide systray")" \
                modules   "$(_t "Status modules")" \
                launchers "$(_t "Launcher icons")") in
            position)  show_barpos_menu    || continue; return 0 ;;
            padding)   show_barpad_menu    || continue; return 0 ;;
            systray)   show_systray_menu   || continue; return 0 ;;
            modules)   show_slstatus_menu  || continue; return 0 ;;
            launchers) show_launchers_menu || continue; return 0 ;;
            *)         return 1 ;;
        esac
    done
}

show_windows_look_menu() {
    while true; do
        case $(pick "$(_t "Windows")" \
                border    "$(_t "Border")" \
                gaps      "$(_t "Gaps")" \
                smartgaps "$(_t "Smart gaps")") in
            border)    show_border_menu    || continue; return 0 ;;
            gaps)      show_gaps_menu      || continue; return 0 ;;
            smartgaps) show_smartgaps_menu || continue; return 0 ;;
            *)         return 1 ;;
        esac
    done
}


show_slstatus_menu() {
    local config="${OHMYCHADWM_CONFIG}/slstatus/config.def.h"
    local -a names=(datetime uptime cpu_perc disk_free disk_used hostname kernel_release load_avg netspeed_rx netspeed_tx ram_free ram_perc ram_used swap_free swap_perc)
    local -A labels=(
        [datetime]="$(_t "Date & time")"
        [uptime]="$(_t "Uptime")"
        [cpu_perc]="$(_t "CPU usage %")"
        [disk_free]="$(_t "Disk free")"
        [disk_used]="$(_t "Disk used")"
        [hostname]="$(_t "Hostname")"
        [kernel_release]="$(_t "Kernel")"
        [load_avg]="$(_t "Load average")"
        [netspeed_rx]="$(_t "Net download speed")"
        [netspeed_tx]="$(_t "Net upload speed")"
        [ram_free]="$(_t "RAM free")"
        [ram_perc]="$(_t "RAM usage %")"
        [ram_used]="$(_t "RAM used")"
        [swap_free]="$(_t "Swap free")"
        [swap_perc]="$(_t "Swap usage %")"
    )

    local selected_row=0

    while true; do
        local -a rows=()
        local name i
        for name in "${names[@]}"; do
            if grep -qP "^\s*\{\s*${name}," "$config"; then
                rows+=("$name" "✓ ${labels[$name]}")
            else
                rows+=("$name" "✗ ${labels[$name]}")
            fi
        done
        rows+=(apply "$(_t "Apply & rebuild")")

        local chosen
        chosen=$(pick "$(_t "Status modules")" "${rows[@]}" -- "-lines 16 -selected-row ${selected_row}") || return 1

        if [[ "$chosen" == apply ]]; then
            (cd "${OHMYCHADWM_CONFIG}/slstatus" && alacritty -e bash -c './rebuild.sh; exec bash')
            notify-send "ohmychadwm" "$(_t "slstatus updated")"
            return 0
        fi

        for i in "${!names[@]}"; do
            [[ "${names[$i]}" == "$chosen" ]] && selected_row=$i
        done
        if grep -qP "^\s*\{\s*${chosen}," "$config"; then
            sed -i "s|^\(\s*\){ ${chosen},|\1//{ ${chosen},|" "$config"
        else
            sed -i "s|^\(\s*\)//{ ${chosen},|\1{ ${chosen},|" "$config"
            # Net speed needs this machine's interface, not the one written in the config (enp3s0).
            if [[ "$chosen" == netspeed_* ]]; then
                local iface
                iface=$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route 2>/dev/null)
                [[ -n "$iface" ]] && sed -i -E "s|^(\s*\{ ${chosen},[^\"]*\"[^\"]*\",\s*)\"[^\"]*\"|\1\"${iface}\"|" "$config"
            fi
        fi
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
    notify-send "ohmychadwm" "$(_tf 'Random theme: $pick')"
    _apply_theme "$pick"
}

# Old names, kept for user extensions: their entries now live under Appearance and Setup.
show_chadwm_menu()    { show_themes_menu "$@"; }
show_customise_menu() { show_appearance_menu "$@"; }

_customise_reset_defaults() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    # The packaged skel copy always matches the installed dwm.c; the .default copy can lag behind it.
    local default="${OHMYCHADWM_SKEL:-/etc/skel/.config/ohmychadwm}/chadwm/config.def.h"
    [[ -f "$default" ]] || default="${OHMYCHADWM_CONFIG}/chadwm/config.def.h.default"
    # Border, gaps, tags, bar position and master area live in the theme files, so those
    # are reset too: every shipped theme comes back from skel; themes you made stay.
    # Paths and translated sentences go to the terminal through the environment.
    OHM_R_CONFIG="$config" OHM_R_DEFAULT="$default"
    OHM_R_THEMES="${OHMYCHADWM_CONFIG}/chadwm/themes" OHM_R_DEFAULT_THEMES="$(dirname "$default")/themes"
    OHM_R_KB="${OHMYCHADWM_CONFIG}/keybindings.txt" OHM_R_CHADWM="${OHMYCHADWM_CONFIG}/chadwm"
    OHM_T_NOTFOUND="$(_t "Not found: %s")"
    OHM_T_TITLE="$(_t "Reset chadwm config to default")"
    OHM_T_OVERWRITE="$(_t "This will overwrite:")"
    OHM_T_SHIPPED="$(_t "the shipped theme files in %s")"
    OHM_T_FROM="$(_t "with the defaults from:")"
    OHM_T_UNTOUCHED="$(_t "Themes you created yourself, wallpapers and other settings are untouched.")"
    OHM_T_BACKUPS="$(_t "Backups will be saved as:")"
    OHM_T_CONTINUE="$(_t "Continue? [y/N]")"
    OHM_T_CANCELLED="$(_t "Cancelled.")"
    OHM_T_BACKED="$(_t "Backups created.")"
    OHM_T_CONFIG_DONE="$(_t "config.def.h restored.")"
    OHM_T_THEMES_DONE="$(_t "Shipped theme files restored.")"
    OHM_T_KB_DONE="$(_t "Keybindings cheatsheet restored.")"
    export OHM_R_CONFIG OHM_R_DEFAULT OHM_R_THEMES OHM_R_DEFAULT_THEMES OHM_R_KB OHM_R_CHADWM \
        OHM_T_NOTFOUND OHM_T_TITLE OHM_T_OVERWRITE OHM_T_SHIPPED OHM_T_FROM OHM_T_UNTOUCHED OHM_T_BACKUPS \
        OHM_T_CONTINUE OHM_T_CANCELLED OHM_T_BACKED OHM_T_CONFIG_DONE OHM_T_THEMES_DONE OHM_T_KB_DONE
    local script
    script=$(cat <<'EOS'
if [[ ! -f "$OHM_R_DEFAULT" ]]; then
    printf "  $OHM_T_NOTFOUND\n" "$OHM_R_DEFAULT"
    exit 1
fi
line="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '%s\n  %s\n%s\n\n' "$line" "$OHM_T_TITLE" "$line"
printf '  %s\n    %s\n    ' "$OHM_T_OVERWRITE" "$OHM_R_CONFIG"
printf "$OHM_T_SHIPPED\n" "$OHM_R_THEMES"
printf '  %s\n    %s\n\n' "$OHM_T_FROM" "$(dirname "$OHM_R_DEFAULT")"
printf '  %s\n\n' "$OHM_T_UNTOUCHED"
ts=$(date +%Y%m%d-%H%M%S)
printf '  %s\n    %s\n    %s\n\n' "$OHM_T_BACKUPS" "${OHM_R_CONFIG}.${ts}" "${OHM_R_THEMES}.${ts}"
read -rp "  $OHM_T_CONTINUE " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "  $OHM_T_CANCELLED"; exit 0; }

cp "$OHM_R_CONFIG" "${OHM_R_CONFIG}.${ts}"
cp -a "$OHM_R_THEMES" "${OHM_R_THEMES}.${ts}"
printf '\n  %s\n' "$OHM_T_BACKED"
cp "$OHM_R_DEFAULT" "$OHM_R_CONFIG"
echo "  $OHM_T_CONFIG_DONE"
if [[ -d "$OHM_R_DEFAULT_THEMES" ]]; then
    cp -f "$OHM_R_DEFAULT_THEMES"/*.h "$OHM_R_THEMES"/
    echo "  $OHM_T_THEMES_DONE"
fi
# The default config is QWERTY again, so the cheatsheet must be too.
kb_default="$(dirname "$(dirname "$OHM_R_DEFAULT")")/keybindings.txt"
if [[ -f "$kb_default" && ! "$kb_default" -ef "$OHM_R_KB" ]]; then
    cp -f "$kb_default" "$OHM_R_KB"
    echo "  $OHM_T_KB_DONE"
fi
echo
cd "$OHM_R_CHADWM" && bash rebuild.sh
EOS
)
    present_terminal "bash -c $(printf '%q' "$script")"
}

show_tags_menu() {
    local chosen
    chosen=$(pick "$(_t "Tags")" \
            TAGS_NERD      "$(_t "Icons (default)")" \
            TAGS_ARABIC    "$(_t "Arabic numbers")" \
            TAGS_ROMAN     "$(_t "Roman numbers")" \
            TAGS_POWERLINE "Powerline" \
            TAGS_WEBDINGS  "$(_t "Words (Web, Chat, Edit…)")" \
            TAGS_JAPANESE  "$(_t "Japanese numbers")" \
            TAGS_ALPHA     "$(_t "Letters")" \
            TAGS_EMOJI     "Emoji" \
            TAGS_GEOMETRIC "$(_t "Geometric shapes")" \
            TAGS_CHINESE   "$(_t "Chinese numbers")" \
            TAGS_PURPOSE   "$(_t "Purpose (home, chat, surf…)")") || return 1
    _apply_tags "$chosen"
}

_rebuild_chadwm() {
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
}

# Tags, border, gaps, smart gaps, systray, bar position and master area are THEME_* defines
# in the active theme file; config.def.h only reads them.
_set_theme_define() {
    local name="$1" value="$2"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local active theme_file
    active=$(grep -oP '(?<=^#include "themes/)[^"]+(?=\.h")' "$config" | head -1)
    theme_file="${OHMYCHADWM_CONFIG}/chadwm/themes/${active}.h"
    if [[ ! -f "$theme_file" ]]; then
        notify-send -u critical "ohmychadwm" "$(_t "Active theme file not found")"
        return 1
    fi
    if grep -qE "^#define ${name}[[:space:]]" "$theme_file"; then
        sed -i -E "s|^#define ${name}[[:space:]].*|#define ${name} ${value}|" "$theme_file"
    else
        printf '#define %s %s\n' "$name" "$value" >> "$theme_file"
    fi
    _rebuild_chadwm
}

_apply_tags() {
    _set_theme_define THEME_TAGS "$1" || return 1
    notify-send "ohmychadwm" "$(_t "Tags changed — rebuilding")"
}

show_keyboard_layout_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local current
    if grep -qE '^#define KIRO_AZERTY[[:space:]]+true' "$config"; then current=AZERTY; else current=QWERTY; fi
    local target
    target=$(pick "$(_t "Keybinding set") (${current})" \
            azerty "$(_t "AZERTY (Belgian)")" \
            qwerty "$(_t "QWERTY (US / world)")") || return 1
    # The switch script flips KIRO_AZERTY, recompiles, and swaps the cheatsheet; run it in a terminal for the sudo prompt.
    (alacritty -e bash -c "\$HOME/.bin/ohmychadwm-keyboard-layout ${target}; exec bash")
    notify-send "ohmychadwm" "$(_t "Keybinding set changed. Press Super+Shift+R to apply.")"
}

show_border_menu() {
    local px
    px=$(menu "$(_t "Border")" "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10") || return 1
    _set_theme_define THEME_BORDER "$px" || return 1
    notify-send "ohmychadwm" "$(_t "Border changed — rebuilding")"
}

show_gaps_menu() {
    local px
    px=$(menu "$(_t "Gaps")" "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10") || return 1
    _set_theme_define THEME_GAPS "$px" || return 1
    notify-send "ohmychadwm" "$(_t "Gaps changed — rebuilding")"
}

show_barpad_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    while true; do
        local cv ch
        cv=$(grep -oP 'vertpadbar\s*=\s*\K[0-9]+' "$config")
        ch=$(grep -oP 'horizpadbar\s*=\s*\K[0-9]+' "$config")
        case $(pick "$(_t "Padding") ${cv} / ${ch}" \
                vertical   "$(_t "Vertical padding")" \
                horizontal "$(_t "Horizontal padding")" \
                default    "$(_t "Back to default")") in
            vertical)
                local v
                v=$(menu "Bar vertical padding (current: ${cv})" \
                    "0\n2\n4\n6\n8\n10\n11\n12\n14\n16\n18\n20") || continue
                sed -i "s/\(static const int vertpadbar\s*=\s*\)[0-9]\+/\1${v}/" "$config"
                notify-send "ohmychadwm" "$(_tf 'Vertical padding: $v — rebuilding…')"
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            horizontal)
                local h
                h=$(menu "Bar horizontal padding (current: ${ch})" \
                    "0\n2\n4\n5\n6\n8\n10\n12\n14\n16\n18\n20") || continue
                sed -i "s/\(static const int horizpadbar\s*=\s*\)[0-9]\+/\1${h}/" "$config"
                notify-send "ohmychadwm" "$(_tf 'Horizontal padding: $h — rebuilding…')"
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            default)
                sed -i "s/\(static const int vertpadbar\s*=\s*\)[0-9]\+/\111/" "$config"
                sed -i "s/\(static const int horizpadbar\s*=\s*\)[0-9]\+/\15/" "$config"
                notify-send "ohmychadwm" "$(_t "Bar padding reset to defaults — rebuilding…")"
                (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
                return 0
                ;;
            *) return 1 ;;
        esac
    done
}

show_barpos_menu() {
    local value
    value=$(pick "$(_t "Position")" \
            1 "$(_t "Top")" \
            0 "$(_t "Bottom")") || return 1
    _set_theme_define THEME_TOPBAR "$value" || return 1
    notify-send "ohmychadwm" "$(_t "Bar position changed — rebuilding")"
}

show_smartgaps_menu() {
    local value
    value=$(pick "$(_t "Smart gaps")" \
            1 "$(_t "On")" \
            0 "$(_t "Off")") || return 1
    _set_theme_define THEME_SMARTGAPS "$value" || return 1
    notify-send "ohmychadwm" "$(_t "Smart gaps changed — rebuilding")"
}

show_systray_menu() {
    local value
    value=$(pick "$(_t "Systray")" \
            1 "$(_t "Show systray")" \
            0 "$(_t "Hide systray")") || return 1
    _set_theme_define THEME_SHOWSYSTRAY "$value" || return 1
    notify-send "ohmychadwm" "$(_t "Systray changed — rebuilding")"
}

show_newwindow_menu() {
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local value
    value=$(pick "$(_t "New window")" \
            0 "$(_t "Opens in front")" \
            1 "$(_t "Opens at the end")") || return 1
    sed -i "s/\(new_window_attach_on_end\s*=\s*\)[01]/\1${value}/" "$config"
    (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
    notify-send "ohmychadwm" "$(_t "New window position changed — rebuilding")"
}

show_mfact_menu() {
    local chosen
    chosen=$(menu "$(_t "Master area")" "10%\n20%\n30%\n40%\n50%\n60%\n70%\n80%\n90%") || return 1
    local pct="${chosen/\%/}"
    _set_theme_define THEME_MFACT "$(printf "0.%02d" "$pct")" || return 1
    notify-send "ohmychadwm" "$(_t "Master area changed — rebuilding")"
}

ALACRITTY_CONF="${HOME}/.config/alacritty/alacritty.toml"
ALACRITTY_THEMES_DIR="${HOME}/.config/ohmychadwm/alacritty/alacritty-themes"
ALACRITTY_DEFAULT_THEME="ohmychadwm-theme.toml"

show_alacritty_menu() {
    while true; do
        case $(pick "Alacritty" \
                theme   "$(_t "Theme")" \
                family  "$(_t "Font family")" \
                size    "$(_t "Font size")" \
                opacity "$(_t "Opacity")" \
                default "$(_t "Back to default")") in
            theme)   show_alacritty_theme_menu   || continue; return 0 ;;
            family)  show_alacritty_font_menu    || continue; return 0 ;;
            size)    show_alacritty_size_menu    || continue; return 0 ;;
            opacity) show_alacritty_opacity_menu || continue; return 0 ;;
            default) _alacritty_reset_default; return 0 ;;
            *)       return 1 ;;
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
    # The ohmychadwm theme leads the list when it exists; the rest follow alphabetically.
    local theme_list=""
    [[ -f "${ALACRITTY_THEMES_DIR}/${ALACRITTY_DEFAULT_THEME}" ]] && theme_list="${ALACRITTY_DEFAULT_THEME}"$'\n'
    theme_list+=$(find "$ALACRITTY_THEMES_DIR" -maxdepth 1 -name '*.toml' ! -name "$ALACRITTY_DEFAULT_THEME" \
        -printf '%f\n' | sort)
    local chosen
    chosen=$(printf '%s\n' "$theme_list" | \
        rofi -dmenu -p "$(_t "Alacritty theme")" -width "$MENU_WIDTH" -lines 20 2>/dev/null) || return 1
    _alacritty_apply_colors "${ALACRITTY_THEMES_DIR}/${chosen}"
    notify-send "ohmychadwm" "$(_tf 'Alacritty theme set to “${chosen}”')"
}

show_alacritty_font_menu() {
    local font_list
    font_list=$(fc-list : family | sort -u)
    local chosen
    chosen=$(echo "$font_list" | rofi -dmenu -p "$(_t "Alacritty font…")" -width "$MENU_WIDTH" -lines 20 2>/dev/null) || return 1
    sed -i "s|^\(family = \).*|\1\"${chosen}\"|" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "$(_tf 'Alacritty font set to “${chosen}”')"
}

show_alacritty_size_menu() {
    local current
    current=$(grep -oP 'size\s*=\s*\K[0-9.]+' "$ALACRITTY_CONF" | head -1)
    local chosen
    chosen=$(menu "Font size (current: ${current})" \
        "8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n20\n22\n24") || return 1
    sed -i "s/^\(size\s*=\s*\)[0-9.]*/\1${chosen}.0/" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "$(_tf 'Alacritty font size set to ${chosen}')"
}

show_alacritty_opacity_menu() {
    local current
    current=$(grep -oP 'opacity\s*=\s*\K[0-9.]+' "$ALACRITTY_CONF" | head -1)
    local chosen
    chosen=$(menu "Opacity (current: ${current})" \
        "0.1\n0.2\n0.3\n0.4\n0.5\n0.6\n0.7\n0.8\n0.9\n1.0") || return 1
    sed -i "s/^\(opacity\s*=\s*\)[0-9.]*/\1${chosen}/" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "$(_tf 'Alacritty opacity set to ${chosen}')"
}

show_alacritty_shell_menu() {
    local current
    current=$(grep -oP 'program\s*=\s*"\K[^"]+' "$ALACRITTY_CONF" | head -1)
    local shell_list
    shell_list=$(grep -v '^#' /etc/shells | grep '^/bin/')
    local chosen
    chosen=$(echo "$shell_list" | rofi -dmenu -p "$(_tf 'Shell (now $current)')" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    sed -i "s|^\(program\s*=\s*\)\"[^\"]*\"|\1\"${chosen}\"|" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "$(_tf 'Alacritty shell set to ${chosen}')"
}

_alacritty_reset_default() {
    # Kiro ships default-kiro.toml; older ArcoLinux-based setups have default-arcolinux.toml.
    local backup="${HOME}/.config/alacritty/default-kiro.toml"
    [[ -f "$backup" ]] || backup="${HOME}/.config/alacritty/default-arcolinux.toml"
    if [[ ! -f "$backup" ]]; then
        notify-send -u critical "ohmychadwm" "$(_t "Default Alacritty config not found")"
        return 1
    fi
    cp "$backup" "$ALACRITTY_CONF"
    notify-send "ohmychadwm" "$(_t "Alacritty reset to default")"
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
        local -a rows=()
        local name
        for name in "${names[@]}"; do
            if grep -qP "^\s*\{\s*${name}," "$config"; then
                rows+=("$name" "✓ ${labels[$name]}")
            else
                rows+=("$name" "✗ ${labels[$name]}")
            fi
        done
        rows+=(apply "$(_t "Apply & rebuild")")

        local chosen
        chosen=$(pick "$(_t "Launcher icons")" "${rows[@]}") || return 1

        if [[ "$chosen" == apply ]]; then
            (cd "${OHMYCHADWM_CONFIG}/chadwm" && alacritty -e bash -c './rebuild.sh; exec bash')
            notify-send "ohmychadwm" "$(_t "Launcher icons updated")"
            return 0
        fi

        if grep -qP "^\s*\{\s*${chosen}," "$config"; then
            sed -i "s|^\(\s*\){ ${chosen},|\1//{ ${chosen},|" "$config"
        else
            sed -i "s|^\(\s*\)//{ ${chosen},|\1{ ${chosen},|" "$config"
        fi
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
        notify-send "ohmychadwm" "$(_t "No custom themes to delete")"
        return 1
    fi

    local chosen
    chosen=$(menu "Delete theme" "$custom_list") || return 1

    # confirm
    local confirm
    confirm=$(pick "$chosen" \
            yes    "$(_t "Yes, delete it")" \
            cancel "$(_t "Cancel")") || return 1
    [[ "$confirm" == yes ]] || return 1

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
        notify-send "ohmychadwm" "$(_t "Active theme deleted — switching to kanagawa")"
        _apply_theme "kanagawa"
    else
        notify-send "ohmychadwm" "$(_tf 'Theme “$chosen” deleted')"
    fi
}

show_theme_menu() {
    OHM_T_THEME_PROMPT="$(_t "Theme > ")"
    OHM_T_FONT_MISSING="$(_t "Font not installed: %s")"
    OHM_T_FONT_FALLBACK="$(_t "Install it first, or the bar will fall back to a system font.")"
    OHM_T_APPLY_ANYWAY="$(_t "Apply theme anyway? [y/N]")"
    OHM_T_THEME_FONT="$(_t "Theme font: %s")"
    OHM_T_APPLY_OTHERS="$(_t "Apply it to other apps too (alacritty, kitty, GTK, rofi)? [y/N]")"
    OHM_T_FONTS_APPLIED="$(_t "Fonts applied.")"
    OHM_T_THEME_APPLIED="$(_t "Theme %s applied — rebuilding…")"
    export OHM_T_THEME_PROMPT OHM_T_FONT_MISSING OHM_T_FONT_FALLBACK OHM_T_APPLY_ANYWAY \
        OHM_T_THEME_FONT OHM_T_APPLY_OTHERS OHM_T_FONTS_APPLIED OHM_T_THEME_APPLIED
    local themes_dir="${OHMYCHADWM_CONFIG}/chadwm/themes"
    local config="${OHMYCHADWM_CONFIG}/chadwm/config.def.h"
    local preview_script="${OHMYCHADWM_CONFIG}/scripts/preview-theme.sh"

    if [[ ! -d "$themes_dir" ]]; then
        notify-send "ohmychadwm" "$(_tf 'No themes directory found at ${themes_dir}')"
        return 1
    fi

    present_terminal "bash -c '
        chosen=\$(ls -1 \"$themes_dir\"/*.h 2>/dev/null \
            | xargs -n1 basename \
            | sed \"s/\\.h\$//\" \
            | fzf \
                --prompt=\"\$OHM_T_THEME_PROMPT\" \
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
                printf \"  ⚠  \$OHM_T_FONT_MISSING\n\" \"\$theme_font\"
                echo \"  \$OHM_T_FONT_FALLBACK\"
                echo \"\"
                read -rp \"  \$OHM_T_APPLY_ANYWAY \" _fc
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
            printf \"\$OHM_T_THEME_FONT\n\" \"\$rofi_font\"
            echo \"\$OHM_T_APPLY_OTHERS\"
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
                echo \"\$OHM_T_FONTS_APPLIED\"
            fi
        fi

        notify-send \"ohmychadwm\" \"\$(printf \"\$OHM_T_THEME_APPLIED\" \"\$chosen\")\"
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
        notify-send -u critical "ohmychadwm" "$(_tf 'Theme “${theme}” not found')"
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
    notify-send "ohmychadwm" "$(_tf 'Theme “${theme}” applied — reboot your system')"
}

show_font_menu() {
    OHM_T_FAMILY_PROMPT="$(_t "Font family > ")"
    OHM_T_STYLE_PROMPT="$(_t "Font style > ")"
    OHM_T_FONT_SIZE="$(_t "Font size? [default 13]:")"
    OHM_T_ICON_SIZE="$(_t "Bar icon size? [default 18]:")"
    OHM_T_FONT_SET="$(_t "Font: %s — rebuilding…")"
    export OHM_T_FAMILY_PROMPT OHM_T_STYLE_PROMPT OHM_T_FONT_SIZE OHM_T_ICON_SIZE OHM_T_FONT_SET
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
            | fzf --prompt=\"\$OHM_T_FAMILY_PROMPT\" --height=40% --layout=reverse --border 2>/dev/null) || exit 0
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
            style=\$(echo \"\$styles\" | fzf --prompt=\"\$OHM_T_STYLE_PROMPT\" --height=40% --layout=reverse --border 2>/dev/null) || style=\"Bold\"
            [[ -z \"\$style\" ]] && style=\"Bold\"
        fi

        # ── font size ────────────────────────────────────────────────────────
        printf \"\n%s\n\" \"\$OHM_T_FONT_SIZE\"
        read -rp \"> \" size
        [[ \"\$size\" =~ ^[0-9]+\$ ]] && (( size >= 6 && size <= 72 )) || size=13

        # ── icon size ────────────────────────────────────────────────────────
        echo \"\$OHM_T_ICON_SIZE\"
        read -rp \"> \" iconsize
        [[ \"\$iconsize\" =~ ^[0-9]+\$ ]] && (( iconsize >= 8 && iconsize <= 72 )) || iconsize=18

        # ── apply to active theme + config.def.h ─────────────────────────────
        for f in \"${theme_file}\" \"${config}\"; do
            sed -i \"s|#define THEME_FONT \\\"[^\\\"]*\\\"|#define THEME_FONT    \\\"\$family\\\"|\" \"\$f\"
            sed -i \"s|#define THEME_FONTSTYLE \\\"[^\\\"]*\\\"|#define THEME_FONTSTYLE   \\\"\$style\\\"|\" \"\$f\"
            sed -i \"s|#define THEME_FONTSIZE [0-9]*|#define THEME_FONTSIZE    \$size|\" \"\$f\"
            sed -i \"s|#define THEME_ICONSIZE [0-9]*|#define THEME_ICONSIZE    \$iconsize|\" \"\$f\"
        done

        notify-send \"ohmychadwm\" \"\$(printf \"\$OHM_T_FONT_SET\" \"\$family \$style \$size\")\"
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
    notify-send "ohmychadwm" "$(_tf 'Font set to “${font}”')"
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
        notify-send "ohmychadwm" "$(_t "No wallpaper images found")"
        return 1
    fi

    local chosen
    chosen=$(for f in "${all_images[@]}"; do
        printf '%s\0icon\x1f%s\n' "$f" "$f"
    done | rofi -dmenu -p "$(_t "Wallpaper…")" -show-icons -width "$MENU_WIDTH" 2>/dev/null) || return 1

    local name
    name="$(basename "$chosen")"
    feh --bg-fill "$chosen" && \
        notify-send "ohmychadwm" "$(_tf 'Wallpaper set to “$name”')"

    # save as the active wallpaper in ohmychadwm wallpapers folder
    cp "$chosen" "${OHMYCHADWM_CONFIG}/wallpapers/wallpaper.jpg"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
show_setup_menu() {
    while true; do
        case $(pick "$(_t "Setup")" \
                keybindings "$(_t "Keybinding set")" \
                keyboard    "$(_t "Keyboard")" \
                windows     "$(_t "Windows")" \
                display     "$(_t "Display")" \
                network     "$(_t "Network")" \
                defaults    "$(_t "Defaults")" \
                timezone    "$(_t "Timezone")" \
                timesync    "$(_t "Time sync")" \
                config      "$(_t "Config")" \
                reset       "$(_t "Hard reset")") in
            keybindings) show_keyboard_layout_menu || continue; return 0 ;;
            keyboard)    show_keyboard_menu        || continue; return 0 ;;
            windows)     show_windows_behaviour_menu || continue; return 0 ;;
            display)     show_display_menu  || continue; return 0 ;;
            network)     show_lanwifi_menu  || continue; return 0 ;;
            defaults)    show_defaults_menu || continue; return 0 ;;
            timezone)    OHM_T_HINT="$(_t "Then run: sudo timedatectl set-timezone <zone>")"; export OHM_T_HINT; present_terminal "tzselect && echo \"\$OHM_T_HINT\""; return 0 ;;
            timesync)    present_terminal "sudo timedatectl set-ntp true && timedatectl status"; return 0 ;;
            config)      show_config_menu   || continue; return 0 ;;
            reset)       present_terminal "bash ${OHMYCHADWM_CONFIG}/scripts/backup-originals.sh --restore"; return 0 ;;
            *)           return 1 ;;
        esac
    done
}

show_windows_behaviour_menu() {
    while true; do
        case $(pick "$(_t "Windows")" \
                newwindow "$(_t "New window")" \
                master    "$(_t "Master area")") in
            newwindow) show_newwindow_menu || continue; return 0 ;;
            master)    show_mfact_menu     || continue; return 0 ;;
            *)         return 1 ;;
        esac
    done
}

show_config_menu() {
    local -a rows=(
        autostart "$(_t "Autostart")"
        alacritty "Alacritty"
        picom     "Picom"
        rofi      "Rofi"
        sxhkd     "Sxhkd"
        chadwm    "config.def.h"
        menutheme "$(_t "Menu theme")"
    )
    [[ -f "${HOME}/.Xresources" ]] && rows+=(xresources "Xresources")
    case $(pick "$(_t "Config")" "${rows[@]}") in
        autostart)  edit_in_editor "${OHMYCHADWM_CONFIG}/scripts/run.sh" ;;
        alacritty)  edit_in_editor "${HOME}/.config/alacritty/alacritty.toml" ;;
        picom)      edit_in_editor "${OHMYCHADWM_CONFIG}/picom/picom.conf" ;;
        rofi)       edit_in_editor "${OHMYCHADWM_CONFIG}/rofi/config.rasi" ;;
        sxhkd)      edit_in_editor "${OHMYCHADWM_CONFIG}/sxhkd/sxhkdrc" ;;
        chadwm)     edit_in_editor "${OHMYCHADWM_CONFIG}/chadwm/config.def.h" ;;
        menutheme)  edit_in_editor "${OHMYCHADWM_CONFIG}/menu/ohmychadwm-menu.rasi" ;;
        xresources) edit_in_editor "${HOME}/.Xresources" ;;
        *)          return 1 ;;
    esac
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

        local -a rows=(arandr "arandr (GUI)" auto "$(_t "Auto-detect")")
        if (( out_count >= 2 )); then
            rows+=(
                mirror    "$(_t "Mirror displays")"
                right     "$(_t "Extend right")"
                left      "$(_t "Extend left")"
                above     "$(_t "Extend above")"
                below     "$(_t "Extend below")"
                primary   "$(_t "Primary only")"
                secondary "$(_t "Secondary only")"
            )
        fi
        rows+=(rotate "$(_t "Rotate display")")

        case $(pick "$(_t "Display")" "${rows[@]}") in
            arandr)
                if ! command -v arandr &>/dev/null; then
                    notify-send "ohmychadwm" "$(_t "Installing arandr…")"
                    sudo pacman -S --needed --noconfirm arandr
                fi
                setsid arandr &>/dev/null &
                disown
                return 0
                ;;
            auto)
                xrandr --auto
                notify-send "ohmychadwm" "$(_t "Display auto-detected")"
                return 0
                ;;
            mirror)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --same-as "$primary" --auto
                notify-send "ohmychadwm" "$(_tf 'Mirroring ${primary} → ${secondary}')"
                return 0
                ;;
            right)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --right-of "$primary"
                notify-send "ohmychadwm" "$(_tf '${secondary} right of ${primary}')"
                return 0
                ;;
            left)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --left-of "$primary"
                notify-send "ohmychadwm" "$(_tf '${secondary} left of ${primary}')"
                return 0
                ;;
            above)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --above "$primary"
                notify-send "ohmychadwm" "$(_tf '${secondary} above ${primary}')"
                return 0
                ;;
            below)
                xrandr --output "$primary" --auto \
                       --output "$secondary" --auto --below "$primary"
                notify-send "ohmychadwm" "$(_tf '${secondary} below ${primary}')"
                return 0
                ;;
            primary)
                xrandr --output "$primary" --auto
                for _o in "${outputs[@]:1}"; do xrandr --output "$_o" --off; done
                notify-send "ohmychadwm" "$(_tf 'Primary only: ${primary}')"
                return 0
                ;;
            secondary)
                xrandr --output "$secondary" --auto
                xrandr --output "$primary" --off
                notify-send "ohmychadwm" "$(_tf 'Secondary only: ${secondary}')"
                return 0
                ;;
            rotate)
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
            rofi -dmenu -p "$(_t "Rotate which display?")" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    fi
    [[ -z "$target" ]] && return 1

    local rotation
    rotation=$(pick "$target" \
            normal   "$(_t "Normal")" \
            left     "$(_t "Left (90°)")" \
            right    "$(_t "Right (270°)")" \
            inverted "$(_t "Inverted (180°)")") || return 1
    xrandr --output "$target" --rotate "$rotation"
    notify-send "ohmychadwm" "$(_t "Display rotated"): ${target}"
}

show_lanwifi_menu() {
    case $(pick "$(_t "Network")" \
            editor "Network Manager" \
            nmtui  "nmtui") in
        editor)
            if ! command -v nm-connection-editor &>/dev/null; then
                notify-send "ohmychadwm" "$(_t "Installing network-manager-applet…")"
                sudo pacman -S --needed --noconfirm network-manager-applet
            fi
            setsid nm-connection-editor &>/dev/null &
            disown
            ;;
        nmtui)
            if ! command -v nmtui &>/dev/null; then
                notify-send "ohmychadwm" "$(_t "Installing networkmanager…")"
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
    notify-send "ohmychadwm" "$(_tf 'Installing “${pkg}”…')"
    present_terminal "sudo pacman -S --noconfirm ${pkg}"
    command -v "$bin" &>/dev/null || { notify-send -u critical "ohmychadwm" "$(_tf 'Installing “${pkg}” failed')"; return 1; }
}

show_defaults_menu() {
    case $(pick "$(_t "Defaults")" \
            terminal "$(_t "Terminal")" \
            editor   "$(_t "Editor")" \
            browser  "$(_t "Browser")" \
            shell    "$(_t "Shell")") in
        terminal) _set_default_terminal; return 0 ;;
        editor)   _set_default_editor;   return 0 ;;
        browser)  _set_default_browser;  return 0 ;;
        shell)    show_alacritty_shell_menu; return 0 ;;
        *)        return 1 ;;
    esac
}

_set_default_terminal() {
    local terminals="alacritty\nghostty\nkitty\nxterm\nurxvt"
    local chosen
    chosen=$(echo -e "$terminals" | rofi -dmenu -p "$(_t "Terminal…")" -width "$MENU_WIDTH" 2>/dev/null) || return 1
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
    notify-send "ohmychadwm" "$(_tf 'Default terminal set to ${chosen} — Super+T updated')"
}

_set_default_editor() {
    local editors="code\nnvim\nvim\nemacs\ngedit"
    local chosen
    chosen=$(echo -e "$editors" | rofi -dmenu -p "$(_t "Editor…")" -width "$MENU_WIDTH" 2>/dev/null) || return 1
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
    notify-send "ohmychadwm" "$(_tf 'Default editor set to ${chosen} — Super+E updated')"
}

_set_default_browser() {
    local browsers="firefox\nchromium\nbrave\nqutebrowser\nvivaldi"
    local chosen
    chosen=$(echo -e "$browsers" | rofi -dmenu -p "$(_t "Browser…")" -width "$MENU_WIDTH" 2>/dev/null) || return 1
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
    notify-send "ohmychadwm" "$(_tf 'Default browser set to ${chosen} — Super+W updated')"
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
        local -a rows=(pamac "Pamac")
        command -v octopi &>/dev/null && rows+=(octopi "Octopi")
        rows+=(
            package  "$(_t "Package")"
            aur      "$(_t "AUR package")"
            ai       "$(_t "AI tools")"
            browser  "$(_t "Browser")"
            dev      "$(_t "Dev environment")"
            editor   "$(_t "Editor")"
            extras   "$(_t "Extras")"
            gaming   "$(_t "Gaming")"
            terminal "$(_t "Terminal")"
        )
        case $(pick "$(_t "Install")" "${rows[@]}") in
            package)  present_terminal 'pacman -Slq | fzf --multi --preview "pacman -Si {}" | xargs -ro sudo pacman -S --needed'; return 0 ;;
            aur)      present_terminal 'yay -Slq | fzf --multi --preview "yay -Si {}" | xargs -ro yay -S'; return 0 ;;
            pamac)    show_pamac_menu || continue; return 0 ;;
            octopi)   octopi & return 0 ;;
            terminal) show_install_terminal_menu || continue; return 0 ;;
            editor)   show_install_editor_menu   || continue; return 0 ;;
            browser)  show_install_browser_menu  || continue; return 0 ;;
            dev)      show_install_dev_menu      || continue; return 0 ;;
            ai)       show_install_ai_menu       || continue; return 0 ;;
            gaming)   show_install_gaming_menu   || continue; return 0 ;;
            extras)   show_install_extras_menu   || continue; return 0 ;;
            *)        return 1 ;;
        esac
    done
}

show_install_terminal_menu() {
    case $(pick "$(_t "Terminal")" \
            alacritty Alacritty ghostty Ghostty kitty Kitty terminator Terminator \
            urxvt Urxvt wezterm WezTerm xterm Xterm) in
        alacritty)  install     "Alacritty"  "alacritty" ;;
        ghostty)    install     "Ghostty"    "ghostty" ;;
        kitty)      install     "Kitty"      "kitty" ;;
        terminator) install     "Terminator" "terminator" ;;
        urxvt)      install     "Urxvt"      "rxvt-unicode" ;;
        wezterm)    aur_install "WezTerm"    "wezterm" ;;
        xterm)      install     "Xterm"      "xterm" ;;
        *)          return 1 ;;
    esac
}

show_install_editor_menu() {
    case $(pick "$(_t "Editor")" \
            cursor Cursor emacs Emacs helix Helix neovim Neovim vscode VSCode zed Zed) in
        cursor) aur_install "Cursor" "cursor-bin" ;;
        emacs)  install     "Emacs"  "emacs" ;;
        helix)  install     "Helix"  "helix" ;;
        neovim) install     "Neovim" "neovim" ;;
        vscode) aur_install "VSCode" "visual-studio-code-bin" ;;
        zed)    install     "Zed"    "zed" ;;
        *)      return 1 ;;
    esac
}

show_install_browser_menu() {
    case $(pick "$(_t "Browser")" \
            brave Brave chromium Chromium firefox Firefox qutebrowser Qutebrowser) in
        brave)       aur_install "Brave"       "brave-bin" ;;
        chromium)    install     "Chromium"    "chromium" ;;
        firefox)     install     "Firefox"     "firefox" ;;
        qutebrowser) install     "Qutebrowser" "qutebrowser" ;;
        *)           return 1 ;;
    esac
}

show_install_dev_menu() {
    case $(pick "$(_t "Dev environment")" \
            docker Docker go Go node "Node.js + mise" podman Podman \
            python "Python + mise" ruby "Ruby + mise" rust Rust) in
        docker) install "Docker" "docker docker-compose" && \
                OHM_T_HINT="$(_t "Log out and back in so the docker group takes effect.")"; export OHM_T_HINT; present_terminal "sudo systemctl enable --now docker && sudo usermod -aG docker \$USER && echo \"\$OHM_T_HINT\"" ;;
        go)     install "Go" "go" ;;
        node)   present_terminal "mise use -g node@lts && node --version" ;;
        podman) install "Podman" "podman" ;;
        python) present_terminal "mise use -g python@latest && python --version" ;;
        ruby)   present_terminal "mise use -g ruby@latest && ruby --version" ;;
        rust)   present_terminal "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" ;;
        *)      return 1 ;;
    esac
}

show_install_ai_menu() {
    OHM_T_HINT="$(_t "Done. Start it with: %s")"
    OHM_T_OLLAMA="$(_t "Ollama is running. Try: ollama run llama3")"
    export OHM_T_HINT OHM_T_OLLAMA
    # Detect GPU for appropriate Ollama package
    local ollama_pkg="ollama"
    command -v nvidia-smi &>/dev/null && ollama_pkg="ollama-cuda"
    command -v rocminfo   &>/dev/null && ollama_pkg="ollama-rocm"

    case $(pick "$(_t "AI tools")" \
            claude   "Claude Code" \
            ollama   "Ollama (${ollama_pkg})" \
            opencode "OpenCode") in
        claude)
            present_terminal "sudo pacman -S --needed --noconfirm nodejs npm && npm install -g @anthropic-ai/claude-code && printf \"\$OHM_T_HINT\n\" claude"
            ;;
        ollama)
            present_terminal "sudo pacman -S --needed --noconfirm ${ollama_pkg} && sudo systemctl enable --now ollama && echo \"\$OHM_T_OLLAMA\""
            ;;
        opencode)
            present_terminal "sudo pacman -S --needed --noconfirm opencode && printf \"\$OHM_T_HINT\n\" opencode"
            ;;
        *)  return 1 ;;
    esac
}

show_install_gaming_menu() {
    case $(pick "$(_t "Gaming")" \
            steam Steam lutris Lutris retroarch RetroArch \
            heroic "Heroic (Epic Games)" bottles "Bottles (Wine)") in
        steam)     install     "Steam"     "steam" ;;
        lutris)    install     "Lutris"    "lutris" ;;
        retroarch) install     "RetroArch" "retroarch" ;;
        heroic)    aur_install "Heroic"    "heroic-games-launcher-bin" ;;
        bottles)   install     "Bottles"   "bottles" ;;
        *)         return 1 ;;
    esac
}

show_install_extras_menu() {
    case $(pick "$(_t "Extras")" \
            bitwarden Bitwarden obs "OBS Studio" obsidian Obsidian signal Signal spotify Spotify) in
        bitwarden) install     "Bitwarden"  "bitwarden" ;;
        obs)       install     "OBS Studio" "obs-studio" ;;
        obsidian)  aur_install "Obsidian"   "obsidian" ;;
        signal)    install     "Signal"     "signal-desktop" ;;
        spotify)   aur_install "Spotify"    "spotify" ;;
        *)         return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Remove
# ---------------------------------------------------------------------------
show_remove_menu() {
    while true; do
        case $(pick "$(_t "Remove")" \
                package "$(_t "Package")" \
                dev     "$(_t "Dev environment")") in
            package) present_terminal 'pacman -Qq | fzf --multi --preview "pacman -Qi {}" | xargs -ro sudo pacman -Rns'; return 0 ;;
            dev)     show_remove_dev_menu || continue; return 0 ;;
            *)       return 1 ;;
        esac
    done
}

show_remove_dev_menu() {
    case $(pick "$(_t "Dev environment")" docker Docker go Go rust Rust) in
        go)     remove_pkg "Go" "go" ;;
        rust)   present_terminal "rustup self uninstall" ;;
        docker) remove_pkg "Docker" "docker docker-compose" ;;
        *)      return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Update — packages, and restarting processes and hardware
# ---------------------------------------------------------------------------
show_update_menu() {
    while true; do
        case $(pick "$(_t "Update")" \
                full     "$(_t "Full update")" \
                aur      "$(_t "AUR packages")" \
                process  "$(_t "Process")" \
                hardware "$(_t "Hardware")") in
            full)     present_terminal "yay -Syu"; return 0 ;;
            aur)      present_terminal "yay -Sua"; return 0 ;;
            process)  show_restart_process_menu  || continue; return 0 ;;
            hardware) show_restart_hardware_menu || continue; return 0 ;;
            *)        return 1 ;;
        esac
    done
}

# Sets the X11 layout of the running session and the persistent X11/console layout.
show_keyboard_menu() {
    local layout
    layout=$(localectl list-x11-keymap-layouts | rofi -dmenu -p "$(_t "Keyboard")" -width "$MENU_WIDTH" 2>/dev/null) || return 1
    [[ -z "$layout" ]] && return 1
    setxkbmap "$layout"
    present_terminal "sudo localectl set-x11-keymap '$layout' && localectl status"
}

show_restart_process_menu() {
    case $(pick "$(_t "Process")" picom Picom fastcompmgr Fastcompmgr sxhkd Sxhkd) in
        picom)       _restart_picom ;;
        fastcompmgr) _restart_fastcompmgr ;;
        sxhkd)       pkill sxhkd; setsid sxhkd -c "${HOME}/.config/ohmychadwm/sxhkd/sxhkdrc" &>/dev/null & disown; notify-send "ohmychadwm" "$(_t "Sxhkd restarted")" ;;
        *)           return 1 ;;
    esac
}

show_restart_hardware_menu() {
    case $(pick "$(_t "Hardware")" \
            pipewire   "$(_t "Audio (PipeWire)")" \
            pulseaudio "$(_t "Audio (PulseAudio)")" \
            wifi       "Wi-Fi" \
            bluetooth  "Bluetooth") in
        pipewire)   _restart_pipewire ;;
        pulseaudio) _restart_pulseaudio ;;
        wifi)       present_terminal "printf 'Running: sudo systemctl restart NetworkManager\n\n'; sudo systemctl restart NetworkManager && echo Done" ;;
        bluetooth)  present_terminal "printf 'Running: sudo systemctl restart bluetooth\n\n'; sudo systemctl restart bluetooth && echo Done" ;;
        *)           return 1 ;;
    esac
}

_restart_picom() {
    local run="${HOME}/.config/ohmychadwm/scripts/run.sh"
    sed -i "s|^#run picom|run picom|" "$run"
    sed -i "s|^run fastcompmgr|#run fastcompmgr|" "$run"
    pkill fastcompmgr 2>/dev/null
    pkill picom 2>/dev/null
    setsid picom --config "${HOME}/.config/ohmychadwm/picom/picom.conf" -b &>/dev/null &
    disown
    notify-send "ohmychadwm" "$(_t "Picom restarted")"
}

_restart_fastcompmgr() {
    local run="${HOME}/.config/ohmychadwm/scripts/run.sh"
    sed -i "s|^#run fastcompmgr|run fastcompmgr|" "$run"
    sed -i "s|^run picom|#run picom|" "$run"
    pkill picom 2>/dev/null
    pkill fastcompmgr 2>/dev/null
    setsid fastcompmgr -c -C &>/dev/null &
    disown
    notify-send "ohmychadwm" "$(_t "Fastcompmgr restarted")"
}

_restart_pipewire() {
    OHM_MSG_OK="$(_t "PipeWire restarted")"; export OHM_MSG_OK
    present_terminal "printf '\$ systemctl --user restart pipewire pipewire-pulse wireplumber\n\n'; systemctl --user restart pipewire pipewire-pulse wireplumber && notify-send ohmychadwm \"\$OHM_MSG_OK\" && echo \"\$OHM_MSG_OK\""
}

_restart_pulseaudio() {
    OHM_MSG_OK="$(_t "PulseAudio restarted")"; export OHM_MSG_OK
    present_terminal "printf '\$ systemctl --user restart pulseaudio\n\n'; systemctl --user restart pulseaudio && notify-send ohmychadwm \"\$OHM_MSG_OK\" && echo \"\$OHM_MSG_OK\""
}

# ---------------------------------------------------------------------------
# System — power management
# ---------------------------------------------------------------------------
show_system_menu() {
    local -a rows=(
        lock    "$(_t "Lock")"
        logout  "$(_t "Logout")"
        suspend "$(_t "Suspend")"
    )
    # Hibernate only when there is swap to hibernate to
    [[ -n "$(swapon --noheadings 2>/dev/null)" ]] && rows+=(hibernate "$(_t "Hibernate")")
    rows+=(
        reboot   "$(_t "Reboot")"
        shutdown "$(_t "Shutdown")"
    )

    case $(pick "$(_t "System")" "${rows[@]}") in
        lock)      _lock_screen ;;
        logout)    _logout_chadwm ;;
        suspend)   systemctl suspend ;;
        hibernate) systemctl hibernate ;;
        reboot)    systemctl reboot ;;
        shutdown)  systemctl poweroff ;;
        *)         return 1 ;;
    esac
}

_logout_chadwm() {
    # run.sh's loop ends when ohmychadwm quits cleanly; shutdown_ohmychadwm.sh triggers that quit path
    local script="${OHMYCHADWM_CONFIG}/scripts/shutdown_ohmychadwm.sh"
    if [[ ! -f "$script" ]]; then
        notify-send -u critical "ohmychadwm" "$(_t "Logout script not found"): ${script}"
        return 1
    fi
    bash "$script"
}

_lock_screen() {
    if command -v betterlockscreen &>/dev/null; then
        betterlockscreen -l dim -- --time-str="%H:%M"
    elif command -v slock &>/dev/null; then
        slock
    else
        notify-send -u critical "ohmychadwm" "$(_t "No screen locker found. Install slock or i3lock.")"
    fi
}

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------
show_info_menu() {
    while true; do
        local -a rows=(
            system   "$(_t "System")"
            btop     "Btop"
            df       "$(_t "Disk overview")"
            ncdu     "$(_t "Disk explorer")"
            temp     "$(_t "Temperatures")"
        )
        upower -e 2>/dev/null | grep -qi bat && rows+=(battery "$(_t "Battery")")
        rows+=(logs "$(_t "Logs")")

        case $(pick "$(_t "Info")" "${rows[@]}") in
            system)  present_terminal "inxi -Fxxx"; return 0 ;;
            btop)    command -v btop &>/dev/null || install "btop" "btop"; present_terminal "btop"; return 0 ;;
            df)      present_terminal "df -h | (read -r header; echo \"\$header\"; sort)"; return 0 ;;
            ncdu)    command -v ncdu &>/dev/null || install "ncdu" "ncdu"; present_terminal "ncdu ${HOME}"; return 0 ;;
            temp)    OHM_T_HINT="$(_t "Install the sensors first: sudo pacman -S lm_sensors && sudo sensors-detect")"; export OHM_T_HINT; present_terminal "sensors 2>/dev/null || echo \"\$OHM_T_HINT\"" ; return 0 ;;
            battery) present_terminal "upower -i \$(upower -e | grep -i bat | head -1)"; return 0 ;;
            logs)    show_logs_menu || continue; return 0 ;;
            *)       return 1 ;;
        esac
    done
}

show_logs_menu() {
    case $(pick "$(_t "Logs")" \
            system "$(_t "System log")" \
            boot   "$(_t "Boot log")" \
            errors "$(_t "Errors only")" \
            kernel "$(_t "Kernel (dmesg)")" \
            follow "$(_t "Follow live")") in
        system) plain_terminal "journalctl -n 200 --no-pager | less -R"; return 0 ;;
        boot)   plain_terminal "journalctl -b --no-pager | less -R"; return 0 ;;
        errors) plain_terminal "journalctl -p err -b --no-pager | less -R"; return 0 ;;
        kernel) plain_terminal "sudo dmesg --color=always | less -R"; return 0 ;;
        follow) plain_terminal "journalctl -f"; return 0 ;;
        *)      return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# MAIN MENU
# ---------------------------------------------------------------------------
show_main_menu() {
    while true; do
        case $(pick "ohmychadwm" \
                apps       "$(_t "Apps")" \
                appearance "$(_t "Appearance")" \
                learn      "$(_t "Learn")" \
                trigger    "$(_t "Trigger")" \
                setup      "$(_t "Setup")" \
                install    "$(_t "Install")" \
                remove     "$(_t "Remove")" \
                update     "$(_t "Update")" \
                info       "$(_t "Info")" \
                system     "$(_t "System")") in
            apps)       rofi -no-config -no-lazy-grab -show drun -modi drun -theme ~/.config/ohmychadwm/rofi/launcher2.rasi; break ;;
            appearance) show_appearance_menu || continue; break ;;
            learn)      show_learn_menu      || continue; break ;;
            trigger)    show_trigger_menu    || continue; break ;;
            setup)      show_setup_menu      || continue; break ;;
            install)    show_install_menu    || continue; break ;;
            remove)     show_remove_menu     || continue; break ;;
            update)     show_update_menu     || continue; break ;;
            info)       show_info_menu       || continue; break ;;
            system)     show_system_menu     || continue; break ;;
            *)          break ;;
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
        *appearance*|*style*) show_appearance_menu ;;
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
