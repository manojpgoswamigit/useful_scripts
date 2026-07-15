#!/usr/bin/env bash

# ==============================================================================
# Haruna HDR Setup Script for Nvidia + KDE Plasma 6 (Wayland) on Arch Linux
# ==============================================================================

set -euo pipefail

# Text formatting colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;m' # No Color

# Default options
AUTO_CONFIRM=false
SKIP_PKG_INSTALL=false

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes          Auto-confirm prompts (non-interactive mode)"
    echo "  -s, --skip-pkg     Skip installing Vulkan HDR layer package"
    echo "  -h, --help         Show this help message"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -s|--skip-pkg)
            SKIP_PKG_INSTALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  Arch Linux Haruna HDR Setup (Nvidia + KDE Wayland)${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Check if user is running Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Error: This script is designed specifically for Arch Linux.${NC}"
    exit 1
fi

# 2. Warning check for Wayland Session
if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
    echo -e "${YELLOW}[!] Warning: You are not currently in a Wayland session (current: ${XDG_SESSION_TYPE:-unknown}).${NC}"
    echo -e "${YELLOW}    HDR playback on Linux requires a Wayland session (e.g., KDE Plasma 6 Wayland).${NC}"
    echo -e "${YELLOW}    Please make sure to log into a Wayland session before testing HDR.${NC}"
    echo
fi

# 3. Check if Haruna is installed
if ! command -v haruna &> /dev/null; then
    echo -e "${YELLOW}[!] Haruna is not currently installed.${NC}"
    if [ "$AUTO_CONFIRM" = true ]; then
        echo -e "${BLUE}Auto-confirm enabled. Installing Haruna...${NC}"
        sudo pacman -S --needed --noconfirm haruna || {
            echo -e "${RED}Failed to install Haruna automatically. Please install it manually: sudo pacman -S haruna${NC}"
        }
    elif [ -t 0 ]; then
        read -p "Would you like to install Haruna? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo pacman -S --needed haruna
        else
            echo -e "${YELLOW}Proceeding without installing Haruna. Note that the launcher will not work until Haruna is installed.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] Non-interactive mode: Skipping Haruna installation.${NC}"
        echo -e "${YELLOW}    Please install Haruna manually using: sudo pacman -S haruna${NC}"
    fi
else
    echo -e "${GREEN}[✔] Haruna is installed.${NC}"
fi

# 4. Check for AUR Helper
AUR_HELPER=""
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
fi

# 5. Check/Install Vulkan HDR WSI Layer
if pacman -Qi vk-hdr-layer-kwin6-git &> /dev/null || pacman -Qi vk-hdr-layer-kwin6 &> /dev/null; then
    echo -e "${GREEN}[✔] Vulkan HDR WSI Layer is already installed.${NC}"
elif [ "$SKIP_PKG_INSTALL" = true ]; then
    echo -e "${YELLOW}[-] Skipping Vulkan HDR layer package installation as requested.${NC}"
else
    echo -e "${YELLOW}[!] Vulkan HDR WSI Layer is missing.${NC}"
    if [ -t 0 ] && [ "$AUTO_CONFIRM" = false ]; then
        if [ -n "$AUR_HELPER" ]; then
            echo -e "${BLUE}Installing vk-hdr-layer-kwin6-git via $AUR_HELPER...${NC}"
            if ! $AUR_HELPER -S --needed vk-hdr-layer-kwin6-git; then
                echo -e "${YELLOW}[!] Automatic installation failed (possibly due to sudo password prompt).${NC}"
                echo -e "${YELLOW}    Please install it manually later: $AUR_HELPER -S vk-hdr-layer-kwin6-git${NC}"
            fi
        else
            echo -e "${RED}Error: No AUR helper (yay/paru) detected. Please install 'vk-hdr-layer-kwin6-git' manually from the AUR.${NC}"
        fi
    else
        # Running non-interactively or with --yes, but sudo/yay needs tty password input
        echo -e "${YELLOW}[!] Non-interactive mode or --yes flag: Skipping automatic package build.${NC}"
        echo -e "${YELLOW}    Please install the Vulkan HDR WSI layer manually using:${NC}"
        if [ -n "$AUR_HELPER" ]; then
            echo -e "${GREEN}    $AUR_HELPER -S vk-hdr-layer-kwin6-git${NC}"
        else
            echo -e "${GREEN}    (AUR helper) -S vk-hdr-layer-kwin6-git${NC}"
        fi
        echo
    fi
fi

# 6. Create the Desktop Entry
LAUNCHER_DIR="$HOME/.local/share/applications"
LAUNCHER_PATH="$LAUNCHER_DIR/haruna-hdr.desktop"

echo -e "${BLUE}Creating HDR launcher at: $LAUNCHER_PATH...${NC}"
mkdir -p "$LAUNCHER_DIR"

cat << 'EOF' > "$LAUNCHER_PATH"
[Desktop Entry]
Name=Haruna Media Player (HDR)
GenericName=Media Player
Comment=Play audio and video files with Vulkan HDR support enabled
Exec=env ENABLE_HDR_WSI=1 haruna %U
Icon=org.kde.haruna
Type=Application
Categories=Qt;KDE;AudioVideo;Player;Video;
MimeType=application/mxf;application/ogg;application/sdp;application/smil;application/streamingmedia;application/ttml+xml;application/vnd.apple.mpegurl;application/vnd.ms-asf;application/vnd.ms-wpl;application/vnd.rn-realmedia;application/vnd.rn-realmedia-vbr;application/x-cue;application/x-extension-m4a;application/x-extension-mp4;application/x-matroska;application/x-mpegurl;application/x-ogm;application/x-ogm-audio;application/x-ogm-video;application/x-shorten;application/x-smil;application/x-streamingmedia;audio/3gpp;audio/3gpp2;audio/aac;audio/ac3;audio/amr;audio/amr-wb;audio/ape;audio/basic;audio/dv;audio/eac3;audio/flac;audio/m4a;audio/midi;audio/mp2;audio/mp3;audio/mp4;audio/mpeg;audio/mpeg3;audio/mpegurl;audio/mpg;audio/musepack;audio/ogg;audio/opus;audio/rn-realaudio;audio/scpls;audio/siren;audio/speex;audio/vnd.dts;audio/vnd.dts.hd;audio/vnd.rn-realaudio;audio/wav;audio/webm;audio/x-aac;audio/x-adpcm;audio/x-ape;audio/x-basic;audio/x-caf;audio/x-flac;audio/x-gsm;audio/x-it;audio/x-iwde;audio/x-m4a;audio/x-matroska;audio/x-mod;audio/x-mp3;audio/x-mpeg;audio/x-mpegurl;audio/x-mpg;audio/x-ms-asf;audio/x-ms-asx;audio/x-ms-wax;audio/x-ms-wma;audio/x-musepack;audio/x-opus;audio/x-pn-realaudio;audio/x-pn-realaudio-plugin;audio/x-real-audio;audio/x-realaudio;audio/x-s3m;audio/x-scpls;audio/x-shorten;audio/x-speex;audio/x-tta;audio/x-wav;audio/x-wavpack;audio/x-webm;audio/x-xm;image/vnd.rn-realflash;video/3gpp;video/3gpp2;video/dv;video/divx;video/fli;video/flv;video/mp2t;video/mp4;video/mp4v-es;video/mpeg;video/mpeg-system;video/msvideo;video/ogg;video/quicktime;video/vnd.divx;video/vnd.mpegurl;video/vnd.rn-realvideo;video/webm;video/x-anim;video/x-avi;video/x-chachacha;video/x-dans1;video/x-dirac;video/x-flic;video/x-flv;video/x-m4v;video/x-matroska;video/x-matroska-3d;video/x-mpeg;video/x-mpeg-system;video/x-mpeg2;video/x-ms-asf;video/x-ms-asf-plugin;video/x-ms-wm;video/x-ms-wmv;video/x-ms-wmx;video/x-ms-wvx;video/x-msvideo;video/x-nsv;video/x-ogm+ogg;video/x-theora;video/x-theora+ogg;video/x-totem;video/x-webm;
Terminal=false
StartupNotify=true
Actions=new-window;
EOF

chmod +x "$LAUNCHER_PATH"

echo -e "${GREEN}[✔] HDR Setup Completed successfully!${NC}"
echo -e "${GREEN}[✔] You can now launch 'Haruna Media Player (HDR)' from your application menu.${NC}"
echo -e "${YELLOW}Note: Make sure HDR is enabled in your KDE display settings before playing files.${NC}"
