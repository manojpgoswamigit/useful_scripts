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

# State tracking
REBOOT_REQUIRED=false


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

# Verify NVIDIA DRM Modesetting is enabled (critical for VA-API and HDR)
MODESET_ENABLED=false
if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
    MODESET_VAL=$(cat /sys/module/nvidia_drm/parameters/modeset)
    if [ "$MODESET_VAL" = "Y" ] || [ "$MODESET_VAL" = "1" ]; then
        MODESET_ENABLED=true
    fi
elif grep -qE "nvidia[-_]drm\.modeset=1" /proc/cmdline 2>/dev/null; then
    MODESET_ENABLED=true
elif ls /sys/class/drm/card*-DP-* &>/dev/null || ls /sys/class/drm/card*-HDMI-* &>/dev/null || ls /sys/class/drm/card*-eDP-* &>/dev/null; then
    # Connectors exist in sysfs, confirming that KMS modesetting is active
    MODESET_ENABLED=true
fi


if [ "$MODESET_ENABLED" = true ]; then
    echo -e "${GREEN}[✓] NVIDIA DRM Modesetting is enabled.${NC}"
else
    echo -e "${YELLOW}[!] WARNING: NVIDIA DRM Modesetting is NOT enabled.${NC}"
    echo -e "    VA-API hardware acceleration and HDR requires modesetting to be active."
    
    read -r -p "Would you like to automatically configure it now? [Y/n] " yn
    case $yn in
        [Nn]*)
            echo -e "${RED}Skipping modesetting configuration. Hardware acceleration will likely be disabled until rebooted with modeset enabled.${NC}"
            ;;
        *)
            echo -e "${YELLOW}Enabling NVIDIA DRM Modesetting...${NC}"
            
            # 1. Modprobe configuration
            MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
            sudo mkdir -p /etc/modprobe.d
            if [ -f "$MODPROBE_CONF" ] && grep -q "nvidia_drm" "$MODPROBE_CONF"; then
                sudo sed -i 's/options nvidia_drm.*/options nvidia_drm modeset=1/' "$MODPROBE_CONF"
            else
                echo "options nvidia_drm modeset=1" | sudo tee -a "$MODPROBE_CONF" >/dev/null
            fi
            echo -e "${GREEN}[✓] Added modeset option to: $MODPROBE_CONF${NC}"
            
            # 2. Initramfs Early Loading Configuration (mkinitcpio.conf)
            MKINITCPIO_CONF="/etc/mkinitcpio.conf"
            if [ -f "$MKINITCPIO_CONF" ]; then
                if grep -q "nvidia_drm" "$MKINITCPIO_CONF"; then
                    echo -e "${GREEN}[✓] NVIDIA modules already present in mkinitcpio.conf${NC}"
                else
                    echo -e "${YELLOW}Adding NVIDIA modules to early loading in mkinitcpio.conf...${NC}"
                    if grep -q "^MODULES=()" "$MKINITCPIO_CONF"; then
                        sudo sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINITCPIO_CONF"
                    else
                        sudo sed -i 's/^MODULES=(\([^)]*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINITCPIO_CONF"
                    fi
                    echo -e "${GREEN}[✓] Updated mkinitcpio.conf${NC}"
                fi
            fi
            
            # 3. Regenerate Initramfs
            if command -v limine-mkinitcpio &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with limine-mkinitcpio...${NC}"
                sudo limine-mkinitcpio
                echo -e "${GREEN}[✓] Initramfs regenerated successfully.${NC}"
            elif command -v mkinitcpio &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with mkinitcpio...${NC}"
                sudo mkinitcpio -P
                echo -e "${GREEN}[✓] Initramfs regenerated successfully.${NC}"
            elif command -v dracut &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with dracut...${NC}"
                sudo dracut-rebuild
                echo -e "${GREEN}[✓] Initramfs regenerated successfully.${NC}"
            else
                echo -e "${YELLOW}[!] Warning: No supported initramfs generator (limine-mkinitcpio, mkinitcpio, or dracut) found.${NC}"
                echo -e "    Please regenerate your initramfs manually to apply modifications."
            fi
            
            REBOOT_REQUIRED=true
            echo -e "${GREEN}[✓] NVIDIA DRM Modesetting configured!${NC}"
            ;;
    esac
fi

# 1.5. Configure NVIDIA PowerMizer performance settings to avoid stuttering under Wayland
echo -e "\n${CYAN}[1.5/6] Checking NVIDIA PowerMizer Settings...${NC}"
MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"

