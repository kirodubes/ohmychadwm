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
#   Show the ohmychadwm system menu in every shipped language, one after
#   the other, on the running ohmychadwm session: English first, then each
#   language in menu/locale/, each for a few seconds. Made for a showcase
#   video (start the screen recorder, then this script) and for a quick
#   visual check of the translations, CJK fonts included.
#   Options:
#     -i <seconds>  how long each language stays open (default 3)
#     -s <folder>   also save a screenshot per language (needs maim)
#     -m <menu.sh>  the menu to show (default ~/.config/ohmychadwm/menu/ohmychadwm-menu.sh)
#   It only sends Escape to close each menu, and stops when another window
#   takes focus, so it never types into anything else.
#
# Why: one place to replay the language round, for videos and after
#   every translation change.
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
INTERVAL=3
SHOTS=""
MENU="${HOME}/.config/ohmychadwm/menu/ohmychadwm-menu.sh"

usage() {
    echo "Usage: $(basename "$0") [-i seconds] [-s screenshot-folder] [-m menu.sh]"
}

parse_args() {
    local opt
    while getopts ":i:s:m:h" opt; do
        case "$opt" in
            i) INTERVAL="$OPTARG" ;;
            s) SHOTS="$OPTARG" ;;
            m) MENU="$OPTARG" ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
}

check_session() {
    export DISPLAY="${DISPLAY:-:0}"
    if [[ -z "${XAUTHORITY:-}" ]]; then
        # Started over ssh: SDDM keeps the cookie in /tmp/xauth_*
        XAUTHORITY="$(find /tmp -maxdepth 1 -name 'xauth_*' -user "$(id -u)" 2>/dev/null | head -1)"
        export XAUTHORITY
    fi
    local tool
    for tool in xdotool rofi; do
        command -v "$tool" >/dev/null 2>&1 || { log_error "$tool is needed"; exit 1; }
    done
    [[ -n "$SHOTS" ]] && ! command -v maim >/dev/null 2>&1 && { log_error "maim is needed for -s"; exit 1; }
    [[ -f "$MENU" ]] || { log_error "Menu not found: $MENU"; exit 1; }
    [[ -d "$(dirname "$MENU")/locale" ]] || log_warn "No locale folder next to the menu — only English will show"
}

# English first, then the translation playbook's order; any other shipped language after that.
languages() {
    local order=(nl de es fr pt_BR ru hu it tr pl ja zh_CN ro) dir lang
    dir="$(dirname "$MENU")/locale"
    echo en
    for lang in "${order[@]}"; do
        [[ -d "$dir/$lang" ]] && echo "$lang"
    done
    find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort |
        grep -vxF -f <(printf '%s\n' "${order[@]}") || true
}

focused_window() {
    xdotool getactivewindow 2>/dev/null || true
}

show_all() {
    local lang shown=0
    [[ -n "$SHOTS" ]] && mkdir -p "$SHOTS"
    log_section "Showing the menu in every language, ${INTERVAL}s each"
    for lang in $(languages); do
        if [[ -n "$(focused_window)" ]]; then
            log_warn "A window has focus — stopped before ${lang} (close or unfocus it and run again)"
            break
        fi
        LANGUAGE="$lang" setsid bash "$MENU" </dev/null >/dev/null 2>&1 &
        sleep 1
        [[ -n "$SHOTS" ]] && maim "$SHOTS/menu-${lang}.png"
        sleep "$(awk -v i="$INTERVAL" 'BEGIN { s = i - 1; print (s > 0 ? s : 0) }')"
        if pgrep -x rofi >/dev/null; then
            xdotool key Escape
        fi
        sleep 0.4
        echo "${CYAN}${lang}${RESET}"
        shown=$((shown + 1))
    done
    echo "${shown} languages shown"
}

#####################################################################
# Main
#####################################################################
main() {
    parse_args "$@"
    check_session
    show_all
    log_success "$(basename "$0") done"
}

main "$@"
