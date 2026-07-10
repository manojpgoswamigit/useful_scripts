#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# ANSI color codes for rich user feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}===    NVIDIA Hardware Video Acceleration Setup for Chromium/Brave  ===${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo

# 1. Prevent running as root directly
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Please do not run this script as root/sudo directly.${NC}"
    echo -e "This script configures user-level settings and flags. Run it as your regular user."
    exit 1
fi

# 2. Check for NVIDIA hardware
echo -e "${CYAN}[1/6] Scanning GPU Hardware...${NC}"
LSPCI_OUT=$(lspci 2>/dev/null || true)

if [ -z "$LSPCI_OUT" ]; then
    echo -e "${YELLOW}[!] Warning: lspci returned no output or is unavailable.${NC}"
    if ! command -v nvidia-smi &>/dev/null; then
        echo -e "${RED}Error: Could not detect any GPU. lspci is empty and nvidia-smi is missing.${NC}"
        exit 1
    fi
    GPU_NAME="NVIDIA GPU (detected via nvidia-smi)"
else
    if ! echo "$LSPCI_OUT" | grep -qi "nvidia"; then
        echo -e "${RED}Error: No NVIDIA GPU detected on this system via lspci.${NC}"
        exit 1
    fi
    GPU_NAME=$(echo "$LSPCI_OUT" | grep -i "nvidia" | grep -E -i "vga|3d" | cut -d':' -f3- | sed 's/^[ \t]*//' || true)
    if [ -z "$GPU_NAME" ]; then
        GPU_NAME=$(echo "$LSPCI_OUT" | grep -i "nvidia" | head -n 1 | cut -d':' -f3- | sed 's/^[ \t]*//' || true)
    fi
    if [ -z "$GPU_NAME" ]; then
        GPU_NAME="NVIDIA GPU"
    fi
fi
echo -e "${GREEN}[✓] Detected GPU:${NC} $GPU_NAME"

if ! command -v nvidia-smi &>/dev/null; then
    echo -e "${RED}Error: nvidia-smi not found. Ensure NVIDIA proprietary drivers are installed.${NC}"
    exit 1
fi

DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
echo -e "${GREEN}[✓] NVIDIA Driver Version:${NC} $DRIVER_VER"

# 3. Detect Session Type (X11 or Wayland)
echo -e "\n${CYAN}[2/6] Detecting Display Session...${NC}"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
echo -e "${GREEN}[✓] Session Type:${NC} $SESSION_TYPE"

# 4. Detect AUR Helper and installed packages
echo -e "\n${CYAN}[3/6] Checking Driver Dependencies...${NC}"
AUR_HELPER=""
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
fi

# Check for translation driver
if pacman -Q libva-nvidia-driver &>/dev/null; then
    echo -e "${GREEN}[✓] libva-nvidia-driver is already installed.${NC}"
else
    echo -e "${YELLOW}[!] libva-nvidia-driver (VA-API translation layer for NVDEC) is missing.${NC}"
    if [ -n "$AUR_HELPER" ]; then
        read -r -p "Would you like to install it now via $AUR_HELPER? [Y/n] " yn
        case $yn in
            [Nn]*) 
                echo -e "${RED}Aborting. Setup cannot continue without libva-nvidia-driver.${NC}"
                exit 1
                ;;
            *)
                echo -e "${YELLOW}Installing libva-nvidia-driver...${NC}"
                $AUR_HELPER -S --noconfirm libva-nvidia-driver
                ;;
        esac
    else
        echo -e "${RED}Error: AUR helper (yay/paru) not found. Please install 'libva-nvidia-driver' manually first.${NC}"
        exit 1
    fi
fi

# Check for libva-utils (for vainfo)
if ! command -v vainfo &>/dev/null; then
    echo -e "${YELLOW}[!] libva-utils (vainfo) is not installed.${NC}"
    if [ -n "$AUR_HELPER" ]; then
        $AUR_HELPER -S --noconfirm libva-utils
    fi
fi

# 5. Configure User Environment Variables
echo -e "\n${CYAN}[4/6] Setting Up Environment Variables...${NC}"

# User systemd environment directory
SYSTEMD_ENV_DIR="$HOME/.config/environment.d"
SYSTEMD_ENV_FILE="$SYSTEMD_ENV_DIR/nvidia-vaapi.conf"

mkdir -p "$SYSTEMD_ENV_DIR"
cat <<EOF > "$SYSTEMD_ENV_FILE"
LIBVA_DRIVER_NAME=nvidia
NVD_BACKEND=direct
EOF
echo -e "${GREEN}[✓] Created systemd-user configuration at:${NC} $SYSTEMD_ENV_FILE"

