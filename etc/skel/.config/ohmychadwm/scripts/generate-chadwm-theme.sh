#!/usr/bin/env bash
# generate-chadwm-theme.sh
# Create a chadwm theme from the current wallpaper colors.

set -euo pipefail

THEMES_DIR="$HOME/.config/ohmychadwm/chadwm/themes"
CONFIG="$HOME/.config/ohmychadwm/chadwm/config.def.h"

# ── terminal colors ──────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'; NC='\033[0m'

header() { echo -e "\n${C}${W}$*${NC}"; }
ask()    { echo -e "${Y}$*${NC}"; }
ok()     { echo -e "${G}✔ $*${NC}"; }
err()    { echo -e "${R}✘ $*${NC}" >&2; }

# ── detect current wallpaper ─────────────────────────────────────────────────
WALLPAPERS_DIR="$HOME/.config/ohmychadwm/wallpapers"

detect_wallpaper() {
    local wp=""

    # 1. variety
    if [[ -f "$HOME/.config/variety/wallpaper/wallpaper.jpg" ]]; then
        wp="$HOME/.config/variety/wallpaper/wallpaper.jpg"
    fi

    # 2. .fehbg (covers feh-set wallpapers including ohmychadwm/wallpapers/)
    if [[ -z "$wp" && -f "$HOME/.fehbg" ]]; then
        wp=$(grep -oP "(?<='|\")/[^'\"]+(?='|\")" "$HOME/.fehbg" | head -1)
    fi

    # 3. pick from ohmychadwm wallpapers folder
    if [[ -z "$wp" || ! -f "$wp" ]]; then
        local wp_dir="$HOME/.config/ohmychadwm/wallpapers"
        if [[ -d "$wp_dir" ]]; then
            mapfile -t images < <(find "$wp_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) | sort)
            if [[ ${#images[@]} -gt 0 ]]; then
                ask "Could not detect current wallpaper. Pick one:"
                local picked_wp
                picked_wp=$(printf '%s\n' "${images[@]}" \
                    | fzf --prompt="Wallpaper > " \
                          --height=40% \
                          --layout=reverse \
                          --border \
                          --preview="file {}" \
                          2>/dev/null) || true
                [[ -n "$picked_wp" ]] && wp="$picked_wp"
            fi
        fi
    fi

    # 4. manual fallback
    if [[ -z "$wp" || ! -f "$wp" ]]; then
        ask "Could not detect wallpaper automatically. Enter path:"
        read -rp "> " wp
    fi

    if [[ ! -f "$wp" ]]; then
        err "File not found: $wp"
        exit 1
    fi
    echo "$wp"
}

# ── extract N dominant colors, sorted darkest → lightest ─────────────────────
extract_colors() {
    local wallpaper="$1"
    local count="${2:-12}"

    magick "$wallpaper" \
        -resize 200x200^ -gravity Center -extent 200x200 \
        +dither -colors "$count" -unique-colors -depth 8 txt:- \
        2>/dev/null \
        | grep -oE '#[0-9A-Fa-f]{6}' \
        | head -"$count"
}

# luminance of a hex color (0–255 scale)
luminance() {
    local hex="${1#'#'}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo $(( (299*r + 587*g + 114*b) / 1000 ))
}

# saturation of a hex color (0–255 scale, higher = more vivid)
saturation() {
    local hex="${1#'#'}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    local max min
    max=$r
    if [[ $g -gt $max ]]; then max=$g; fi
    if [[ $b -gt $max ]]; then max=$b; fi
    min=$r
    if [[ $g -lt $min ]]; then min=$g; fi
    if [[ $b -lt $min ]]; then min=$b; fi
    if [[ $max -eq 0 ]]; then
        echo 0
    else
        echo $(( (max - min) * 255 / max ))
    fi
}

# darken a hex color by a fixed amount (clamps to 0)
darken() {
    local hex="${1#'#'}" amt="${2:-20}"
    local r=$(( 16#${hex:0:2} - amt )); r=$(( r < 0 ? 0 : r ))
    local g=$(( 16#${hex:2:2} - amt )); g=$(( g < 0 ? 0 : g ))
    local b=$(( 16#${hex:4:2} - amt )); b=$(( b < 0 ? 0 : b ))
    printf '#%02x%02x%02x' $r $g $b
}

# lighten a hex color by a fixed amount (clamps to 255)
lighten() {
    local hex="${1#'#'}" amt="${2:-20}"
    local r=$(( 16#${hex:0:2} + amt )); r=$(( r > 255 ? 255 : r ))
    local g=$(( 16#${hex:2:2} + amt )); g=$(( g > 255 ? 255 : g ))
    local b=$(( 16#${hex:4:2} + amt )); b=$(( b > 255 ? 255 : b ))
    printf '#%02x%02x%02x' $r $g $b
}

# WCAG contrast ratio between two hex colors, e.g. 4.50
contrast_ratio() {
    local a="${1#'#'}" b="${2#'#'}"
    awk -v r1=$((16#${a:0:2})) -v g1=$((16#${a:2:2})) -v b1=$((16#${a:4:2})) \
        -v r2=$((16#${b:0:2})) -v g2=$((16#${b:2:2})) -v b2=$((16#${b:4:2})) '
        function lin(c) { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
        function lum(r, g, b) { return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }
        BEGIN {
            x = lum(r1, g1, b1); y = lum(r2, g2, b2)
            if (x < y) { t = x; x = y; y = t }
            printf "%.2f\n", (x + 0.05) / (y + 0.05)
        }'
}

# move a foreground color toward white (dark bg) or black (light bg) until it reaches
# the given contrast ratio against bg; lighten-only made text unreadable on light bars
ensure_contrast() {
    local fg="$1" bg="$2" min="$3" step=lighten end="#ffffff"
    if awk -v w="$(contrast_ratio "#ffffff" "$bg")" -v k="$(contrast_ratio "#000000" "$bg")" \
        'BEGIN { exit !(k > w) }'; then
        step=darken; end="#000000"
    fi
    while awk -v r="$(contrast_ratio "$fg" "$bg")" -v m="$min" 'BEGIN { exit !(r < m) }'; do
        [[ "$fg" == "$end" ]] && break
        fg=$("$step" "$fg" 8)
    done
    echo "$fg"
}

# sort colors by luminance (darkest first), output one per line
sort_by_luminance() {
    local colors=("$@")
    local pairs=()
    for c in "${colors[@]}"; do
        pairs+=("$(luminance "$c") $c")
    done
    printf '%s\n' "${pairs[@]}" | sort -n | awk '{print $2}'
}

# pick the most saturated color from a list
most_saturated() {
    local best="" best_sat=-1
    for c in "$@"; do
        local s; s=$(saturation "$c")
        if [[ $s -gt $best_sat ]]; then best_sat=$s; best=$c; fi
    done
    echo "$best"
}

# ── build color palette from sorted list ─────────────────────────────────────
build_palette() {
    local -a sorted=("$@")
    local n=${#sorted[@]}

    # background: darkest color, with a slightly lighter border variant
    BG="${sorted[0]}"
    BR=$(darken "$BG" -12)   # slightly lighter than bg for borders

    # dim foreground: near-darkest, for empty tags and inactive window text
    local dim_idx=$(( n / 8 ))
    if [[ $dim_idx -lt 1 ]]; then dim_idx=1; fi
    DIM_FG="${sorted[$dim_idx]}"

    # muted normal foreground: ~1/4 from darkest
    local idx=$(( n / 4 ))
    NORM_FG="${sorted[$idx]}"

    # bright foreground / title: ~90% from darkest
    local bright_idx=$(( n * 9 / 10 ))
    if [[ $bright_idx -ge $n ]]; then bright_idx=$(( n - 1 )); fi
    BRIGHT="${sorted[$bright_idx]}"

    # accent / selection: most saturated of the mid-range colors
    local mid_start=$(( n / 4 ))
    local mid_end=$(( n * 3 / 4 ))
    local mids=("${sorted[@]:$mid_start:$(( mid_end - mid_start ))}")
    ACCENT=$(most_saturated "${mids[@]}")

    # 10 tag colors: spread across the bright half of the palette
    # (occupied tags must be visibly brighter than empty tags which use DIM_FG)
    local range_start=$(( n / 2 ))
    local range_end=$(( n - 1 ))
    local range_colors=("${sorted[@]:$range_start:$(( range_end - range_start + 1 ))}")
    local rc=${#range_colors[@]}

    TAG=()
    for i in {0..9}; do
        local pick=$(( i * rc / 10 ))
        if [[ $pick -ge $rc ]]; then pick=$(( rc - 1 )); fi
        TAG+=("${range_colors[$pick]}")
    done

    # ── enforce minimum luminance step between adjacent tags ─────────────────
    # tags are ordered dark→light; each must be ≥8 lum units above the previous
    local min_tag_step=8
    local distinct_tags=("${TAG[0]}")
    local prev_lum
    prev_lum=$(luminance "${TAG[0]}")
    for i in {1..9}; do
        local t="${TAG[$i]}"
        local curr_lum
        curr_lum=$(luminance "$t")
        while (( curr_lum - prev_lum < min_tag_step )); do
            t=$(lighten "$t" 8)
            curr_lum=$(luminance "$t")
            if [[ "$t" == "#ffffff" ]]; then break; fi
        done
        distinct_tags+=("$t")
        prev_lum=$curr_lum
    done
    TAG=("${distinct_tags[@]}")

    # ── enforce contrast against the bar (WCAG ratios) — runs last so nothing undoes it
    DIM_FG=$(ensure_contrast "$DIM_FG" "$BG" 1.2)
    NORM_FG=$(ensure_contrast "$NORM_FG" "$BG" 3.0)   # status text + other monitor's title
    BRIGHT=$(ensure_contrast "$BRIGHT" "$BG" 4.5)
    ACCENT=$(ensure_contrast "$ACCENT" "$BG" 1.5)
    local new_tags=()
    for t in "${TAG[@]}"; do
        new_tags+=("$(ensure_contrast "$t" "$BG" 2.5)")
    done
    TAG=("${new_tags[@]}")

    # ── SchemeMenu fg: must be brighter than every tag color ─────────────────
    # find the highest luminance among all tag colors
    local max_tag_lum=0
    for t in "${TAG[@]}"; do
        local lum; lum=$(luminance "$t")
        if [[ $lum -gt $max_tag_lum ]]; then
            max_tag_lum=$lum
        fi
    done
    # start from BRIGHT and keep lightening until it exceeds all tags
    MENU_FG="$BRIGHT"
    while [[ $(luminance "$MENU_FG") -le $max_tag_lum ]]; do
        MENU_FG=$(lighten "$MENU_FG" 8)
        if [[ "$MENU_FG" == "#ffffff" ]]; then break; fi
    done
    # the menu button sits on the bar too (rofi gets its own lighter copy in update_config)
    MENU_FG=$(ensure_contrast "$MENU_FG" "$BG" 3.0)
}

# ── truecolor palette preview ─────────────────────────────────────────────────
_color_block() {
    local hex="${1#'#'}"
    [[ ${#hex} -eq 6 ]] || return
    local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    printf '\e[48;2;%d;%d;%dm    \e[0m \e[38;2;%d;%d;%dm%s\e[0m  %s\n' \
        "$r" "$g" "$b" "$r" "$g" "$b" "#${hex}" "$2"
}

show_palette_preview() {
    echo
    echo -e "${W}── Theme palette ────────────────────────────────────${NC}"
    _color_block "${BG}"     "background"
    _color_block "${BR}"     "border"
    _color_block "${DIM_FG}" "inactive"
    _color_block "${ACCENT}" "selection"
    _color_block "${BRIGHT}" "title"
    _color_block "${MENU_FG}" "menu fg"
    printf '  tags  '
    for t in "${TAG[@]}"; do
        local h="${t#'#'}"
        [[ ${#h} -eq 6 ]] || continue
        local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
        printf '\e[48;2;%d;%d;%dm  \e[0m' "$r" "$g" "$b"
    done
    echo
    echo
}

# ── tweak individual palette colors ──────────────────────────────────────────
_tweak_line() {
    local label="$1" hex="$2" desc="$3"
    local h="${hex#'#'}"
    if [[ ${#h} -eq 6 ]]; then
        local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
        printf '\e[48;2;%d;%d;%dm  \e[0m %-9s %s  %s' "$r" "$g" "$b" "$label" "$hex" "$desc"
    else
        printf '     %-9s %s  %s' "$label" "$hex" "$desc"
    fi
}

tweak_palette() {
    while true; do
        local choice
        choice=$(printf '%s\n' \
            "$(_tweak_line BG      "$BG"       "background")" \
            "$(_tweak_line Border  "$BR"       "border")" \
            "$(_tweak_line Dim     "$DIM_FG"   "inactive / empty tags")" \
            "$(_tweak_line Normal  "$NORM_FG"  "normal foreground")" \
            "$(_tweak_line Accent  "$ACCENT"   "selection / active window")" \
            "$(_tweak_line Bright  "$BRIGHT"   "title text")" \
            "$(_tweak_line MenuFG  "$MENU_FG"  "menu foreground")" \
            "$(_tweak_line Tag1    "${TAG[0]}"  "")" \
            "$(_tweak_line Tag2    "${TAG[1]}"  "")" \
            "$(_tweak_line Tag3    "${TAG[2]}"  "")" \
            "$(_tweak_line Tag4    "${TAG[3]}"  "")" \
            "$(_tweak_line Tag5    "${TAG[4]}"  "")" \
            "$(_tweak_line Tag6    "${TAG[5]}"  "")" \
            "$(_tweak_line Tag7    "${TAG[6]}"  "")" \
            "$(_tweak_line Tag8    "${TAG[7]}"  "")" \
            "$(_tweak_line Tag9    "${TAG[8]}"  "")" \
            "$(_tweak_line Tag10   "${TAG[9]}"  "")" \
            "  ✔  Done — continue" \
            | fzf --ansi \
                  --prompt="Tweak color > " \
                  --height=60% \
                  --layout=reverse \
                  --border \
                  2>/dev/null) || break

        [[ "$choice" == *"Done"* ]] && break

        # extract label (second token after the swatch)
        local label
        label=$(echo "$choice" | awk '{print $1}')

        ask "New hex for $label (e.g. #a1b2c3), Enter to cancel:"
        read -rp "> " new_hex
        [[ -z "$new_hex" ]] && continue
        new_hex="#${new_hex#'#'}"
        if ! [[ "$new_hex" =~ ^#[0-9a-fA-F]{6}$ ]]; then
            err "Invalid hex: $new_hex"
            continue
        fi

        case "$label" in
            BG)     BG="$new_hex" ;;
            Border) BR="$new_hex" ;;
            Dim)    DIM_FG="$new_hex" ;;
            Normal) NORM_FG="$new_hex" ;;
            Accent) ACCENT="$new_hex" ;;
            Bright) BRIGHT="$new_hex" ;;
            MenuFG) MENU_FG="$new_hex" ;;
            Tag1)   TAG[0]="$new_hex" ;;
            Tag2)   TAG[1]="$new_hex" ;;
            Tag3)   TAG[2]="$new_hex" ;;
            Tag4)   TAG[3]="$new_hex" ;;
            Tag5)   TAG[4]="$new_hex" ;;
            Tag6)   TAG[5]="$new_hex" ;;
            Tag7)   TAG[6]="$new_hex" ;;
            Tag8)   TAG[7]="$new_hex" ;;
            Tag9)   TAG[8]="$new_hex" ;;
            Tag10)  TAG[9]="$new_hex" ;;
        esac

        ok "$label → $new_hex"
        show_palette_preview
    done
}

# ── interactive questions ─────────────────────────────────────────────────────
ask_questions() {
    header "── chadwm theme generator ──────────────────────────────"
    echo -e "${W}Wallpaper:${NC} $WALLPAPER"
    echo -e "${W}Extracted ${#SORTED[@]} colors${NC}"
    echo

    # name
    # names registered in config.def.h must not be overwritten
    local -a DEFAULT_NAMES
    mapfile -t DEFAULT_NAMES < <(grep -oP '(?<=themes/)[^"]+(?=\.h")' "$CONFIG")

    while true; do
        ask "Theme name (lowercase, no spaces, e.g. 'savannah'):"
        read -rp "> " THEME_NAME
        THEME_NAME="${THEME_NAME,,}"
        THEME_NAME="${THEME_NAME// /_}"
        if [[ -z "$THEME_NAME" ]]; then
            err "Name cannot be empty."
            continue
        fi
        local is_default=0
        for d in "${DEFAULT_NAMES[@]}"; do
            if [[ "$THEME_NAME" == "$d" ]]; then is_default=1; break; fi
        done
        if [[ $is_default -eq 1 ]]; then
            err "'$THEME_NAME' is a built-in theme and cannot be overwritten. Choose another name."
            continue
        fi
        if [[ -f "$THEMES_DIR/$THEME_NAME.h" ]]; then
            ask "Theme '$THEME_NAME' already exists. Overwrite? [y/N]:"
            read -rp "> " ow
            if [[ "$ow" =~ ^[Yy]$ ]]; then break; else continue; fi
        fi
        break
    done

    # bar position
    ask "Bar position — (t)op or (b)ottom? [T/b]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[Bb]$ ]]; then
        THEME_TOPBAR=0
    else
        THEME_TOPBAR=1
    fi

    # gaps
    ask "Gap size between windows in pixels? [0-20, default 5]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans <= 20 )); then
        THEME_GAPS=$ans
    else
        THEME_GAPS=5
    fi

    # autohide
    ask "Auto-hide bar after how many seconds? [0 = disabled, default 0]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[0-9]+$ ]]; then
        THEME_AUTOHIDE=$ans
    else
        THEME_AUTOHIDE=0
    fi

    # systray
    ask "Show systray? [Y/n]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        THEME_SHOWSYSTRAY=0
    else
        THEME_SHOWSYSTRAY=1
    fi

    # border
    ask "Border width in pixels? [default 2]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[0-9]+$ ]]; then
        THEME_BORDER=$ans
    else
        THEME_BORDER=2
    fi

    # smartgaps
    ask "Remove gaps when only one window is open? [y/N]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        THEME_SMARTGAPS=1
    else
        THEME_SMARTGAPS=0
    fi

    # layout
    echo
    ask "Default layout? [default: dwindle]"
    echo "  0) dwindle  — fibonacci dwindle (default)"
    echo "  1) tile     — master + stack"
    echo "  2) spiral   — fibonacci spiral"
    echo "  3) deck     — master + tabbed stack"
    echo "  4) bstack   — bottom stack"
    echo "  5) bstackh  — bottom stack horizontal"
    echo "  6) grid     — grid"
    echo "  7) nrowgrid — n-row grid"
    echo "  8) horizgrid— horizontal grid"
    echo "  9) gapless  — gapless grid"
    echo " 10) center   — centered master"
    echo " 11) cfloat   — centered floating master"
    echo " 12) float    — floating"
    read -rp "> " ans
    case "$ans" in
        1|tile)      THEME_LAYOUT="LAYOUT_TILE"     ;;
        2|spiral)    THEME_LAYOUT="LAYOUT_SPIRAL"   ;;
        3|deck)      THEME_LAYOUT="LAYOUT_DECK"     ;;
        4|bstack)    THEME_LAYOUT="LAYOUT_BSTACK"   ;;
        5|bstackh)   THEME_LAYOUT="LAYOUT_BSTACKH"  ;;
        6|grid)      THEME_LAYOUT="LAYOUT_GRID"     ;;
        7|nrowgrid)  THEME_LAYOUT="LAYOUT_NROWGRID" ;;
        8|horizgrid) THEME_LAYOUT="LAYOUT_HORIZGRID";;
        9|gapless)   THEME_LAYOUT="LAYOUT_GAPLESS"  ;;
        10|center)   THEME_LAYOUT="LAYOUT_CENTER"   ;;
        11|cfloat)   THEME_LAYOUT="LAYOUT_CFLOAT"   ;;
        12|float)    THEME_LAYOUT="LAYOUT_FLOAT"    ;;
        *)           THEME_LAYOUT="LAYOUT_DWINDLE"  ;;
    esac
    ok "Layout: $THEME_LAYOUT"

    # tag style
    echo
    ask "Tag style? [default: nerd]"
    echo "  0) nerd      — nerd font icons (default)"
    echo "  1) arabic    — 1 2 3 4 5 6 7 8 9 10"
    echo "  2) roman     — I II III IV V VI VII VIII IX X"
    echo "  3) powerline — powerline glyphs"
    echo "  4) webdings  — Web Chat Edit Meld Vb Mail Video Image Files Music"
    echo "  5) japanese  — 一 二 三 四 五 六 七 八 九 十"
    echo "  6) alpha     — A B C D E F G H I J"
    echo "  7) emoji     — 👨‍💻 🌐 🖥️ 📟 📜 👋 📺 ✉️ 💬 🎮"
    echo "  8) geometric — ● ■ ▲ ◆ ◇ ★ ✗ ✓ + ○"
    echo "  9) chinese   — 壹 贰 叁 肆 伍 陆 柒 捌 玖 拾"
    echo " 10) purpose   — home chat surf media game remote code mail files misc"
    read -rp "> " ans
    case "$ans" in
        1|arabic)    THEME_TAGS="TAGS_ARABIC"    ;;
        2|roman)     THEME_TAGS="TAGS_ROMAN"     ;;
        3|powerline) THEME_TAGS="TAGS_POWERLINE" ;;
        4|webdings)  THEME_TAGS="TAGS_WEBDINGS"  ;;
        5|japanese)  THEME_TAGS="TAGS_JAPANESE"  ;;
        6|alpha)     THEME_TAGS="TAGS_ALPHA"     ;;
        7|emoji)     THEME_TAGS="TAGS_EMOJI"     ;;
        8|geometric) THEME_TAGS="TAGS_GEOMETRIC" ;;
        9|chinese)   THEME_TAGS="TAGS_CHINESE"   ;;
        10|purpose)  THEME_TAGS="TAGS_PURPOSE"   ;;
        *)           THEME_TAGS="TAGS_NERD"      ;;
    esac
    ok "Tag style: $THEME_TAGS"

    # mfact
    ask "Master area size? [0.10-0.90, default 0.50]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^0\.[0-9]+$ ]] && awk "BEGIN{exit !($ans >= 0.10 && $ans <= 0.90)}"; then
        THEME_MFACT=$ans
    else
        THEME_MFACT=0.50
    fi

    # nmaster
    ask "Number of windows in master area? [1-4, default 1]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[1-4]$ ]]; then
        THEME_NMASTER=$ans
    else
        THEME_NMASTER=1
    fi

    # font — keep defaults or customize?
    echo
    THEME_FONT="JetBrainsMono Nerd Font Mono"
    THEME_FONTSTYLE="Bold"
    THEME_FONTSIZE=13
    THEME_ICONSIZE=18
    ask "Keep default font? (JetBrainsMono Nerd Font Mono, Bold, 13, icon 18) [Y/n]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then

        # font family
        ask "Bar font — press Enter to keep default, or any key to browse:"
        read -rp "> " ans
        if [[ -n "$ans" ]]; then
            local picked
            picked=$(fc-list : family \
                | sed 's/,.*//' \
                | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
                | grep -v '^\.' \
                | sort -uf \
                | fzf \
                --prompt="Font > " \
                --height=40% \
                --layout=reverse \
                --border \
                2>/dev/null) || true
            if [[ -n "$picked" ]]; then
                THEME_FONT="$picked"
            fi
        fi
        ok "Font family: $THEME_FONT"

        # font style — query real styles for the selected font
        local styles
        styles=$(fc-list ":family=${THEME_FONT}" style 2>/dev/null \
            | grep -oP '(?<=style=)[^\n]+' \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
            | sort -u)
        local style_count
        style_count=$(echo "$styles" | grep -c .)
        if [[ $style_count -le 1 ]]; then
            # only one style available — use it automatically
            THEME_FONTSTYLE=$(echo "$styles" | head -1)
            [[ -z "$THEME_FONTSTYLE" ]] && THEME_FONTSTYLE="Bold"
            ok "Font style: $THEME_FONTSTYLE (only available style)"
        else
            local picked_style
            picked_style=$(echo "$styles" | fzf \
                --prompt="Style > " \
                --height=40% \
                --layout=reverse \
                --border \
                2>/dev/null) || true
            if [[ -n "$picked_style" ]]; then
                THEME_FONTSTYLE="$picked_style"
            fi
            ok "Font style: $THEME_FONTSTYLE"
        fi

        # font size
        ask "Font size? [default 13]:"
        read -rp "> " ans
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 6 && ans <= 72 )); then
            THEME_FONTSIZE=$ans
        fi
        ok "Font size: $THEME_FONTSIZE"

        # icon size (Nerd Font fallback for bar icons)
        ask "Bar icon size? [default 18]:"
        read -rp "> " ans
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 8 && ans <= 72 )); then
            THEME_ICONSIZE=$ans
        fi
        ok "Icon size: $THEME_ICONSIZE"

    else
        ok "Font: $THEME_FONT, $THEME_FONTSTYLE, $THEME_FONTSIZE, icon $THEME_ICONSIZE (defaults)"
    fi

    # apply scope
    FONT_CHADWM_ONLY=1
    ask "Apply font only to chadwm? [Y/n]:"
    read -rp "> " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        FONT_CHADWM_ONLY=0
    fi
}

