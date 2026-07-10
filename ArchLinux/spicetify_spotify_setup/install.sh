#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -eo pipefail

# ANSI color codes for rich user feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}=== Spicetify & Spotify Automated Setup & Patching ===${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo

# 1. Prevent running as root directly
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Please do not run this script as root/sudo directly.${NC}"
    echo -e "AUR helpers (like paru/yay) cannot be run as root. The script will request sudo when required."
    exit 1
fi

# 2. Detect AUR helper
AUR_HELPER=""
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
else
    echo -e "${RED}Error: Neither 'paru' nor 'yay' AUR helpers were found. Please install one of them first.${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Detected AUR helper:${NC} $AUR_HELPER"

# 3. Detect Askpass or Sudo prompt helper
# Check if running in a graphical session and setup askpass if possible
SUDO_CMD="sudo"
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    if [ -f "/usr/lib/ssh/x11-ssh-askpass" ]; then
        export SUDO_ASKPASS="/usr/lib/ssh/x11-ssh-askpass"
        SUDO_CMD="sudo -A"
        echo -e "${GREEN}[✓] Setup graphical sudo prompt using x11-ssh-askpass${NC}"
    fi
fi

# Request sudo credentials cache upfront
echo -e "${YELLOW}Requesting sudo authorization for system operations...${NC}"
$SUDO_CMD true

# 4. Install Spotify AUR package
if pacman -Q spotify &> /dev/null; then
    echo -e "${GREEN}[✓] Spotify is already installed.${NC}"
else
    echo -e "${YELLOW}Installing Spotify from AUR...${NC}"
    $AUR_HELPER -S --noconfirm spotify
fi

# 5. Install Spicetify-cli
if pacman -Q spicetify-cli &> /dev/null; then
    echo -e "${GREEN}[✓] Spicetify-cli is already installed.${NC}"
else
    echo -e "${YELLOW}Installing Spicetify-cli from AUR...${NC}"
    $AUR_HELPER -S --noconfirm spicetify-cli
fi

# 6. Configure Pacman IgnorePkg to prevent automatic updates breaking the patch
add_to_ignorepkg() {
    local config="/etc/pacman.conf"
    if pacman-conf IgnorePkg | grep -qw "spotify"; then
        echo -e "${GREEN}[✓] Spotify is already in pacman's IgnorePkg list.${NC}"
    else
        echo -e "${YELLOW}Adding Spotify to IgnorePkg in /etc/pacman.conf...${NC}"
        # If IgnorePkg is completely commented out
        if grep -q "^#IgnorePkg" "$config"; then
            $SUDO_CMD sed -i 's/^#IgnorePkg\s*=.*/IgnorePkg = spotify/' "$config"
        # If IgnorePkg is already active but doesn't have spotify
        elif grep -q "^IgnorePkg\s*=" "$config"; then
            $SUDO_CMD sed -i 's/^IgnorePkg\s*=\s*/IgnorePkg = spotify /' "$config"
        # If the option doesn't exist at all, append it under [options]
        else
            $SUDO_CMD sed -i '/^\[options\]/a IgnorePkg = spotify' "$config"
        fi
        echo -e "${GREEN}[✓] Successfully updated /etc/pacman.conf.${NC}"
    fi
}
add_to_ignorepkg

# 7. Grant folder permissions on Spotify
echo -e "${YELLOW}Granting write permissions to Spotify installation folders for Spicetify...${NC}"
$SUDO_CMD chmod a+wr /opt/spotify
$SUDO_CMD chmod a+wr /opt/spotify/Apps -R
echo -e "${GREEN}[✓] Folder permissions granted.${NC}"

# 8. Initialize Spicetify config if it doesn't exist
SPICETIFY_CONFIG_DIR="$HOME/.config/spicetify"
SPICETIFY_CONFIG_FILE="$SPICETIFY_CONFIG_DIR/config-xpui.ini"

if [ ! -f "$SPICETIFY_CONFIG_FILE" ]; then
    echo -e "${YELLOW}Initializing Spicetify config...${NC}"
    spicetify bootstrap || true
fi

