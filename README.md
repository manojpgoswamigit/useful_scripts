# Useful Scripts 🚀

A curated collection of system automation, utilities, and configuration scripts to make desktop Linux life easier and more productive.

Tested and optimized for **CachyOS / Arch Linux** using **PipeWire**.

---

## 📁 Repository Structure

Below are the utilities available in this repository:

### 🎙️ Audio Utilities

*   **[Audio Output Switcher](file:///home/mpi/Documents/GitHub/useful_scripts/Linux/audio_output_switcher)**
    *   **Description:** Cycles through available audio outputs (speakers, headphones, Bluetooth headsets) using `pactl`.
    *   **Features:** Displays desktop notifications with human-readable device names and matching speaker icons. Very lightweight and quick.
    *   **Usage:** Best bound to a hotkey or mouse button shortcut.
*   **[Audio Input Switcher](file:///home/mpi/Documents/GitHub/useful_scripts/Linux/audio_input_switcher)**
    *   **Description:** Cycles through physical audio input sources (microphones).
    *   **Features:** Automatically filters out internal `.monitor` streams, seamlessly shifts active recording inputs (e.g., in Discord, OBS, or browser calls) to the new default device, and sends desktop notifications with microphone icons.

### ⚙️ System Configuration

*   **[Topgrade Configuration Backup](file:///home/mpi/Documents/GitHub/useful_scripts/Linux/topgrade)**
    *   **Description:** Backup configuration (`topgrade.toml`) for [Topgrade](https://github.com/topgrade-rs/topgrade), the ultimate terminal package and tool updater.
    *   **Features:** Clean, customized profile using `paru`, auto-cleanup, Flatpak support, and custom exclusion list.

---

## 🚀 Getting Started

To use any of the scripts:

1.  Clone the repository:
    ```bash
    git clone https://github.com/manojpgoswamigit/useful_scripts.git
    cd useful_scripts
    ```
2.  Make sure the script files are executable:
    ```bash
    chmod +x Linux/audio_input_switcher/audio_input_switcher.sh
    chmod +x Linux/audio_output_switcher/audio_output_switcher.sh
    ```
3.  Refer to the sub-folder `README.md` files for specific configuration details (e.g., mapping to mouse buttons or keyboard shortcuts using `keyd` and system shortcut managers).

## 📄 License

This repository is licensed under the MIT License. See [LICENSE](file:///home/mpi/Documents/GitHub/useful_scripts/LICENSE) for details.
