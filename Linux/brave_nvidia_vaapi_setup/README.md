# NVIDIA Hardware Acceleration Setup for Chromium/Brave

This script automates the configuration of hardware-accelerated video decoding (VA-API/NVDEC) for Chromium-based browsers (specifically Brave and Chromium) on Linux systems running NVIDIA proprietary drivers under both X11 and Wayland sessions.

## Features
- Scans system GPU hardware to verify compatibility.
- Detects the desktop environment session type (X11 vs. Wayland).
- Detects and prompts to install `libva-nvidia-driver` (using `yay` or `paru` if present).
- Configures user-level systemd environment variables (`LIBVA_DRIVER_NAME` and `NVD_BACKEND`).
- Appends exports to shell profile files (`~/.zshrc` and `~/.bashrc`).
- Detects installed Chromium/Brave packages and writes the appropriate `*-flags.conf` configuration.

## Usage
Simply run the script as a regular user:

```bash
./install.sh
```

## How to Verify
1. Log out of your desktop session and log back in, or restart your system.
2. Launch your browser.
3. Open a video (e.g. 4K/1080p on YouTube).
4. Run `nvtop` (or `nvidia-smi`) in a terminal.
5. Verify that the **DEC** (Decoder) metric rises above 0% during video playback, indicating that hardware decoding is active.