# ── apply font to other applications ─────────────────────────────────────────
apply_font_globally() {
    header "Apply font to other applications"
    bash "${HOME}/.config/ohmychadwm/scripts/backup-originals.sh"

    # rofi font format: "Family Style Size"  (e.g. "JetBrainsMono Nerd Font Mono Bold 13")
    local rofi_font="${THEME_FONT} ${THEME_FONTSTYLE} ${THEME_FONTSIZE}"

    # ── ohmychadwm menu (ohmychadwm-menu.rasi) ───────────────────────────────
    local rasi="${HOME}/.config/ohmychadwm/menu/ohmychadwm-menu.rasi"
    ask "Apply font to ohmychadwm menu (rofi)? [Y/n]:"
    read -rp "> " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        if [[ -f "$rasi" ]]; then
            sed -i "s|font:.*\"[^\"]*\";|font:             \"${rofi_font}\";|" "$rasi"
            ok "Menu font updated → $rofi_font"
        else
            err "rasi file not found: $rasi"
        fi
    fi

    # ── alacritty ────────────────────────────────────────────────────────────
    local alacritty="${HOME}/.config/alacritty/alacritty.toml"
    ask "Apply font to Alacritty? [Y/n]:"
    read -rp "> " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        if [[ -f "$alacritty" ]]; then
            # update family in all [font.*] sections
            sed -i 's|^\(family = \)"[^"]*"|\1"'"${THEME_FONT}"'"|' "$alacritty"
            # update size (always written as float)
            sed -i 's|^\(size = \)[0-9.]*|\1'"${THEME_FONTSIZE}.0"'|' "$alacritty"
            ok "Alacritty font updated → $THEME_FONT, size ${THEME_FONTSIZE}"
        else
            err "Alacritty config not found: $alacritty"
        fi
    fi

    # ── xfce4 + gtk3/gtk4 (thunar, mousepad, and other gtk apps) ────────────
    ask "Apply font to XFCE4 / GTK apps (Thunar, etc.)? [Y/n]:"
    read -rp "> " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        # live session via xfconf (if xfce4-settings is running)
        if command -v xfconf-query &>/dev/null; then
            xfconf-query -c xsettings -p /Gtk/FontName -s "${rofi_font}"
            ok "XFCE4 GTK font updated → $rofi_font"
        fi
        # gtk-3.0 settings file
        local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
        if [[ -f "$gtk3" ]]; then
            sed -i "s|^gtk-font-name=.*|gtk-font-name=${rofi_font}|" "$gtk3"
            ok "GTK3 font updated → $rofi_font"
        fi
        # gtk-4.0 settings file
        local gtk4="${HOME}/.config/gtk-4.0/settings.ini"
        if [[ -f "$gtk4" ]]; then
            sed -i "s|^gtk-font-name=.*|gtk-font-name=${rofi_font}|" "$gtk4"
            ok "GTK4 font updated → $rofi_font"
        fi
    fi

    # ── rofi global config + launcher2 (Super+D) ────────────────────────────
    for rofi_cfg in \
        "${HOME}/.config/ohmychadwm/rofi/config.rasi" \
        "${HOME}/.config/ohmychadwm/rofi/launcher2.rasi"; do
        if [[ -f "$rofi_cfg" ]]; then
            sed -i 's|\(\s*font:\s*\)"[^"]*"|\1"'"${rofi_font}"'"|g' "$rofi_cfg"
            ok "$(basename "$rofi_cfg") font updated → $rofi_font"
        fi
    done

    # ── system rofi config (used by ctrl+alt+r / rofi-theme-selector) ────────
    local system_rofi="${HOME}/.config/rofi/config.rasi"
    if [[ -f "$system_rofi" ]]; then
        # font line may be commented out — uncomment and set it
        if grep -q '/\*.*font:' "$system_rofi"; then
            sed -i 's|/\*\s*font:.*\*/|font: "'"${rofi_font}"'";|' "$system_rofi"
        else
            sed -i 's|\(\s*font:\s*\)"[^"]*"|\1"'"${rofi_font}"'"|g' "$system_rofi"
        fi
        ok "System rofi config font updated → $rofi_font"
    fi

    # ── launcher rofi themes ─────────────────────────────────────────────────
    local launcher_dir="${HOME}/.config/ohmychadwm/launcher/rofi"
    ask "Apply font to launcher rofi themes? [Y/n]:"
    read -rp "> " ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        local updated=0
        for rasi_file in "$launcher_dir"/launcher.rasi "$launcher_dir"/keybindings.rasi "$launcher_dir"/powermenu.rasi; do
            if [[ -f "$rasi_file" ]]; then
                sed -i 's|\(\s*font:\s*\)"[^"]*"|\1"'"${rofi_font}"'"|g' "$rasi_file"
                ok "$(basename "$rasi_file") font updated → $rofi_font"
                (( updated++ )) || true
            fi
        done
        [[ $updated -eq 0 ]] && err "No launcher rasi files found in $launcher_dir"
    fi

    # ── kitty (only if installed) ────────────────────────────────────────────
    if command -v kitty &>/dev/null; then
        local kitty_conf="${HOME}/.config/kitty/kitty.conf"
        ask "Apply font to Kitty terminal? [Y/n]:"
        read -rp "> " ans
        if [[ ! "$ans" =~ ^[Nn]$ ]]; then
            if [[ -f "$kitty_conf" ]]; then
                sed -i "s|^font_family.*|font_family      ${THEME_FONT}|" "$kitty_conf"
                sed -i "s|^font_size.*|font_size        ${THEME_FONTSIZE}.0|" "$kitty_conf"
                ok "Kitty font updated → $THEME_FONT, size ${THEME_FONTSIZE}"
            else
                err "Kitty config not found: $kitty_conf"
            fi
        fi
    fi

    echo
    ok "Font settings applied."
}