if [ -f "$MODPROBE_CONF" ] && grep -q "NVreg_RegistryDwords" "$MODPROBE_CONF" && grep -q "PowerMizerEnable=0x1" "$MODPROBE_CONF"; then
    echo -e "${GREEN}[✓] NVIDIA PowerMizer performance RegistryDwords already configured.${NC}"
else
    echo -e "${YELLOW}[!] Warning: NVIDIA PowerMizer RegistryDwords are not set or incomplete.${NC}"
    echo -e "    Without forcing maximum performance, the driver may stay in the lowest power"
    echo -e "    saving state (P8 / 315MHz) during video playback, bottlenecking memory and"
    echo -e "    PCIe bandwidth, which causes micro-stuttering."
    read -r -p "Would you like to configure NVIDIA PowerMizer for maximum performance? [Y/n] " pm_yn
    case $pm_yn in
        [Nn]*)
            echo -e "${YELLOW}Skipping PowerMizer override. Micro-stuttering may persist during video playback.${NC}"
            ;;
        *)
            echo -e "${YELLOW}Applying PowerMizer performance overrides...${NC}"
            sudo mkdir -p /etc/modprobe.d
            if [ -f "$MODPROBE_CONF" ] && grep -q "options nvidia " "$MODPROBE_CONF"; then
                if grep -q "NVreg_RegistryDwords" "$MODPROBE_CONF"; then
                    sudo sed -i 's/options nvidia .*NVreg_RegistryDwords=.*/options nvidia NVreg_EnableGpuFirmware=0 NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerDefaultAC=0x1"/' "$MODPROBE_CONF"
                else
                    sudo sed -i 's/options nvidia .*/& NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerDefaultAC=0x1"/' "$MODPROBE_CONF"
                fi
            else
                echo 'options nvidia NVreg_EnableGpuFirmware=0 NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerDefaultAC=0x1"' | sudo tee -a "$MODPROBE_CONF" >/dev/null
            fi
            echo -e "${GREEN}[✓] Overrides written to $MODPROBE_CONF.${NC}"
            
            if command -v limine-mkinitcpio &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with limine-mkinitcpio...${NC}"
                sudo limine-mkinitcpio
            elif command -v mkinitcpio &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with mkinitcpio...${NC}"
                sudo mkinitcpio -P
            elif command -v dracut &>/dev/null; then
                echo -e "${YELLOW}Regenerating initramfs with dracut...${NC}"
                sudo dracut-rebuild
            fi
            REBOOT_REQUIRED=true
            echo -e "${GREEN}[✓] Overrides applied. A system reboot is required to load the new settings.${NC}"
            ;;
    esac
fi


# Detect AV1 support (RTX 30xx/40xx/50xx and future GPUs)
HAS_AV1=false
if echo "$GPU_NAME" | grep -E -i "RTX (30|40|50|60|A[0-9]{3,4})" &>/dev/null || \
   echo "$GPU_NAME" | grep -E -i "GeForce RTX (30|40|50|60)" &>/dev/null || \
   { echo "$GPU_NAME" | grep -i "GTX" -v && echo "$GPU_NAME" | grep -E -i "(3080|3090|3070|3060|4090|4080|4070|4060)" &>/dev/null; }; then
    HAS_AV1=true
fi

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

# Function to check and install a package
install_package() {
    local pkg="$1"
    local desc="$2"
    if pacman -Q "$pkg" &>/dev/null; then
        echo -e "${GREEN}[✓] $pkg ($desc) is already installed.${NC}"
    else
        echo -e "${YELLOW}[!] $pkg ($desc) is missing.${NC}"
        read -r -p "Would you like to install it now? [Y/n] " yn
        case $yn in
            [Nn]*)
                echo -e "${RED}Aborting. Setup cannot continue without $pkg.${NC}"
                exit 1
                ;;
            *)
                echo -e "${YELLOW}Attempting to install $pkg via pacman...${NC}"
                if sudo pacman -S --noconfirm "$pkg"; then
                    echo -e "${GREEN}[✓] Successfully installed $pkg.${NC}"
                elif [ -n "$AUR_HELPER" ]; then
                    echo -e "${YELLOW}Pacman failed. Attempting to install $pkg via $AUR_HELPER...${NC}"
                    $AUR_HELPER -S --noconfirm "$pkg"
                    echo -e "${GREEN}[✓] Successfully installed $pkg via AUR.${NC}"
                else
                    echo -e "${RED}Error: Failed to install $pkg. Please install it manually.${NC}"
                    exit 1
                fi
                ;;
        esac
    fi
}

