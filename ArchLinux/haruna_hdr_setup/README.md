# Haruna HDR Setup (Nvidia + KDE Wayland)

This script automates the installation of necessary Vulkan WSI layer for HDR on Arch Linux with Nvidia GPUs, and sets up a dedicated desktop launcher for Haruna with HDR mode enabled.

## Features
- Detects and installs `vk-hdr-layer-kwin6` or `vk-hdr-layer-kwin6-git` using an AUR helper (`yay` or `paru`).
- Creates a separate desktop entry called **Haruna Media Player (HDR)** that launches Haruna with the required environment variables (`ENABLE_HDR_WSI=1`).
- Integrates with the system launcher for easy search and access.

## Prerequisites
- Arch Linux running **KDE Plasma 6 (Wayland)**.
- Nvidia Proprietary Drivers.
- HDR-capable monitor (like the ASUS PG48UQ) with HDR enabled in System Settings.

## Usage
Run the script to begin setup:
```bash
chmod +x setup_hdr_haruna.sh
./setup_hdr_haruna.sh
```