# Shell configuration exports
export_to_shell_config() {
    local shell_rc="$1"
    if [ -f "$shell_rc" ]; then
        if grep -q "LIBVA_DRIVER_NAME=nvidia" "$shell_rc"; then
            echo -e "${GREEN}[✓] Environment variables already exported in:${NC} $(basename "$shell_rc")"
        else
            echo -e "${YELLOW}Appending exports to:${NC} $(basename "$shell_rc")"
            cat <<EOF >> "$shell_rc"

# NVIDIA VA-API hardware video acceleration variables
export LIBVA_DRIVER_NAME=nvidia
export NVD_BACKEND=direct
EOF
            echo -e "${GREEN}[✓] Successfully updated:${NC} $(basename "$shell_rc")"
        fi
    fi
}

export_to_shell_config "$HOME/.zshrc"
export_to_shell_config "$HOME/.bashrc"

# 6. Detect Browsers & Configure Flags
echo -e "\n${CYAN}[5/6] Scanning and Configuring Browsers...${NC}"

declare -A BROWSERS=(
    ["brave-origin-flags.conf"]="brave-origin"
    ["brave-flags.conf"]="brave"
    ["chromium-flags.conf"]="chromium"
    ["chrome-flags.conf"]="google-chrome"
)

CONFIGURED_ANY=false

# The direct, optimal acceleration flags
ACCEL_FLAGS=$(cat <<'EOF'
--ozone-platform-hint=auto
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--enable-features=VaapiVideoDecoder,VaapiOnNvidiaGPUs,WaylandFractionalScaleV1
--disable-features=UseChromeOSDirectVideoDecoder
EOF
)

for config_file in "${!BROWSERS[@]}"; do
    binary_name="${BROWSERS[$config_file]}"
    if command -v "$binary_name" &>/dev/null; then
        echo -e "${GREEN}[✓] Found installed browser:${NC} $binary_name"
        target_path="$HOME/.config/$config_file"
        
        # Check if the file already exists and matches
        if [ -f "$target_path" ] && grep -q "VaapiOnNvidiaGPUs" "$target_path"; then
            echo -e "${GREEN}[✓] Browser flags already configured at:${NC} $target_path"
        else
            echo -e "${YELLOW}Writing launch flags configuration to:${NC} $target_path"
            echo "$ACCEL_FLAGS" > "$target_path"
            echo -e "${GREEN}[✓] Flags written successfully!${NC}"
        fi
        CONFIGURED_ANY=true
    fi
done

if [ "$CONFIGURED_ANY" = false ]; then
    echo -e "${YELLOW}[!] No supported Chromium-based browsers detected.${NC}"
    echo -e "Creating a default 'brave-flags.conf' and 'chromium-flags.conf' in case you install them later..."
    echo "$ACCEL_FLAGS" > "$HOME/.config/brave-flags.conf"
    echo "$ACCEL_FLAGS" > "$HOME/.config/chromium-flags.conf"
fi

# 7. Verification Steps
echo -e "\n${CYAN}[6/6] Finalizing Setup...${NC}"
echo -e "${PURPLE}┌────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${PURPLE}│${GREEN}            🎉 SUCCESS: Configuration applied successfully!         ${PURPLE}│${NC}"
echo -e "${PURPLE}└────────────────────────────────────────────────────────────────────┘${NC}"

echo -e "\n${YELLOW}🔔 IMPORTANT ACTION REQUIRED:${NC}"
echo -e "  ${CYAN}✦${NC} For GUI application launchers to pick up variables:"
echo -e "    Log out of your desktop session and log back in (or restart your PC)."
echo -e "  ${CYAN}✦${NC} To test immediately:"
echo -e "    Launch your browser from a newly opened terminal window."

echo -e "\n${CYAN}🔍 HOW TO VERIFY HARDWARE ACCELERATION:${NC}"
echo -e "  1. Open a terminal and run: ${GREEN}nvtop${NC} (or: ${GREEN}watch -n 1 nvidia-smi${NC})"
echo -e "  2. Launch your browser (e.g. run: ${GREEN}brave-origin${NC} or use your desktop launcher)"
echo -e "  3. Play a high-resolution video (e.g., 4K on YouTube)"
echo -e "  4. Look at ${GREEN}nvtop${NC}:"
echo -e "     - Check the ${GREEN}DEC (Decoder)${NC} column. It should show active load (15% - 45%)."
echo -e "     - If it remains at 0%, the GPU is NOT decoding (software fallback)."

echo -e "\n${PURPLE}💡 PRO-TIP FOR HIGH RESOLUTIONS (1440p / 4K):${NC}"
echo -e "  If you have an older NVIDIA GPU that lacks AV1 hardware decoding (GTX 10xx / RTX 20xx),"
echo -e "  YouTube's default AV1 stream will lag on your CPU."
echo -e "  Install the ${CYAN}Enhanced h264ify${NC} browser extension and toggle ${YELLOW}\"Block AV1\"${NC} to force"
echo -e "  YouTube to serve VP9/H.264 codecs, which your GPU accelerates flawlessly."
echo
