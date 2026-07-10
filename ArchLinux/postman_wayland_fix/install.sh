#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# ANSI color codes for rich user feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}===         Postman Wayland Blurry Text Fix Installation            ===${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo

# 1. Prevent running as root directly
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Please do not run this script as root/sudo directly.${NC}"
    echo -e "This script configures user-level settings and launchers. Run it as your regular user."
    exit 1
fi

# 2. Detect Session Type (X11 or Wayland)
echo -e "${CYAN}[1/4] Detecting Display Session...${NC}"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
echo -e "${GREEN}[✓] Session Type:${NC} $SESSION_TYPE"

if [ "$SESSION_TYPE" != "wayland" ]; then
    echo -e "${YELLOW}[!] Warning: You are not currently in a Wayland session.${NC}"
    echo -e "    This fix is designed to resolve blurry rendering under Wayland."
    echo -e "    The configuration will still be applied, and it will take effect"
    echo -e "    the next time you log into a Wayland session."
fi

# Create target applications directory if it doesn't exist
TARGET_APP_DIR="$HOME/.local/share/applications"
mkdir -p "$TARGET_APP_DIR"

# 3. Configure Native (AUR/Pacman) Postman
echo -e "\n${CYAN}[2/4] Checking Native (AUR/Pacman) Postman...${NC}"
NATIVE_DESKTOP_SRC="/usr/share/applications/postman.desktop"
NATIVE_DESKTOP_DST="$TARGET_APP_DIR/postman.desktop"

if [ -f "$NATIVE_DESKTOP_SRC" ]; then
    echo -e "${GREEN}[✓] Found native Postman desktop launcher at:${NC} $NATIVE_DESKTOP_SRC"
    
    # Check if we have already configured it
    if [ -f "$NATIVE_DESKTOP_DST" ] && grep -q "UseOzonePlatform" "$NATIVE_DESKTOP_DST"; then
        echo -e "${GREEN}[✓] Native Postman is already configured for Wayland at:${NC} $NATIVE_DESKTOP_DST"
    else
        # Backup existing user launcher if it exists
        if [ -f "$NATIVE_DESKTOP_DST" ]; then
            echo -e "${YELLOW}Saving backup of existing launcher...${NC}"
            cp "$NATIVE_DESKTOP_DST" "${NATIVE_DESKTOP_DST}.bak"
        fi
        
        echo -e "${YELLOW}Creating native launcher override with Wayland flags...${NC}"
        # Match Exec=binary and insert the flags right after it
        sed -E 's|^(Exec=[^ ]+)(.*)|\1 --enable-features=UseOzonePlatform --ozone-platform=wayland\2|' "$NATIVE_DESKTOP_SRC" > "$NATIVE_DESKTOP_DST"
        chmod +x "$NATIVE_DESKTOP_DST"
        echo -e "${GREEN}[✓] Created: ${NC} $NATIVE_DESKTOP_DST"
    fi
else
    echo -e "${YELLOW}[!] Native Postman desktop launcher not found. Skipping native setup.${NC}"
fi

# 4. Configure Flatpak Postman
echo -e "\n${CYAN}[3/4] Checking Flatpak Postman...${NC}"
FLATPAK_APP_ID="com.getpostman.Postman"
FLATPAK_DESKTOP_NAME="${FLATPAK_APP_ID}.desktop"
FLATPAK_DESKTOP_DST="$TARGET_APP_DIR/$FLATPAK_DESKTOP_NAME"

# Potential source paths for flatpak desktop entry
FLATPAK_SRC_SYSTEM="/var/lib/flatpak/exports/share/applications/$FLATPAK_DESKTOP_NAME"
FLATPAK_SRC_USER="$HOME/.local/share/flatpak/exports/share/applications/$FLATPAK_DESKTOP_NAME"
FLATPAK_DESKTOP_SRC=""

if [ -f "$FLATPAK_SRC_USER" ]; then
    FLATPAK_DESKTOP_SRC="$FLATPAK_SRC_USER"
elif [ -f "$FLATPAK_SRC_SYSTEM" ]; then
    FLATPAK_DESKTOP_SRC="$FLATPAK_SRC_SYSTEM"
fi

if [ -n "$FLATPAK_DESKTOP_SRC" ]; then
    echo -e "${GREEN}[✓] Found Flatpak Postman desktop launcher at:${NC} $FLATPAK_DESKTOP_SRC"
    
    # Check if we have already configured it
    if [ -f "$FLATPAK_DESKTOP_DST" ] && grep -q "UseOzonePlatform" "$FLATPAK_DESKTOP_DST"; then
        echo -e "${GREEN}[✓] Flatpak Postman is already configured for Wayland at:${NC} $FLATPAK_DESKTOP_DST"
    else
        # Backup existing user launcher if it exists
        if [ -f "$FLATPAK_DESKTOP_DST" ]; then
            echo -e "${YELLOW}Saving backup of existing launcher...${NC}"
            cp "$FLATPAK_DESKTOP_DST" "${FLATPAK_DESKTOP_DST}.bak"
        fi
        
        echo -e "${YELLOW}Creating Flatpak launcher override with Wayland flags...${NC}"
        # For flatpak, we replace 'com.getpostman.Postman' in Exec with 'com.getpostman.Postman --enable-features=UseOzonePlatform --ozone-platform=wayland'
        sed "s|$FLATPAK_APP_ID|$FLATPAK_APP_ID --enable-features=UseOzonePlatform --ozone-platform=wayland|g" "$FLATPAK_DESKTOP_SRC" > "$FLATPAK_DESKTOP_DST"
        chmod +x "$FLATPAK_DESKTOP_DST"
        echo -e "${GREEN}[✓] Created: ${NC} $FLATPAK_DESKTOP_DST"
    fi
    
    # Apply flatpak environment variable override as well
    if command -v flatpak &>/dev/null; then
        echo -e "${YELLOW}Setting flatpak environment variable overrides...${NC}"
        # We set both variables to support older and newer Electron versions in the flatpak
        flatpak override --user --env=ELECTRON_OZONE_PLATFORM_HINT=auto "$FLATPAK_APP_ID"
        flatpak override --user --socket=wayland "$FLATPAK_APP_ID"
        echo -e "${GREEN}[✓] Environment overrides applied via flatpak override command.${NC}"
    fi
else
    echo -e "${YELLOW}[!] Flatpak Postman desktop launcher not found. Skipping Flatpak setup.${NC}"
fi

# 5. Finalizing
echo -e "\n${CYAN}[4/4] Finalizing Setup...${NC}"
echo -e "Refreshing desktop database..."
update-desktop-database "$TARGET_APP_DIR" &>/dev/null || true
echo -e "${GREEN}[✓] Done!${NC}"

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${GREEN}🎉 Setup Complete! Please follow these steps to verify:${NC}"
echo -e "1. Close any running Postman instances."
echo -e "2. Launch Postman from your Application Menu / KRunner."
echo -e "3. To verify if it runs under native Wayland, run this in a terminal:"
echo -e "   ${CYAN}xlsclients${NC}"
echo -e "   If Postman is running natively on Wayland, it should ${YELLOW}NOT${NC} appear in the list."
echo -e "${BLUE}======================================================================${NC}"
