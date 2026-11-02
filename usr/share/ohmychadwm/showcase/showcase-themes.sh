#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
# Purpose:
#   Show several chadwm themes one after the other on the running
#   ohmychadwm session. For every theme it switches the theme include in
#   config.def.h, merges the theme's Xresources and wallpaper when it has
#   them, rebuilds chadwm in a visible terminal, installs it and restarts
#   chadwm live (Super+Shift+R), then holds the theme a few seconds.
#   At the end it goes back to the theme you started with.
#   Usage: showcase-themes.sh [-i seconds] [-k] [theme …]
#     theme …       themes to show (default: everforest rosepine tiger mars dracula)
#     -i <seconds>  how long each theme stays on screen (default 8)
#     -k            keep the last theme instead of going back to the first one
#   It asks for your sudo password once, for "make install". Over ssh
#   (no terminal) set SUDO_ASKPASS to a program that prints it.
#
# Why: a replayable theme round for showcase videos, without picking
#   five themes by hand from the menu and rebooting after each one.
#
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

#####################################################################
# Colors
#####################################################################
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 6)"
    RESET="$(tput sgr0)"
else
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" RESET=""
fi

#####################################################################
# Logging
#####################################################################
log_section() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

log_info() {
    echo
    echo "${BLUE}############################################################################${RESET}"
    echo "$1"
    echo "${BLUE}############################################################################${RESET}"
    echo
}

log_warn() {
    echo
    echo "${YELLOW}############################################################################${RESET}"
    echo "$1"
    echo "${YELLOW}############################################################################${RESET}"
    echo
}

log_error() {
    echo
    echo "${RED}############################################################################${RESET}"
    echo "$1"
    echo "${RED}############################################################################${RESET}"
    echo
}

log_success() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

#####################################################################
# Error handling
#####################################################################
on_error() {
    local line="$1"
    local cmd="$2"
    echo "${RED}ERROR on line ${line}: ${cmd}${RESET}"
    sleep 10
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

#####################################################################
# Functions
#####################################################################
HOLD=8
KEEP_LAST=0
THEMES=()
CFG="${OHMYCHADWM_CONFIG:-${HOME}/.config/ohmychadwm}"
CONF="${CFG}/chadwm/config.def.h"
SUDO=(sudo)

usage() {
    echo "Usage: $(basename "$0") [-i seconds] [-k] [theme …]"
}

parse_args() {
    local opt
    while getopts ":i:kh" opt; do
        case "$opt" in
            i) HOLD="$OPTARG" ;;
            k) KEEP_LAST=1 ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    THEMES=("$@")
    if (( ${#THEMES[@]} == 0 )); then
        THEMES=(everforest rosepine tiger mars dracula)
    fi
}

check_session() {
    export DISPLAY="${DISPLAY:-:0}"
    if [[ -z "${XAUTHORITY:-}" ]]; then
        # Started over ssh: SDDM keeps the cookie in /tmp/xauth_*
        XAUTHORITY="$(find /tmp -maxdepth 1 -name 'xauth_*' -user "$(id -u)" 2>/dev/null | head -1)"
        export XAUTHORITY
    fi
    local tool theme
    for tool in xdotool alacritty make; do
        command -v "$tool" >/dev/null 2>&1 || { log_error "$tool is needed"; exit 1; }
    done
    pgrep -x ohmychadwm >/dev/null || { log_error "ohmychadwm is not running"; exit 1; }
    [[ -f "$CONF" ]] || { log_error "Not found: $CONF"; exit 1; }
    for theme in "${THEMES[@]}"; do
        [[ -f "${CFG}/chadwm/themes/${theme}.h" ]] || { log_error "Theme not found: ${theme}"; exit 1; }
    done
}

# Ask once now, so the password prompt is not in the middle of the video.
check_sudo() {
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        SUDO=(sudo -A)
    fi
    "${SUDO[@]}" -v || { log_error "sudo is needed for make install"; exit 1; }
}

current_theme() {
    grep -oP '^#include "themes/\K[^"]+(?=\.h")' "$CONF" | head -1
}

set_theme() {
    local theme="$1"
    sed -i "s|^#include \"themes/\(.*\)\.h\"|//#include \"themes/\1.h\"|" "$CONF"
    sed -i "s|^//#include \"themes/${theme}\.h\"|#include \"themes/${theme}.h\"|" "$CONF"
    if [[ -f "${CFG}/chadwm/themes/${theme}.Xresources" ]]; then
        xrdb -merge "${CFG}/chadwm/themes/${theme}.Xresources"
    fi
    if [[ -f "${CFG}/chadwm/themes/alacritty/${theme}.toml" ]]; then
        cp "${CFG}/chadwm/themes/alacritty/${theme}.toml" "${HOME}/.config/alacritty/colors.toml"
    fi
    if [[ -f "${CFG}/wallpapers/${theme}.jpg" ]] && command -v feh >/dev/null 2>&1; then
        feh --bg-fill "${CFG}/wallpapers/${theme}.jpg"
    fi
}

# The build runs in a terminal so it shows in the video; install runs here, where sudo is cached.
build_and_restart() {
    local status old_pid _
    status="$(mktemp)"
    alacritty -e bash -c "cd '${CFG}/chadwm' && make clean && make; echo \$? > '${status}'; sleep 1.5"
    if [[ "$(cat "$status")" != "0" ]]; then
        rm -f "$status"
        log_error "Build failed — nothing installed"
        return 1
    fi
    rm -f "$status"
    (cd "${CFG}/chadwm" && "${SUDO[@]}" make install >/dev/null && make clean >/dev/null)
    old_pid="$(pgrep -n -x ohmychadwm)"
    xdotool key super+shift+r
    for _ in $(seq 50); do
        if [[ "$(pgrep -n -x ohmychadwm || true)" != "$old_pid" ]]; then
            return 0
        fi
        sleep 0.1
    done
    log_warn "chadwm did not restart — press Super+Shift+R"
}

show_theme() {
    local theme="$1"
    echo "${CYAN}${theme}${RESET}"
    notify-send -t 3000 "ohmychadwm" "Theme: ${theme}" 2>/dev/null || true
    set_theme "$theme"
    build_and_restart
}

#####################################################################
# Main
#####################################################################
main() {
    local start theme
    parse_args "$@"
    check_session
    check_sudo
    start="$(current_theme)"
    log_section "Showing ${#THEMES[@]} themes, ${HOLD}s each"
    for theme in "${THEMES[@]}"; do
        show_theme "$theme"
        sleep "$HOLD"
    done
    notify-send -u critical "ohmychadwm" "Theme showcase done" 2>/dev/null || true
    if (( ! KEEP_LAST )) && [[ -n "$start" && "$start" != "$(current_theme)" ]]; then
        log_info "Back to ${start}"
        sleep 3
        set_theme "$start"
        build_and_restart
    fi
    log_success "$(basename "$0") done"
}

main "$@"