install_package "libva-nvidia-driver" "VA-API translation layer for NVDEC"

if ! command -v vainfo &>/dev/null; then
    install_package "libva-utils" "provides vainfo tool"
else
    echo -e "${GREEN}[✓] libva-utils (vainfo) is already installed.${NC}"
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
__GLX_VENDOR_LIBRARY_NAME=nvidia
ENABLE_HDR_WSI=1
EOF
echo -e "${GREEN}[✓] Created systemd-user configuration at:${NC} $SYSTEMD_ENV_FILE"

# Shell configuration exports with clean blocks
export_to_shell_config() {
    local shell_rc="$1"
    if [ -f "$shell_rc" ]; then
        # Check if the block already exists
        if grep -q "# >>> nvidia-vaapi-setup start >>>" "$shell_rc"; then
            echo -e "${YELLOW}Updating existing env variables block in:${NC} $(basename "$shell_rc")"
            # Remove the old block using sed
            sed -i '/# >>> nvidia-vaapi-setup start >>>/,/# <<< nvidia-vaapi-setup end <<</d' "$shell_rc"
        fi
        
        # Clean up old single exports if present from previous script versions
        if grep -q "export LIBVA_DRIVER_NAME=nvidia" "$shell_rc" && ! grep -q "# >>> nvidia-vaapi-setup start >>>" "$shell_rc"; then
            echo -e "${YELLOW}Cleaning up legacy environment variable exports in:${NC} $(basename "$shell_rc")"
            sed -i '/export LIBVA_DRIVER_NAME=nvidia/d' "$shell_rc"
            sed -i '/export NVD_BACKEND=direct/d' "$shell_rc"
        fi

        echo -e "${YELLOW}Writing env variables block to:${NC} $(basename "$shell_rc")"
        cat <<'EOF' >> "$shell_rc"

# >>> nvidia-vaapi-setup start >>>
# NVIDIA VA-API and HDR video acceleration variables
export LIBVA_DRIVER_NAME=nvidia
export NVD_BACKEND=direct
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export ENABLE_HDR_WSI=1
# <<< nvidia-vaapi-setup end <<<
EOF
        echo -e "${GREEN}[✓] Successfully updated:${NC} $(basename "$shell_rc")"
    fi
}

export_to_shell_config "$HOME/.zshrc"
export_to_shell_config "$HOME/.bashrc"

# 6. Detect Browsers & Configure Flags
echo -e "\n${CYAN}[5/6] Scanning and Configuring Browsers...${NC}"

declare -A BROWSERS=(
    ["brave-origin-flags.conf"]="brave-origin"
    ["brave-flags.conf"]="brave"
    ["brave-beta-flags.conf"]="brave-beta"
    ["brave-nightly-flags.conf"]="brave-nightly"
    ["chromium-flags.conf"]="chromium"
    ["chrome-flags.conf"]="google-chrome"
    ["chrome-beta-flags.conf"]="google-chrome-beta"
    ["chrome-unstable-flags.conf"]="google-chrome-unstable"
)

CONFIGURED_ANY=false

# The direct, optimal acceleration and HDR playback flags
ACCEL_FLAGS=$(cat <<'EOF'
--ozone-platform-hint=auto
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--use-gl=egl
--enable-features=VaapiVideoDecoder,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks,UseHDRTransferFunction,UseSkiaRenderer,WaylandFractionalScaleV1,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL
--disable-features=UseChromeOSDirectVideoDecoder
EOF
)

for config_file in "${!BROWSERS[@]}"; do
    binary_name="${BROWSERS[$config_file]}"
    if command -v "$binary_name" &>/dev/null; then
        echo -e "${GREEN}[✓] Found installed browser:${NC} $binary_name"
        target_path="$HOME/.config/$config_file"
        
        # Backup old config if present to avoid losing user modifications
        if [ -f "$target_path" ]; then
            echo -e "${YELLOW}Backing up existing config to:${NC} ${target_path}.bak"
            cp "$target_path" "${target_path}.bak"
        fi
        
        echo -e "${YELLOW}Writing launch flags configuration to:${NC} $target_path"
        echo "$ACCEL_FLAGS" > "$target_path"
        echo -e "${GREEN}[✓] Flags written successfully!${NC}"
        CONFIGURED_ANY=true
    fi
done

