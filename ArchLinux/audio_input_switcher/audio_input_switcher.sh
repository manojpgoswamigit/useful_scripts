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
