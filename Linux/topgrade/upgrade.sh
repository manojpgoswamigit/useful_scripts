#!/usr/bin/env bash

# Exit on error for safety
set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print header
echo -e "${BLUE}${BOLD}=======================================================${NC}"
echo -e "${BLUE}${BOLD}===   CachyOS & Topgrade System Upgrade Wrapper     ===${NC}"
echo -e "${BLUE}${BOLD}=======================================================${NC}"
echo

# Detect askpass helper if graphical
SUDO_CMD="sudo"
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    if [ -f "/usr/lib/ssh/x11-ssh-askpass" ]; then
        export SUDO_ASKPASS="/usr/lib/ssh/x11-ssh-askpass"
        SUDO_CMD="sudo -A"
    fi
fi

# Request sudo credentials upfront so the user doesn't get prompted mid-run
echo -e "${YELLOW}Acquiring administrator privileges...${NC}"
$SUDO_CMD true
echo -e "${GREEN}[✓] Privileges acquired.${NC}"
echo

# 1. Run Topgrade
echo -e "${CYAN}${BOLD}==> Phase 1: Running Topgrade upgrades...${NC}"
if topgrade; then
    echo -e "${GREEN}[✓] Topgrade upgrades completed successfully.${NC}"
else
    echo -e "${RED}Warning: Topgrade reported some errors or was interrupted.${NC}"
fi
echo

# 2. Check for Orphan Packages
echo -e "${CYAN}${BOLD}==> Phase 2: Scanning for orphan packages...${NC}"
mapfile -t orphans < <(pacman -Qtdq || true)
if [ "${#orphans[@]}" -gt 0 ]; then
    echo -e "${YELLOW}The following orphan packages were found:${NC}"
    printf "  - %s\n" "${orphans[@]}"
    echo
    read -p "Would you like to remove these orphan packages and their dependencies? [y/N]: " -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removing orphan packages...${NC}"
        $SUDO_CMD pacman -Rns "${orphans[@]}"
        echo -e "${GREEN}[✓] Orphan packages removed.${NC}"
    else
        echo -e "${BLUE}Skipped orphan removal.${NC}"
    fi
else
    echo -e "${GREEN}[✓] No orphan packages found.${NC}"
fi
echo

# 3. Check for Unused Flatpaks
echo -e "${CYAN}${BOLD}==> Phase 3: Scanning for unused Flatpak runtimes/packages...${NC}"
if command -v flatpak &> /dev/null; then
    flatpak_unused=$(flatpak uninstall --unused || true)
    if [ -n "$flatpak_unused" ] && echo "$flatpak_unused" | grep -q "Uninstalling"; then
        echo -e "${YELLOW}Unused Flatpak runtimes found. Uninstalling...${NC}"
        flatpak uninstall --unused -y
        echo -e "${GREEN}[✓] Unused Flatpaks uninstalled.${NC}"
    else
        echo -e "${GREEN}[✓] No unused Flatpaks found.${NC}"
    fi
else
    echo -e "${BLUE}Flatpak is not installed. Skipping Flatpak checks.${NC}"
fi
echo

# 4. Clean up Pacman Cache (paccache)
echo -e "${CYAN}${BOLD}==> Phase 4: Scanning for old cached packages...${NC}"
if command -v paccache &> /dev/null; then
    # Dry-run check for how many candidate files are there
    old_candidates=$(paccache -dk3 | sed -n 's/.*: \([0-9]*\) candidate.*/\1/p' || echo "0")
    uninstalled_candidates=$(paccache -duk0 | sed -n 's/.*: \([0-9]*\) candidate.*/\1/p' || echo "0")
    
    [ -z "${old_candidates}" ] && old_candidates="0"
    [ -z "${uninstalled_candidates}" ] && uninstalled_candidates="0"
    total_candidates=$((old_candidates + uninstalled_candidates))
    
    if [ "$total_candidates" -gt 0 ]; then
        echo -e "${YELLOW}Found ${total_candidates} cached package files that can be cleaned up.${NC}"
        read -p "Clean package cache? (Keeps latest 3 versions, removes uninstalled) [Y/n]: " -r answer
        if [[ "$answer" =~ ^[Yy]$ || -z "$answer" ]]; then
            echo -e "${YELLOW}Cleaning old pacman cache...${NC}"
            $SUDO_CMD paccache -rk3
            echo -e "${YELLOW}Cleaning uninstalled pacman cache...${NC}"
            $SUDO_CMD paccache -ruk0
            echo -e "${GREEN}[✓] Pacman package cache cleaned.${NC}"
        else
            echo -e "${BLUE}Skipped package cache cleanup.${NC}"
        fi
    else
        echo -e "${GREEN}[✓] Pacman package cache is already clean.${NC}"
    fi
else
    echo -e "${RED}paccache command not found (pacman-contrib package missing). Skipping cache cleanup.${NC}"
fi
echo

# 5. Check for Pending Kernel Updates (Reboot Check)
echo -e "${CYAN}${BOLD}==> Phase 5: Checking for pending kernel updates...${NC}"
kernel_file="/usr/lib/modules/$(uname -r)/vmlinuz"
if [ ! -f "${kernel_file}" ]; then
    echo -e "${RED}${BOLD}!!! WARNING: A kernel upgrade was installed. A reboot is required to load the new kernel !!!${NC}"
    echo
    read -p "Would you like to reboot the system now? [y/N]: " -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Rebooting in 5 seconds... Press Ctrl+C to abort.${NC}"
        for sec in {5..1}; do
            echo -ne "  Rebooting in ${sec}...\r"
            sleep 1
        done
        echo
        $SUDO_CMD systemctl reboot
    else
        echo -e "${YELLOW}Please consider rebooting your PC soon to apply the kernel update.${NC}"
    fi
else
    echo -e "${GREEN}[✓] No pending kernel updates. The running kernel matches the latest installed version.${NC}"
fi
echo

echo -e "${GREEN}${BOLD}=== Upgrade wrap-up completed! ===${NC}"
read -p "Press [Enter] to quit." -r _unused