if [ "$CONFIGURED_ANY" = false ]; then
    echo -e "${YELLOW}[!] No supported Chromium-based browsers detected.${NC}"
    echo -e "Creating default config files in case you install them later..."
    echo "$ACCEL_FLAGS" > "$HOME/.config/brave-flags.conf"
    echo "$ACCEL_FLAGS" > "$HOME/.config/chromium-flags.conf"
fi

# 6.5. Update PWA and Autostart Desktop Shortcuts
# Autostart and PWA shortcuts generated by Chrome/Brave run the raw binary in /opt/ directly,
# which completely bypasses the wrapper script in /usr/bin/ and fails to load your flag files.
echo -e "\n${CYAN}[5.5/6] Updating Desktop Launchers to use Wrapper Scripts...${NC}"
DESKTOP_DIRS=("$HOME/.config/autostart" "$HOME/.local/share/applications")
UPDATED_DESKTOP=false

for dir in "${DESKTOP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "Scanning shortcuts in $dir..."
        if find "$dir" -name "*.desktop" -type f -exec sed -i -E \
            -e 's|/opt/brave-origin-bin/brave-origin|/usr/bin/brave-origin|g' \
            -e 's|/opt/brave-origin-bin/brave|/usr/bin/brave-origin|g' \
            -e 's|/opt/brave-bin/brave|/usr/bin/brave|g' \
            -e 's|/opt/brave.com/brave-origin-beta/brave-origin-beta|/usr/bin/brave-origin-beta|g' \
            -e 's|/opt/brave.com/brave-origin-beta/brave|/usr/bin/brave-origin-beta|g' \
            -e 's|/opt/google/chrome/google-chrome|/usr/bin/google-chrome|g' \
            -e 's|/opt/google/chrome/chrome|/usr/bin/google-chrome|g' \
            -e 's|/opt/google/chrome-beta/google-chrome-beta|/usr/bin/google-chrome-beta|g' \
            -e 's|/opt/google/chrome-unstable/google-chrome-unstable|/usr/bin/google-chrome-unstable|g' \
            {} + 2>/dev/null; then
            UPDATED_DESKTOP=true
        fi
    fi
done

if [ "$UPDATED_DESKTOP" = true ]; then
    echo -e "${GREEN}[✓] Desktop shortcuts updated successfully!${NC}"
fi

# Offer to kill running browser processes (otherwise the old processes block the flags)
RUNNING_BROWSERS=$(pgrep -f -i -d ' ' "brave|chrome|chromium" | grep -v "$$" || true)
if [ -n "$RUNNING_BROWSERS" ]; then
    echo -e "\n${YELLOW}[!] Detected active browser processes running in the background.${NC}"
    echo -e "    Since existing browser processes were launched without flags (e.g., autostarted PWAs),"
    echo -e "    you must close them for the hardware video acceleration config to take effect."
    read -r -p "Would you like to close all running Chrome/Brave browser processes now? [Y/n] " kill_yn
    case $kill_yn in
        [Nn]*)
            echo -e "${YELLOW}Please manually close/kill all browser instances before testing.${NC}"
            ;;
        *)
            echo -e "${YELLOW}Closing browser processes...${NC}"
            # Kill processes matching brave, chrome, chromium
            pkill -f -i "brave" || true
            pkill -f -i "chrome" || true
            pkill -f -i "chromium" || true
            echo -e "${GREEN}[✓] Browser processes terminated.${NC}"
            ;;
    esac
fi

# 6.6. Verify KDE Plasma Session Restore Settings
KSMSERVER_RC="$HOME/.config/ksmserverrc"
if [ -f "$KSMSERVER_RC" ]; then
    # If [General] is not present or loginMode is set to restorePreviousLogout, warn the user
    # because session restore bypasses wrapper scripts and causes flagless browser restarts.
    LOGIN_MODE="restorePreviousLogout" # default
    if grep -q "loginMode=" "$KSMSERVER_RC"; then
        LOGIN_MODE=$(grep "loginMode=" "$KSMSERVER_RC" | cut -d'=' -f2)
    fi
    
    if [ "$LOGIN_MODE" = "restorePreviousLogout" ]; then
        echo -e "\n${YELLOW}[!] Warning: KDE Desktop Session Restore is active.${NC}"
        echo -e "    On reboot, KDE will automatically restore your running apps by calling"
        echo -e "    the raw browser binary directly, bypassing all flags and configurations."
        read -r -p "Would you like to switch KDE to start with an empty session instead? [Y/n] " kde_yn
        case $kde_yn in
            [Nn]*)
                echo -e "${YELLOW}Please remember to manually close and reopen Brave if it stutters after rebooting.${NC}"
                ;;
            *)
                echo -e "${YELLOW}Configuring KDE to start with an empty session...${NC}"
                if grep -q "\[General\]" "$KSMSERVER_RC"; then
                    if grep -q "loginMode=" "$KSMSERVER_RC"; then
                        sed -i 's/loginMode=.*/loginMode=default/' "$KSMSERVER_RC"
                    else
                        sed -i '/\[General\]/a loginMode=default' "$KSMSERVER_RC"
                    fi
                else
                    cat <<EOF >> "$KSMSERVER_RC"