# ── write theme file ──────────────────────────────────────────────────────────
write_theme() {
    local file="$THEMES_DIR/$THEME_NAME.h"

    # cycle tag colors
    local t0="${TAG[0]}" t1="${TAG[1]}" t2="${TAG[2]}" t3="${TAG[3]}" t4="${TAG[4]}"
    local t5="${TAG[5]}" t6="${TAG[6]}" t7="${TAG[7]}" t8="${TAG[8]}" t9="${TAG[9]}"

    cat > "$file" <<EOF
/* ${THEME_NAME^} — generated from wallpaper */
#define THEME_TOPBAR   $THEME_TOPBAR
#define THEME_LAYOUT   $THEME_LAYOUT
#define THEME_TAGS     $THEME_TAGS
#define THEME_GAPS     $THEME_GAPS
#define THEME_AUTOHIDE    $THEME_AUTOHIDE
#define THEME_SHOWSYSTRAY $THEME_SHOWSYSTRAY
#define THEME_BORDER      $THEME_BORDER
#define THEME_SMARTGAPS   $THEME_SMARTGAPS
#define THEME_MFACT       $THEME_MFACT
#define THEME_NMASTER     $THEME_NMASTER
#define THEME_FONT        "$THEME_FONT"
#define THEME_FONTSTYLE   "$THEME_FONTSTYLE"
#define THEME_FONTSIZE    $THEME_FONTSIZE
#define THEME_ICONSIZE    $THEME_ICONSIZE

static const char col_borderbar[]      = "$BG";

static const char SchemeNormfg[]       = "$NORM_FG";
static const char SchemeNormbg[]       = "$BG";
static const char SchemeNormbr[]       = "$BR";

static const char SchemeSelfg[]        = "$BG";
static const char SchemeSelbg[]        = "$ACCENT";
static const char SchemeSelbr[]        = "$ACCENT";

static const char SchemeTitlefg[]      = "$BRIGHT";
static const char SchemeTitlebg[]      = "$BG";
static const char SchemeTitlebr[]      = "$BG";

static const char TabSelfg[]           = "$ACCENT";
static const char TabSelbg[]           = "$BR";
static const char TabSelbr[]           = "$BG";

static const char TabNormfg[]          = "$DIM_FG";
static const char TabNormbg[]          = "$BG";
static const char TabNormbr[]          = "$BG";

static const char SchemeTagfg[]        = "$DIM_FG";
static const char SchemeTagbg[]        = "$BG";
static const char SchemeTagbr[]        = "$BG";

static const char SchemeTag1fg[]       = "$t0";
static const char SchemeTag1bg[]       = "$BG";
static const char SchemeTag1br[]       = "$BG";

static const char SchemeTag2fg[]       = "$t1";
static const char SchemeTag2bg[]       = "$BG";
static const char SchemeTag2br[]       = "$BG";

static const char SchemeTag3fg[]       = "$t2";
static const char SchemeTag3bg[]       = "$BG";
static const char SchemeTag3br[]       = "$BG";

static const char SchemeTag4fg[]       = "$t3";
static const char SchemeTag4bg[]       = "$BG";
static const char SchemeTag4br[]       = "$BG";

static const char SchemeTag5fg[]       = "$t4";
static const char SchemeTag5bg[]       = "$BG";
static const char SchemeTag5br[]       = "$BG";

static const char SchemeTag6fg[]       = "$t5";
static const char SchemeTag6bg[]       = "$BG";
static const char SchemeTag6br[]       = "$BG";

static const char SchemeTag7fg[]       = "$t6";
static const char SchemeTag7bg[]       = "$BG";
static const char SchemeTag7br[]       = "$BG";

static const char SchemeTag8fg[]       = "$t7";
static const char SchemeTag8bg[]       = "$BG";
static const char SchemeTag8br[]       = "$BG";

static const char SchemeTag9fg[]       = "$t8";
static const char SchemeTag9bg[]       = "$BG";
static const char SchemeTag9br[]       = "$BG";

static const char SchemeTag10fg[]      = "$t9";
static const char SchemeTag10bg[]      = "$BG";
static const char SchemeTag10br[]      = "$BG";

static const char SchemeLayoutfg[]     = "$ACCENT";
static const char SchemeLayoutbg[]     = "$BG";
static const char SchemeLayoutbr[]     = "$BG";

static const char SchemeBtnPrevfg[]    = "$t3";
static const char SchemeBtnPrevbg[]    = "$BG";
static const char SchemeBtnPrevbr[]    = "$BG";

static const char SchemeBtnNextfg[]    = "$t5";
static const char SchemeBtnNextbg[]    = "$BG";
static const char SchemeBtnNextbr[]    = "$BG";

static const char SchemeBtnClosefg[]   = "$t1";
static const char SchemeBtnClosebg[]   = "$BG";
static const char SchemeBtnClosebr[]   = "$BG";

static const char SchemeLayoutFFfg[]   = "$t2";
static const char SchemeLayoutFFbg[]   = "$BG";
static const char SchemeLayoutFFbr[]   = "$BG";

static const char SchemeLayoutEWfg[]   = "$t4";
static const char SchemeLayoutEWbg[]   = "$BG";
static const char SchemeLayoutEWbr[]   = "$BG";

static const char SchemeLayoutDSfg[]   = "$t1";
static const char SchemeLayoutDSbg[]   = "$BG";
static const char SchemeLayoutDSbr[]   = "$BG";

static const char SchemeLayoutTGfg[]   = "$t3";
static const char SchemeLayoutTGbg[]   = "$BG";
static const char SchemeLayoutTGbr[]   = "$BG";

static const char SchemeLayoutMSfg[]   = "$t6";
static const char SchemeLayoutMSbg[]   = "$BG";
static const char SchemeLayoutMSbr[]   = "$BG";

static const char SchemeLayoutPCfg[]   = "$t2";
static const char SchemeLayoutPCbg[]   = "$BG";
static const char SchemeLayoutPCbr[]   = "$BG";

static const char SchemeLayoutVVfg[]   = "$t4";
static const char SchemeLayoutVVbg[]   = "$BG";
static const char SchemeLayoutVVbr[]   = "$BG";

static const char SchemeLayoutOPfg[]   = "$t1";
static const char SchemeLayoutOPbg[]   = "$BG";
static const char SchemeLayoutOPbr[]   = "$BG";

static const char SchemeMenufg[]       = "$MENU_FG";
static const char SchemeMenubg[]       = "$BG";
static const char SchemeMenubr[]       = "$BG";
EOF

    ok "Theme written to $file"

    # save wallpaper alongside the theme so it can be restored when activated
    local wp_dir="$HOME/.config/ohmychadwm/wallpapers"
    mkdir -p "$wp_dir"
    local wp_ext="${WALLPAPER##*.}"
    local wp_dest="$wp_dir/${THEME_NAME}.${wp_ext}"
    if [[ "$WALLPAPER" != "$wp_dest" ]]; then
        cp -f "$WALLPAPER" "$wp_dest"
    fi
    ok "Wallpaper saved to $wp_dest"
}

