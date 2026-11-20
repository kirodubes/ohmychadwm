#!/usr/bin/env bash
# install-arch.sh
# Prepare a base Arch Linux system for ohmychadwm.

set -euo pipefail

ENABLE_MULTILIB=0
ENABLE_CHAOTIC=0
INSTALL_CHAOTIC_EXTRAS=0

usage() {
    cat <<'USAGE'
Usage: ./scripts/install-arch.sh [options]

Options:
  --enable-multilib        Enable [multilib] in /etc/pacman.conf
  --enable-chaotic-aur     Add chaotic-aur repository
  --chaotic-extras         Install extra optional packages (if available)
  -h, --help               Show this help

Examples:
  ./scripts/install-arch.sh
  ./scripts/install-arch.sh --enable-multilib
  ./scripts/install-arch.sh --enable-multilib --enable-chaotic-aur --chaotic-extras
USAGE
}

log() { printf '[install-arch] %s\n' "$*"; }
warn() { printf '[install-arch] WARNING: %s\n' "$*" >&2; }

for arg in "$@"; do
    case "$arg" in
        --enable-multilib) ENABLE_MULTILIB=1 ;;
        --enable-chaotic-aur) ENABLE_CHAOTIC=1 ;;
        --chaotic-extras) INSTALL_CHAOTIC_EXTRAS=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            warn "Unknown option: $arg"
            usage
            exit 1
            ;;
    esac
done

if ! command -v pacman >/dev/null 2>&1; then
    warn "pacman not found. This script is for Arch Linux only."
    exit 1
fi

if ! sudo -v; then
    warn "sudo authentication failed."
    exit 1
fi

enable_multilib() {
    if grep -Eq '^\[multilib\]' /etc/pacman.conf; then
        log "[multilib] is already enabled."
        return
    fi

    if grep -Eq '^#\[multilib\]' /etc/pacman.conf; then
        log "Enabling commented [multilib] section in /etc/pacman.conf"
        sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/s/^#//' /etc/pacman.conf
    else
        log "Adding [multilib] section to /etc/pacman.conf"
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
    fi
}

enable_chaotic_aur() {
    if grep -Eq '^\[chaotic-aur\]' /etc/pacman.conf; then
        log "[chaotic-aur] already exists in /etc/pacman.conf"
        return
    fi

    log "Adding chaotic-aur keyring and mirrorlist"
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/chaotic-keyring.pkg.tar.zst' \
        'https://geo-mirror.chaotic.cx/chaotic-aur/x86_64/chaotic-mirrorlist.pkg.tar.zst'

    log "Appending [chaotic-aur] to /etc/pacman.conf"
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
}

pkg_available() {
    local pkg="$1"
    pacman -Si "$pkg" >/dev/null 2>&1
}

install_if_available() {
    local group_name="$1"
    shift
    local -a requested=("$@")
    local -a available=()
    local -a missing=()

    for pkg in "${requested[@]}"; do
        if pkg_available "$pkg"; then
            available+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done

    if ((${#available[@]} > 0)); then
        log "Installing ${group_name}: ${available[*]}"
        sudo pacman -S --needed --noconfirm "${available[@]}"
    fi

    if ((${#missing[@]} > 0)); then
        warn "Not in enabled repos (${group_name}): ${missing[*]}"
    fi
}

if ((ENABLE_MULTILIB)); then
    enable_multilib
fi

if ((ENABLE_CHAOTIC)); then
    enable_chaotic_aur
fi

log "Refreshing package databases"
sudo pacman -Syyu --noconfirm

REQUIRED_PKGS=(
    base-devel
    libx11
    libxft
    libxinerama
    imlib2
    rofi
    feh
    sxhkd
    alacritty
    picom-git
    libnotify
    xclip
    maim
    slop
    fzf
    btop
    ncdu
    inxi
    lm_sensors
    xorg-xrandr
    xorg-xsetroot
    xorg-xset
    xorg-xprop
    fontconfig
    imagemagick
    bc
    ttf-jetbrains-mono-nerd
)

OPTIONAL_OFFICIAL_PKGS=(
    redshift
    xautolock
    numlockx
    flameshot-git
    networkmanager
    network-manager-applet
    xfce4-power-manager
    xfce4-clipman-plugin
    blueberry
    snixembed
    arandr
    xcolor
    xdotool
    simplescreenrecorder
    nomacs-git
    kitty
    signal-desktop
    polkit-gnome
)

CHAOTIC_OR_AUR_LIKE_PKGS=(
    fastcompmgr
    volctl
    pamac-aur
    yay
    brave-bin
    visual-studio-code-bin
    spotify
    wezterm
    ghostty
    insync
)

install_if_available "required" "${REQUIRED_PKGS[@]}"
install_if_available "optional-official" "${OPTIONAL_OFFICIAL_PKGS[@]}"

if ((INSTALL_CHAOTIC_EXTRAS)); then
    install_if_available "chaotic-or-aur-like" "${CHAOTIC_OR_AUR_LIKE_PKGS[@]}"
else
    log "Skipping chaotic/AUR-like extras. Use --chaotic-extras to include them."
fi

log "Done. Recommended next steps:"
log "1) Rebuild chadwm: cd ~/.config/ohmychadwm/chadwm && ./rebuild.sh"
log "2) Rebuild slstatus: cd ~/.config/ohmychadwm/slstatus && ./rebuild.sh"
log "3) Start session with your DM/startx using scripts/run.sh"