[General]
loginMode=default
EOF
                fi
                echo -e "${GREEN}[✓] KDE Session Restore set to start with empty session.${NC}"
                ;;
        esac
    fi
fi

# 7. Verification Steps
echo -e "\n${CYAN}[6/6] Finalizing Setup...${NC}"
echo -e "${PURPLE}┌────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${PURPLE}│${GREEN}            🎉 SUCCESS: Configuration applied successfully!         ${PURPLE}│${NC}"
echo -e "${PURPLE}└────────────────────────────────────────────────────────────────────┘${NC}"

echo -e "\n${YELLOW}🔔 IMPORTANT ACTIONS REQUIRED:${NC}"
if [ "$REBOOT_REQUIRED" = true ]; then
    echo -e "  ${RED}✦ REBOOT REQUIRED:${NC} Please reboot your PC now for the kernel modesetting and VA-API changes to take effect."
else
    echo -e "  ${CYAN}✦${NC} For systemd and GUI applications to pick up the new variables:"
    echo -e "    Log out of your desktop session and log back in (or restart your PC)."
fi
echo -e "  ${CYAN}✦${NC} To test immediately (if modesetting is already active):"
echo -e "    Launch your browser from a newly opened terminal window."

echo -e "\n${CYAN}🌈 HDR MOUNTING AND COLOR SYSTEM CONFIGURATION:${NC}"
echo -e "  To achieve true 4K HDR video playback, you must ensure:"
echo -e "  1. You are running a ${GREEN}Wayland desktop session${NC} (e.g. KDE Plasma 6+ or GNOME under Wayland)."
echo -e "  2. HDR is ${GREEN}enabled in your system settings${NC} (e.g. System Settings > Display > Enable HDR)."
echo -e "  3. Color management support is functional on your monitor."

echo -e "\n${CYAN}🔍 HOW TO VERIFY HARDWARE ACCELERATION:${NC}"
echo -e "  1. Open a terminal and run: ${GREEN}nvtop${NC} (or: ${GREEN}watch -n 1 nvidia-smi${NC})"
echo -e "     (Install nvtop via 'sudo pacman -S nvtop' if you don't have it)"
echo -e "  2. Launch your browser (e.g., ${GREEN}brave${NC} or ${GREEN}chromium${NC}) from a new terminal."
echo -e "  3. Play a 4K 60FPS HDR video on YouTube."
echo -e "  4. Look at ${GREEN}nvtop${NC}:"
echo -e "     - Check the ${GREEN}DEC (Decoder)${NC} column. It should show active load (15% - 45%)."
echo -e "     - If it remains at 0%, check ${YELLOW}chrome://gpu${NC} and ${YELLOW}chrome://media-internals${NC} for errors."

echo -e "\n${PURPLE}💡 PRO-TIP FOR HIGH RESOLUTIONS (4K / 8K) & AV1:${NC}"
if [ "$HAS_AV1" = true ]; then
    echo -e "  Your GPU (${BLUE}$GPU_NAME${NC}) supports ${GREEN}AV1 hardware decoding${NC} natively!"
    echo -e "  YouTube's default AV1 stream will be fully accelerated by your GPU's NVDEC."
    echo -e "  No need for 'h264ify' extensions unless you experience driver-level issues."
else
    echo -e "  Your GPU (${BLUE}$GPU_NAME${NC}) does NOT support AV1 hardware decoding."
    echo -e "  YouTube's default AV1 stream will decode on your CPU, which might lag."
    echo -e "  Install the ${CYAN}Enhanced h264ify${NC} extension and toggle ${YELLOW}\"Block AV1\"${NC} to force"
    echo -e "  VP9/H.264 formats, which your GPU accelerates flawlessly."
fi
echo
