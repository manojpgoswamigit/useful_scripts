# Audio Input Switcher

**CachyOS (PipeWire)**  
Tested in: CachyOS

Small Bash script to cycle the default PulseAudio/pipewire-pulse input (source/microphone) and show a desktop notification with the new device name.

## Key features
- Cycle through available input sources (microphones) using `pactl`.
- Automatically filters out monitor sources (like output monitor streams) so you only cycle through actual input devices.
- Automatically moves active recording streams (e.g. Discord, OBS, browser audio calls) to the new default input source so the switch happens instantly.
- Show a notification using `notify-send` with the human-friendly device description and a microphone icon.
- Minimal, dependency-light Bash script suitable for binding to a hotkey.

## Setup Instructions

### 1. Create the Script
Open your terminal and run the following commands to create the file:

```bash
mkdir -p ~/.local/bin
nano ~/.local/bin/audio_input_switcher.sh
```

Paste the following code into the editor:

```bash
#!/bin/bash

# Get the currently active default source
current_source=$(pactl get-default-source)

# Get a list of all non-monitor sources and their descriptions
mapfile -t lines < <(pactl list sources)
sources=()
descriptions=()
current_name=""

for line in "${lines[@]}"; do
    if [[ "$line" =~ [[:space:]]*Name:[[:space:]]*(.*) ]]; then
        current_name="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ [[:space:]]*Description:[[:space:]]*(.*) ]]; then
        current_desc="${BASH_REMATCH[1]}"
        # Exclude monitor sources (e.g. monitor of speakers/outputs)
        if [[ ! "$current_name" =~ \.monitor$ ]]; then
            sources+=("$current_name")
            descriptions+=("$current_desc")
        fi
    fi
done

# If no sources found, exit
if [ ${#sources[@]} -eq 0 ]; then
    notify-send "Audio Input Switcher" "No input devices found." --icon=dialog-warning
    exit 1
fi

# Find the index of the current source
current_index=-1
for i in "${!sources[@]}"; do
    if [[ "${sources[$i]}" == "$current_source" ]]; then
        current_index=$i
        break
    fi
done

# Calculate the next index (default to 0 if current source was not in the filtered list)
if [ "$current_index" -eq -1 ]; then
    next_index=0
else
    next_index=$(( (current_index + 1) % ${#sources[@]} ))
fi

next_source=${sources[$next_index]}
next_desc=${descriptions[$next_index]}

# Set the next source as default
pactl set-default-source "$next_source"

# Move all active recording streams to the new default source
mapfile -t source_outputs < <(pactl list short source-outputs | awk '{print $1}')
for output in "${source_outputs[@]}"; do
    if [ -n "$output" ]; then
        pactl move-source-output "$output" "$next_source" 2>/dev/null
    fi
done

# Send notification with the human-readable description
notify-send "Audio Input Changed" "Switched to: $next_desc" --icon=audio-input-microphone
```

Save and exit (`Ctrl+O`, `Enter`, then `Ctrl+X`).

### 2. Make it Executable
Run this command to give the file permission to run:

```bash
chmod +x ~/.local/bin/audio_input_switcher.sh
```

### 3. Bind to a Shortcut
You can map a mouse button or a keyboard key to trigger this script.

#### Define a "Dummy" Shortcut in KDE:
1. Open **System Settings** > **Shortcuts** > **Add New** > **Command**.
2. Set **Command**: `/home/mpi/.local/bin/audio_input_switcher.sh`
3. Assign a keyboard combination you'll never actually press (e.g., `Meta + Shift + F11`).

#### Map a mouse button to that shortcut using `keyd`:
1. Edit your configuration: `sudo nano /etc/keyd/default.conf`
2. Add your button mapping (replace `mouse2` with the correct ID):
   ```ini
   [main]
   mouse2 = M-S-f11
   ```
3. Reload keyd: `sudo keyd reload`

Now, every time you press that button/shortcut, the script will run, cycle to the next physical microphone, update your active recording apps, and display a desktop notification.

---

## Requirements
- Linux with PulseAudio or PipeWire (with pipewire-pulse providing `pactl`)
- `pactl` (usually provided by `pulseaudio-utils` or `pipewire-pulse`)
- `notify-send` (provided by `libnotify-bin` or your desktop environment)

## Usage
- Run manually from the script directory:
  ```bash
  ./audio_input_switcher.sh
  ```
- Or, if installed to your PATH:
  ```bash
  audio_input_switcher.sh
  ```

## How it works
1. The script retrieves the active default source name via `pactl get-default-source`.
2. It parses the output of `pactl list sources` to align device names with their descriptions while filtering out `.monitor` sources.
3. It selects the next source in the list (wrapping around back to 0) and sets it as the default via `pactl set-default-source`.
4. It queries active source outputs using `pactl list short source-outputs` and moves any existing recording streams (e.g., Discord or browser streams) to the new default source using `pactl move-source-output`.
5. It triggers a notification with the new device's name.

## Troubleshooting
- **No sources listed**: Run `pactl list short sources` to verify which devices are detected.
- **Unplugged devices won't stick**: If you try to switch to a motherboard audio jack device and it immediately reverts or does not switch, this is expected behavior from PipeWire/WirePlumber if nothing is physically plugged into the jack.
- **`pactl: command not found`**: Install `pulseaudio-utils` or ensure PipeWire's `pipewire-pulse` compatibility layer is installed.
- **No notification**: Ensure `notify-send` is installed (e.g. `libnotify-bin` or `libnotify`) and your desktop environment's notification daemon is active.

## License
This script follows the repository license. See [LICENSE](../../LICENSE).
