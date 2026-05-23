# Audio Output Switcher

**CachyOS (PipeWire)**  
Tested in: CachyOS

To set up the audio switcher from that gist, follow these steps. Since you are on CachyOS (PipeWire), this script will work perfectly as it uses `pactl` (the PulseAudio compatibility layer for PipeWire).

1. Create the Script
Open your terminal and run the following commands to create the file:

```bash
mkdir -p ~/.local/bin
nano ~/.local/bin/audio_output_switcher.sh
```
Paste the following code into the editor:

```bash
#!/bin/bash
# Get the currently active default sink
current_sink=$(pactl get-default-sink)

# Get a list of all sinks and their descriptions
# This creates an array of internal names
mapfile -t sinks < <(pactl list short sinks | awk '{print $2}')
# This creates an array of descriptions
mapfile -t descriptions < <(pactl list sinks | grep -E 'Description:' | cut -d: -f2- | sed 's/^[ \t]*//')

# Find the index of the current sink
current_index=0
for i in "${!sinks[@]}"; do
    if [[ "${sinks[$i]}" == "$current_sink" ]]; then
        current_index=$i
        break
    fi
done

# Calculate the next index
next_index=$(( (current_index + 1) % ${#sinks[@]} ))
next_sink=${sinks[$next_index]}
next_desc=${descriptions[$next_index]}

# Set the next sink
pactl set-default-sink "$next_sink"

# Send notification with the human-readable description
notify-send "Audio Output Changed" "Switched to: $next_desc" --icon=audio-speakers
```
Save and exit (Ctrl+O, Enter, then Ctrl+X).

2. Make it Executable
Run this command to give the file permission to run:

```bash
chmod +x ~/.local/bin/audio_output_switcher.sh
```

3. Bind to a Shortcut
Since you want to use a mouse button (via keyd), we will map the button to a custom keyboard shortcut, then map that shortcut to the script.

Define a "Dummy" Shortcut in KDE:

Open System Settings > Shortcuts > Add New > Command.

Command: /home/mpi/.local/bin/audio_output_switcher.sh

Assign a keyboard combination you'll never actually press (e.g., Meta + Shift + F12).

Map your mouse button to that shortcut using keyd:

Edit your configuration: `sudo nano /etc/keyd/default.conf`

Add your button mapping (replace mouse2 with the correct ID from your previous keyd monitor session):

```
[main]
mouse2 = M-S-f12
```

Reload keyd: `sudo keyd reload`

Now, every time you press that mouse button, the script will trigger, rotate to the next available audio device, and show a desktop notification of the change. This is the cleanest, most "pro" way to handle the switch without installing extra background daemons.

Small Bash script to cycle the default PulseAudio/pipewire-pulse output (sink) and show a desktop notification with the new device name.

**Key features**
- Cycle through available sinks using `pactl`
- Show a notification using `notify-send` with the human-friendly device description
- Minimal, dependency-light Bash script suitable for binding to a hotkey

**Requirements**
- Linux with PulseAudio or PipeWire (with pipewire-pulse providing `pactl`)
- `pactl` (usually provided by `pulseaudio-utils` or `pipewire-pulse`)
- `notify-send` (provided by `libnotify-bin` or your desktop environment)

**Installation**
1. Copy or move `audio_output_switcher.sh` to a location in your PATH, or keep it in-place and make it executable:

```bash
chmod +x audio_output_switcher.sh
# optional: install to /usr/local/bin
sudo install -m 755 audio_output_switcher.sh /usr/local/bin/audio_output_switcher.sh
```

**Usage**
- Run manually from the script directory:

```bash
./audio_output_switcher.sh
```

- Or, if installed to your PATH:

```bash
audio_output_switcher.sh
```

**Bind to a hotkey (examples)**
- GNOME / Settings → Keyboard → Custom Shortcut: set command to the full path to the script (e.g. `/usr/local/bin/audio_output_switcher.sh`) and assign a shortcut.
- i3wm (in `~/.config/i3/config`):

```
bindsym $mod+Shift+o exec --no-startup-id /home/you/bin/audio_output_switcher.sh
```

- sxhkd example:

```
super + p
	/home/you/bin/audio_output_switcher.sh
```

**How it works**
- The script determines the current default sink with `pactl get-default-sink`.
- It enumerates available sinks and descriptions using `pactl list short sinks` and `pactl list sinks`.
- It selects the next sink in the list (wraps around), sets it as the default with `pactl set-default-sink`, and sends a `notify-send` notification with the sink description.

Note: switching the default sink does not always move existing playback streams. To move running streams you can use `pactl list sink-inputs` and `pactl move-sink-input <index> <sink>`.

**Troubleshooting**
- No sinks listed: run `pactl list short sinks` to verify available devices.
- `pactl: command not found`: install `pulseaudio-utils` (PulseAudio) or ensure PipeWire's `pipewire-pulse` is installed.
- No notification: ensure `notify-send` is available (install `libnotify-bin`) and your notification daemon is running.

**License**
This script follows the repository license. See [LICENSE](../../LICENSE).

**Contributing / Improvements**
- Pull requests and suggestions are welcome. Possible improvements: move active sink inputs automatically after switching, add an option to list sinks, or a reverse cycle flag.