# 9. Configure paths and options in Spicetify config-xpui.ini
echo -e "${YELLOW}Configuring Spicetify path to /opt/spotify...${NC}"
spicetify config spotify_path "/opt/spotify"

# Set Wayland launch flags so Spicetify launches Spotify correctly
echo -e "${YELLOW}Configuring Spicetify launch flags for Wayland compatibility...${NC}"
spicetify config spotify_launch_flags "--enable-features=UseOzonePlatform|--ozone-platform=wayland|--enable-features=WaylandWindowDecorations"

# Set correct prefs path if needed
PREFS_PATH="$HOME/.config/spotify/prefs"
if [ -f "$PREFS_PATH" ]; then
    spicetify config prefs_path "$PREFS_PATH"
fi

# 10. Install and configure Adblockify extension
EXTENSIONS_DIR="$SPICETIFY_CONFIG_DIR/Extensions"
mkdir -p "$EXTENSIONS_DIR"

echo -e "${YELLOW}Downloading/updating Adblockify extension (adblock.js)...${NC}"
curl -sS -L -o "$EXTENSIONS_DIR/adblock.js" https://raw.githubusercontent.com/rxri/spicetify-extensions/main/adblock/adblock.js
echo -e "${GREEN}[✓] Adblockify downloaded successfully.${NC}"

# Enable extension in Spicetify
spicetify config extensions adblock.js

# 11. Fix Spotify blurriness on Wayland (HiDPI scaling)
echo -e "${YELLOW}Configuring Spotify launch flags to fix blurriness on Wayland...${NC}"

# Write flags to ~/.config/spotify-flags.conf (used by /usr/bin/spotify wrapper)
SPOTIFY_FLAGS_FILE="$HOME/.config/spotify-flags.conf"
mkdir -p "$HOME/.config"
cat <<EOF > "$SPOTIFY_FLAGS_FILE"
--enable-features=UseOzonePlatform
--ozone-platform=wayland
--enable-features=WaylandWindowDecorations
EOF
echo -e "${GREEN}[✓] Spotify user flags configured at $SPOTIFY_FLAGS_FILE.${NC}"

# Clean up any local spotify.desktop to avoid redundant files overriding system configuration
LOCAL_DESKTOP_FILE="$HOME/.local/share/applications/spotify.desktop"
if [ -f "$LOCAL_DESKTOP_FILE" ]; then
    rm "$LOCAL_DESKTOP_FILE"
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$HOME/.local/share/applications"
    fi
    echo -e "${GREEN}[✓] Cleaned up legacy local desktop file override.${NC}"
fi

# 12. Apply Spicetify Patch
# Kill any running Spotify instance to make sure files aren't locked and modifications apply immediately
if pgrep -i "spotify" > /dev/null; then
    echo -e "${YELLOW}Closing running Spotify instance(s) to apply the patch...${NC}"
    pkill -i "spotify" || true
    sleep 1
fi

echo -e "${YELLOW}Applying Spicetify customizations (this may take a few seconds)...${NC}"
if spicetify restore backup apply; then
    echo -e "${GREEN}=== Setup Completed Successfully! ===${NC}"
    echo -e "Spotify is now patched with Adblockify and configured for Wayland display compatibility."
    echo -e "Updates have been pinned in pacman to keep the patch stable."
else
    # Fallback to standard apply if backup setup encountered issues
    echo -e "${YELLOW}Standard backup failed, attempting direct apply...${NC}"
    if spicetify apply; then
        echo -e "${GREEN}=== Setup Completed Successfully! ===${NC}"
    else
        echo -e "${RED}Error: Failed to apply Spicetify modifications.${NC}"
        exit 1
    fi
fi

# 13. Relaunch Spotify to apply Wayland display fixes (avoiding the blurry auto-launch)
if pgrep -i "spotify" > /dev/null; then
    echo -e "${YELLOW}Restarting Spotify to apply display fixes...${NC}"
    pkill -i "spotify" || true
    sleep 1.5
fi
# Launch Spotify in the background and disown it
spotify >/dev/null 2>&1 & disown
echo -e "${GREEN}[✓] Spotify restarted successfully (non-blurry).${NC}"

