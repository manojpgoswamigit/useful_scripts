# Postman Wayland Blurry Text Fix

This configuration fixes the blurry text rendering issue in Postman (both AUR/Pacman and Flatpak packages) when running on KDE Plasma Wayland with fractional or display scaling.

## The Problem
By default, Electron-based applications like Postman run under **XWayland** (the X11 compatibility layer) on Wayland desktops. When display scaling is configured (e.g., 125% or 150% scale in KDE Plasma settings), the window manager renders XWayland apps at their base resolution and scales them up using pixel stretching, leading to blurry fonts and interfaces.

## The Solution
To resolve this, we force Postman to run natively on **Wayland** using Chrome's Ozone platform engine by adding the following launch arguments:
* `--enable-features=UseOzonePlatform`
* `--ozone-platform=wayland`

This allows the desktop compositor to scale the application interface cleanly and natively, ensuring crisp text and a sharp interface.

## How to Apply the Fix

Run the installation script:
```bash
./install.sh
```

### What the script does:
1. **For AUR/Pacman (`postman-bin` / `postman`)**:
   Copies the system desktop entry from `/usr/share/applications/postman.desktop` to your user directory at `~/.local/share/applications/postman.desktop` and appends the ozone platform flags to the `Exec` line.
2. **For Flatpak (`com.getpostman.Postman`)**:
   Copies the exported Flatpak desktop entry to `~/.local/share/applications/com.getpostman.Postman.desktop` and appends the ozone platform flags to the `Exec` line.

## Verification
To verify that Postman is running natively on Wayland:
1. Close any running instances of Postman.
2. Launch Postman from your application menu (or KRunner).
3. Run the following command in a terminal:
   ```bash
   xlsclients
   ```
   * If Postman runs on native Wayland, it **will not** be listed in the output of `xlsclients`.
   * If it is listed, it is still running under XWayland.

Alternatively, under KDE Plasma, you can open **KDE System Monitor** or look at the window rules to see if the window is categorized as a Wayland client.

## Reverting the Changes
If you ever want to revert the changes and go back to the default behavior:
* For native Postman: `rm ~/.local/share/applications/postman.desktop`
* For Flatpak Postman: `rm ~/.local/share/applications/com.getpostman.Postman.desktop`
