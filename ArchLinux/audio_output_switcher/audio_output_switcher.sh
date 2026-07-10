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