# ── update config.def.h ───────────────────────────────────────────────────────
update_config() {
    local active_line="#include \"themes/${THEME_NAME}.h\""
    local section="// custom themes"

    # deactivate all active theme includes
    sed -i 's|^#include "themes/\(.*\)\.h"|//&|' "$CONFIG"

    # ensure custom themes section exists
    if ! grep -q "$section" "$CONFIG"; then
        sed -i "/^\/\* fallback layout settings/i $section\n" "$CONFIG"
    fi

    # add or uncomment this theme's include line, then activate it
    if ! grep -q "themes/${THEME_NAME}.h" "$CONFIG"; then
        sed -i "/^\/\/ custom themes/a $active_line" "$CONFIG"
    else
        sed -i "s|^//\(#include \"themes/${THEME_NAME}.h\"\)|\1|" "$CONFIG"
    fi

    ok "config.def.h updated — theme activated"

    # Sync SchemeMenufg → rofi menu accent color
    local rasi="$HOME/.config/ohmychadwm/menu/ohmychadwm-menu.rasi"
    local theme_file="$THEMES_DIR/$THEME_NAME.h"
    if [[ -f "$rasi" && -f "$theme_file" ]]; then
        local color
        color=$(grep -oP 'SchemeMenufg\[\]\s*=\s*"\K[^"]+' "$theme_file" | head -1)
        if [[ -n "$color" ]]; then
            # ensure color is visible on the rasi dark background (#101010, lum≈16)
            local rasi_bg_lum=16
            local clum; clum=$(luminance "$color")
            while (( clum - rasi_bg_lum < 80 )); do
                color=$(lighten "$color" 10)
                clum=$(luminance "$color")
                [[ "$color" == "#ffffff" ]] && break
            done
            local safe_color="${color//&/\\&}"
            sed -i "s|ac:.*\/\* selected item text.*|ac:     ${safe_color};   /* selected item text   (synced from SchemeMenufg)  */|" "$rasi"
            ok "Menu accent color synced to SchemeMenufg: $color"
        fi
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    # dependency checks
    local missing=0
    if ! command -v magick &>/dev/null; then
        err "ImageMagick not found — install it first: sudo pacman -S imagemagick"
        missing=1
    fi
    if ! command -v fzf &>/dev/null; then
        err "fzf not found — install it first: sudo pacman -S fzf"
        missing=1
    fi
    if [[ $missing -eq 1 ]]; then exit 1; fi

    header "Detecting wallpaper..."
    WALLPAPER=$(detect_wallpaper)
    ok "Wallpaper: $WALLPAPER"

    header "Extracting colors..."
    mapfile -t COLORS < <(extract_colors "$WALLPAPER" 12)

    if [[ ${#COLORS[@]} -lt 4 ]]; then
        err "Could not extract enough colors from the wallpaper (got ${#COLORS[@]})."
        exit 1
    fi

    mapfile -t SORTED < <(sort_by_luminance "${COLORS[@]}")
    build_palette "${SORTED[@]}"

    show_palette_preview
    ask "Continue with these colors? [y=keep / a=adapt / n=cancel]:"
    read -rp "> " ans
    case "$ans" in
        [Nn]) echo "Aborted."; exit 0 ;;
        [Aa]) tweak_palette ;;
    esac

    ask_questions

    # ── font availability check ───────────────────────────────────────────────
    if [[ -z "$(fc-list ":family=${THEME_FONT}" 2>/dev/null)" ]]; then
        echo -e "${R}✘ Font not installed: $THEME_FONT${NC}" >&2
        echo -e "${Y}  The theme will be written but the bar will fall back to a system font.${NC}"
        ask "Install '$THEME_FONT' first for correct rendering. Continue? [Y/n]:"
        read -rp "> " ans
        if [[ "$ans" =~ ^[Nn]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    else
        ok "Font found: $THEME_FONT"
    fi

    write_theme
    update_config

    if [[ "${FONT_CHADWM_ONLY:-1}" -eq 0 ]]; then
        apply_font_globally
    fi

    show_palette_preview

    # ── fix wallpaper ─────────────────────────────────────────────────────────
    ask "Fix this wallpaper to the theme? [Y/n]:"
    read -rp "> " fix_wp
    if [[ ! "$fix_wp" =~ ^[Nn]$ ]]; then
        local ext="${WALLPAPER##*.}"
        local wp_dest="$WALLPAPERS_DIR/${THEME_NAME}.${ext}"
        if [[ "$WALLPAPER" != "$wp_dest" ]]; then
            cp "$WALLPAPER" "$wp_dest"
            ok "Wallpaper saved to $(basename "$wp_dest")"
        fi
        if feh --bg-fill "$wp_dest" 2>/dev/null; then
            ok "Wallpaper set with feh"
        else
            err "feh could not set wallpaper — set manually: $wp_dest"
        fi
    fi

    echo
    header "Done!"
    echo -e "  Theme file : ${W}$THEMES_DIR/$THEME_NAME.h${NC}"
    echo -e "  config     : ${W}$CONFIG${NC}"
    echo
    ask "Run ./rebuild.sh now? [Y/n]:"
    read -rp "> " do_rebuild
    if [[ ! "$do_rebuild" =~ ^[Nn]$ ]]; then
        cd "$HOME/.config/ohmychadwm/chadwm" && ./rebuild.sh
    else
        echo -e "  Rebuild manually: ${W}cd ~/.config/ohmychadwm/chadwm && ./rebuild.sh${NC}"
    fi
}

main "$@"
