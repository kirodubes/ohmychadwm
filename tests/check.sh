#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
#####################################################################
#
# Purpose:
#   Test ohmychadwm the way a user meets it, without touching this machine:
#   1. lint every shell script (bash -n, shellcheck errors)
#   2. build chadwm against every theme and against the shipped default config
#   3. build slstatus with every status module switched on
#   4. run two rebuilds at once (the second must wait, not wreck the first)
#   5. click through every row of the Super+Alt+Space menu in a throwaway home
#      (tests/menu_crawl.py) and report each action that errors or does nothing
#   Builds run in temporary copies; nothing is installed. --quick skips step 2.
#
# Why: menu entries broke silently (Tags, Border, Gaps, Master area, Back to
#   default) because nothing exercised them after the config moved to THEME_* defines.
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
REPO="$(dirname "$SCRIPT_DIR")"
OHM="${REPO}/etc/skel/.config/ohmychadwm"
FAILED=0
WORK=""

cleanup() {
    [[ -n "$WORK" ]] && rm -rf "$WORK"
}

fail() {
    echo "${RED}FAIL${RESET}  $1"
    FAILED=$((FAILED + 1))
}

lint_scripts() {
    log_info "1. Lint shell scripts"
    local f count=0
    while IFS= read -r -d '' f; do
        count=$((count + 1))
        bash -n "$f" 2>/dev/null || fail "syntax: ${f#"$REPO"/}"
        if command -v shellcheck >/dev/null 2>&1; then
            shellcheck -S error "$f" >/dev/null 2>&1 || fail "shellcheck error: ${f#"$REPO"/}"
        fi
    done < <(find "$REPO" -path "$REPO/.git" -prune -o -type f -name '*.sh' -print0)
    command -v shellcheck >/dev/null 2>&1 || log_warn "shellcheck not installed — only bash -n was run"
    echo "${CYAN}${count} scripts checked${RESET}"
}

# Build one chadwm copy: $1 = label, $2 = config file to use, $3 = theme name or "" to keep the include
build_chadwm() {
    local label="$1" config="$2" theme="$3"
    local dir
    dir="$(mktemp -d "${WORK}/chadwm-XXXX")"
    cp -a "${OHM}/chadwm/." "$dir/"
    cp "$config" "$dir/config.def.h"
    if [[ -n "$theme" ]]; then
        sed -i 's|^#include "themes/.*\.h"|//&|' "$dir/config.def.h"
        sed -i "s|^//\(//\)*#include \"themes/${theme}\.h\"|#include \"themes/${theme}.h\"|" "$dir/config.def.h"
        grep -q "^#include \"themes/${theme}\.h\"" "$dir/config.def.h" ||
            echo "#include \"themes/${theme}.h\"" > "$dir/.missing-include"
    fi
    if [[ -f "$dir/.missing-include" ]]; then
        echo "FAIL ${label}: theme not listed in config.def.h"
    elif ! make -C "$dir" -s >"$dir/build.log" 2>&1; then
        echo "FAIL ${label}: $(grep -m1 'error' "$dir/build.log" || tail -1 "$dir/build.log")"
    else
        echo "ok ${label}"
    fi
    rm -rf "$dir"
}

build_themes() {
    log_info "2. Build chadwm with every theme and with the shipped default config"
    export -f build_chadwm
    export OHM WORK
    local results
    results="$(
        {
            printf '%s\0%s\0%s\0' "config.def.h.default" "${OHM}/chadwm/config.def.h.default" ""
            local t
            for t in "${OHM}"/chadwm/themes/*.h; do
                t="$(basename "$t" .h)"
                printf '%s\0%s\0%s\0' "theme ${t}" "${OHM}/chadwm/config.def.h" "$t"
            done
        } | xargs -0 -n 3 -P "$(nproc)" bash -c 'build_chadwm "$1" "$2" "$3"' _
    )"
    local line
    while IFS= read -r line; do
        [[ "$line" == FAIL* ]] && fail "${line#FAIL }"
    done <<< "$results"
    echo "${CYAN}$(grep -c '^ok' <<< "$results") of $(grep -c . <<< "$results") builds passed${RESET}"
}

build_slstatus() {
    log_info "3. Build slstatus with every module switched on"
    local dir
    dir="$(mktemp -d "${WORK}/slstatus-XXXX")"
    cp -a "${OHM}/slstatus/." "$dir/"
    sed -i 's|^\(\s*\)//{ |\1{ |' "$dir/config.def.h"
    if make -C "$dir" -s >"$dir/build.log" 2>&1; then
        echo "ok slstatus"
    else
        fail "slstatus: $(grep -m1 'error' "$dir/build.log" || tail -1 "$dir/build.log")"
    fi
}

race_rebuilds() {
    log_info "4. Two rebuilds at once (two menu choices in quick succession)"
    local dir
    dir="$(mktemp -d "${WORK}/race-XXXX")"
    cp -a "${OHM}/chadwm" "$dir/"
    mkdir "$dir/bin" "$dir/inst"
    # sudo stub: install into the temp folder, never the system
    printf '#!/bin/bash\n"$@" PREFIX=%s/inst\n' "$dir" > "$dir/bin/sudo"
    chmod +x "$dir/bin/sudo"
    (cd "$dir/chadwm" && PATH="$dir/bin:$PATH" XDG_RUNTIME_DIR="$dir" bash rebuild.sh </dev/null >"$dir/a.log" 2>&1) &
    sleep 0.3
    (cd "$dir/chadwm" && PATH="$dir/bin:$PATH" XDG_RUNTIME_DIR="$dir" bash rebuild.sh </dev/null >"$dir/b.log" 2>&1) &
    local ok=0 pid
    for pid in $(jobs -p); do wait "$pid" || ok=1; done
    if (( ok == 0 )) && [[ -x "$dir/inst/bin/ohmychadwm" ]]; then
        echo "ok both rebuilds finished"
    else
        fail "racing rebuilds: $(grep -h -m1 -E 'error|No such file' "$dir/a.log" "$dir/b.log" | head -1)"
    fi
}

crawl_menu() {
    log_info "5. Click through every row of the system menu, then the scenarios"
    local out rc
    out="$(python3 -I "${SCRIPT_DIR}/menu_crawl.py" 2>&1)" && rc=0 || rc=$?
    grep -v '^ok ' <<< "$out" || true
    (( rc == 0 )) || fail "menu crawl (see FAIL lines above)"
}

#####################################################################
# Main
#####################################################################
main() {
    local quick=0
    [[ "${1:-}" == "--quick" ]] && quick=1

    log_section "ohmychadwm checks"
    WORK="$(mktemp -d)"
    trap cleanup EXIT

    lint_scripts
    if (( quick )); then
        log_warn "--quick: theme builds skipped"
    else
        build_themes
    fi
    build_slstatus
    race_rebuilds
    crawl_menu

    if (( FAILED > 0 )); then
        log_error "${FAILED} check(s) failed"
        exit 1
    fi
    log_success "$(basename "$0") done"
}

main "$@"
