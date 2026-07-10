#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print a clear error message with the failing line number on unexpected exit
trap 'echo "ERROR: Script failed at line ${LINENO}. Partial changes may have been applied. Review the output above."' ERR

echo "======================================================"
echo "   Starting CachyOS KDE Plasma 6 Font Optimization   "
echo "======================================================"

# 1. Verify environment
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi


# 2. Sync core typography packages
echo "--> Ensuring optimal open-source font families are installed..."
pacman -S --needed --noconfirm inter-font ttf-jetbrains-mono noto-fonts

# 3. Handle System-Wide Fontconfig Symlinks
echo "--> Applying clean Fontconfig layout rules..."
FONTCONFIG_DIR="/etc/fonts/conf.d"
AVAIL_DIR="/usr/share/fontconfig/conf.avail"

# Ensure the fontconfig conf.d directory exists
mkdir -p "${FONTCONFIG_DIR}"

# Remove potentially conflicting geometric rules
rm -f "${FONTCONFIG_DIR}/10-hinting-slight.conf"
rm -f "${FONTCONFIG_DIR}/10-sub-pixel-rgb.conf"

# Link clean, modern presets
# 70-no-bitmaps blocks blocky, unscalable legacy bitmap elements
if [ -f "${AVAIL_DIR}/70-no-bitmaps.conf" ]; then
    ln -sf "${AVAIL_DIR}/70-no-bitmaps.conf" "${FONTCONFIG_DIR}/"
fi

# 11-lcdfilter-default standardizes the geometry engine across different GUI toolkits
if [ -f "${AVAIL_DIR}/11-lcdfilter-default.conf" ]; then
    ln -sf "${AVAIL_DIR}/11-lcdfilter-default.conf" "${FONTCONFIG_DIR}/"
fi

# 4. Enforce System-Wide FreeType Stem Darkening
echo "--> Forcing FreeType stem darkening properties..."
FREETYPE_PROFILE="/etc/profile.d/freetype2.sh"

cat << 'EOF' > "${FREETYPE_PROFILE}"
#!/bin/sh
# Force the v40 interpreter to enable stem darkening for modern vector fonts
export FREETYPE_PROPERTIES="truetype:interpreter-version=40"
EOF

chmod +x "${FREETYPE_PROFILE}"

# 5. Fix Qt6/Wayland Fractional Scaling Coordinate Bug
echo "--> Setting layout rounding rules in /etc/environment..."
ENV_FILE="/etc/environment"
ROUNDING_RULE='QT_SCALE_FACTOR_ROUNDING_POLICY="RoundPreferFloor"'

if ! grep -q "QT_SCALE_FACTOR_ROUNDING_POLICY" "${ENV_FILE}"; then
    # Ensure the file ends with a newline before appending to avoid line-joining
    [[ -s "${ENV_FILE}" && $(tail -c1 "${ENV_FILE}" | wc -l) -eq 0 ]] && echo "" >> "${ENV_FILE}"
    echo "${ROUNDING_RULE}" >> "${ENV_FILE}"
fi

# 6. Rebuild Font Cache
echo "--> Regenerating system-wide font cache binaries..."
fc-cache -f -v > /dev/null 2>&1

echo "======================================================"
echo "          Optimization Completed Successfully!        "
echo "======================================================"
echo "Final Manual Steps Required:"
echo "1. Open KDE System Settings -> Appearance & Style -> Text & Fonts."
echo "2. Click 'Configure...' next to Anti-Aliasing."
echo "3. Set Sub-pixel rendering to: 'None (Grayscale)'"
echo "   (Crucial to stop color-fringing/blur on Plasma 6 Wayland)"
echo "4. Set Hinting style to: 'Slight'"
echo "5. Change your UI/General fonts to 'Inter' and fixed-width to 'JetBrains Mono'."
echo ""
echo "Please restart your computer to apply the updated environment parameters."