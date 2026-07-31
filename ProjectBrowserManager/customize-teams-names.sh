#!/bin/bash
# ==============================================================================
# customize-teams-names.sh
#
# Customizes taskbar hover names, tray tooltips, window titles, and icons for all
# installed Microsoft Teams application instances (Native, Flatpak, PWAs, Snaps).
# Updates both .desktop launcher files & Electron appTitle/appIcon config.json.
# Allows interactive runtime choice to customize or reset app icons anytime.
# ==============================================================================

set -e

# --- ANSI Color Tokens ---
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"
BLUE="\033[34m"
NC="\033[0m" # No Color

# --- Icons ---
CHECK="✔"
CROSS="✖"
INFO="ℹ"
GLOBE="🌐"
GEAR="⚙"

print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║       💬 Microsoft Teams Taskbar & Hover Name Customizer             ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# Function to reset all Teams icons to default system icons
do_reset_icons() {
  echo -e "${BLUE}${GEAR} Resetting all Teams app icons to default system icons...${NC}"
  python3 -c "
import os, json, re
user_apps_dir = os.path.expanduser('~/.local/share/applications')

dt1 = os.path.join(user_apps_dir, 'teams-for-linux.desktop')
if os.path.isfile(dt1):
    with open(dt1, 'r') as f: content = f.read()
    content = re.sub(r'^Icon=.*', 'Icon=teams-for-linux', content, flags=re.M)
    content = re.sub(r'--appIcon=[\"\'][^\"\']*[\"\']|--appIcon=[^\s]+', '', content)
    with open(dt1, 'w') as f: f.write(content)

dt2 = os.path.join(user_apps_dir, 'com.github.IsmaelMartinez.teams_for_linux.desktop')
if os.path.isfile(dt2):
    with open(dt2, 'r') as f: content = f.read()
    content = re.sub(r'^Icon=.*', 'Icon=com.github.IsmaelMartinez.teams_for_linux', content, flags=re.M)
    content = re.sub(r'--appIcon=[\"\'][^\"\']*[\"\']|--appIcon=[^\s]+', '', content)
    with open(dt2, 'w') as f: f.write(content)

for cfg in [os.path.expanduser('~/.config/teams-for-linux/config.json'), os.path.expanduser('~/.var/app/com.github.IsmaelMartinez.teams_for_linux/config/teams-for-linux/config.json')]:
    if os.path.isfile(cfg):
        try:
            with open(cfg, 'r') as f: d = json.load(f)
            d.pop('appIcon', None)
            with open(cfg, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
        except Exception: pass
"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
  fi
  echo -e "${GREEN}${BOLD}${CHECK} Icons reset to default system icons successfully!${NC}"
}

# CLI flag handling for --reset-icons
if [ "${1:-}" = "--reset-icons" ]; then
  print_banner
  do_reset_icons
  exit 0
fi

# Scan system for installed Microsoft Teams applications
scan_teams_apps() {
  python3 -c "
import os, glob, re, json

desktop_dirs = [
    os.path.expanduser('~/.local/share/applications'),
    '/usr/share/applications',
    os.path.expanduser('~/.local/share/flatpak/exports/share/applications'),
    '/var/lib/flatpak/exports/share/applications',
    '/var/lib/snapd/desktop/applications'
]

override_map = {}
for base in desktop_dirs:
    if not os.path.isdir(base): continue
    for fname in os.listdir(base):
        if fname.endswith('.desktop'):
            full_path = os.path.join(base, fname)
            if fname not in override_map:
                override_map[fname] = full_path

seen_keys = set()
teams_apps = []

for fname, dt in override_map.items():
    if 'antigravity-browser-opener' in dt: continue
    try:
        with open(dt, 'r', errors='ignore') as f:
            content = f.read()
        
        if 'steam' in fname.lower() or 'teamviewer' in fname.lower():
            continue
            
        name_m = re.search(r'^Name=(.+)$', content, re.MULTILINE)
        exec_m = re.search(r'^Exec=(.+)$', content, re.MULTILINE)
        comment_m = re.search(r'^Comment=(.+)$', content, re.MULTILINE)
        icon_m = re.search(r'^Icon=(.+)$', content, re.MULTILINE)

        name = name_m.group(1).strip() if name_m else fname
        exec_cmd = exec_m.group(1).strip() if exec_m else ''
        comment = comment_m.group(1).strip() if comment_m else ''
        icon = icon_m.group(1).strip() if icon_m else ''
        
        is_teams = False
        if any(k in fname.lower() for k in ['teams', 'msteams', 'ms-teams']):
            is_teams = True
        elif any(k in name.lower() for k in ['microsoft teams', 'teams for linux', 'g teams', 'msteams', 'ms teams']):
            is_teams = True
        elif 'teams.microsoft.com' in exec_cmd.lower() or 'teams.live.com' in exec_cmd.lower():
            is_teams = True
        elif 'teams' in comment.lower() and ('microsoft' in comment.lower() or 'chat' in comment.lower()):
            is_teams = True

        if is_teams:
            app_id = fname.replace('.desktop', '')
            if 'flatpak' in exec_cmd:
                fp_match = re.search(r'([a-zA-Z0-9_\-\.]+\.teams[a-zA-Z0-9_\-\.]*)', exec_cmd, re.I)
                if fp_match:
                    app_id = f'flatpak:{fp_match.group(1)}'
                else:
                    fp_match2 = re.search(r'([a-zA-Z0-9_\-\.]+\.[a-zA-Z0-9_\-\.]+)', exec_cmd)
                    if fp_match2:
                        app_id = f'flatpak:{fp_match2.group(1)}'
            elif '--app-id=' in exec_cmd:
                pwa_id = re.search(r'--app-id=([a-zA-Z0-9]+)', exec_cmd)
                if pwa_id:
                    app_id = f'pwa:{pwa_id.group(1)}'
            
            key = (name, app_id, exec_cmd)
            if key not in seen_keys:
                seen_keys.add(key)
                teams_apps.append({
                    'id': app_id,
                    'fname': fname,
                    'name': name,
                    'exec': exec_cmd,
                    'comment': comment,
                    'icon': icon,
                    'desktop_file': dt
                })
    except Exception:
        pass

print(json.dumps(teams_apps))
"
}

print_banner

TEAMS_JSON=$(scan_teams_apps)
TEAMS_COUNT=$(echo "$TEAMS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")

if [ "$TEAMS_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}${INFO} No installed Microsoft Teams applications detected on your PC.${NC}"
  exit 0
fi

echo -e "${BOLD}Detected $TEAMS_COUNT Microsoft Teams application(s) on your PC:${NC}"
echo -e "  ${BOLD}1)${NC} Customize Teams taskbar names, tooltips, & icons"
echo -e "  ${BOLD}2)${NC} Reset all Teams app icons to default system icons"
echo ""
read -rp "Enter choice [1-2] (default 1): " RUNTIME_CHOICE

if [ "$RUNTIME_CHOICE" = "2" ]; then
  echo ""
  do_reset_icons
  exit 0
fi

echo ""

TEAMS_JSON="$TEAMS_JSON" python3 -c "
import os, sys, json, re

apps = json.loads(os.environ['TEAMS_JSON'])
user_apps_dir = os.path.expanduser('~/.local/share/applications')
os.makedirs(user_apps_dir, exist_ok=True)

BOLD = '\033[1m'
NC = '\033[0m'
GREEN = '\033[32m'
CYAN = '\033[36m'
YELLOW = '\033[33m'
DIM = '\033[2m'

for idx, app in enumerate(apps):
    src_file = app['desktop_file']
    fname = app['fname']
    app_id = app['id']
    dest_file = os.path.join(user_apps_dir, fname)

    print(f'----------------------------------------------------------------------')
    print(f'📱 App #{idx+1}: {BOLD}{CYAN}{app[\"name\"]}{NC}')
    print(f'   Source Desktop File: {DIM}{src_file}{NC}')
    print(f'   Target Override:     {DIM}{dest_file}{NC}')
    print(f'   Current Name:        {GREEN}{app[\"name\"]}{NC}')
    print(f'   Current Tooltip:     {GREEN}{app[\"comment\"] or \"None\"}{NC}')
    print(f'   Current Icon:        {GREEN}{app[\"icon\"] or \"Default\"}{NC}\n')

    # 1. Custom Name
    try:
        new_name = input(f'Enter new Taskbar & Tray Name for App #{idx+1} [Leave blank to keep \"{app[\"name\"]}\"]: ').strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not new_name:
        new_name = app['name']

    # 2. Custom Tooltip / Comment
    default_tooltip = app['comment'] or f'{new_name} Desktop Application'
    try:
        new_comment = input(f'Enter new Hover Tooltip text [Leave blank to keep \"{default_tooltip}\"]: ').strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not new_comment:
        new_comment = default_tooltip

    # 3. Custom Icon (supports 'reset' / 'default' to restore original icon)
    try:
        new_icon_input = input(f'Enter Custom Icon path/name (or type \"reset\" for system default) [Leave blank to keep \"{app[\"icon\"] or \"Default\"}\"]: ').strip()
    except (EOFError, KeyboardInterrupt):
        break

    is_reset_icon = False
    if new_icon_input.lower() in ['reset', 'default', 'r']:
        is_reset_icon = True
        new_icon = 'com.github.IsmaelMartinez.teams_for_linux' if 'flatpak' in app_id else 'teams-for-linux'
    elif new_icon_input:
        new_icon = new_icon_input
    else:
        new_icon = app['icon']

    # Read original desktop file lines
    with open(src_file, 'r', errors='ignore') as f:
        lines = f.readlines()

    has_name = False
    has_generic = False
    has_comment = False
    has_icon = False
    new_lines = []
    in_desktop = False

    for line in lines:
        if line.strip() == '[Desktop Entry]':
            in_desktop = True
            new_lines.append(line)
            continue
        elif line.startswith('[') and line.strip().endswith(']'):
            in_desktop = False

        if in_desktop:
            if line.startswith('Name='):
                new_lines.append(f'Name={new_name}\n')
                has_name = True
                continue
            elif line.startswith('GenericName='):
                new_lines.append(f'GenericName={new_name}\n')
                has_generic = True
                continue
            elif line.startswith('Comment='):
                new_lines.append(f'Comment={new_comment}\n')
                has_comment = True
                continue
            elif line.startswith('Icon='):
                new_lines.append(f'Icon={new_icon}\n')
                has_icon = True
                continue
            elif line.startswith('Exec='):
                exec_val = line.split('Exec=', 1)[1].strip()
                # Inject --appTitle and --appIcon flags into Exec string
                exec_val = re.sub(r'--appTitle=[\"\'][^\"\']*[\"\']|--appTitle=[^\s]+', '', exec_val)
                exec_val = re.sub(r'--appIcon=[\"\'][^\"\']*[\"\']|--appIcon=[^\s]+', '', exec_val)
                
                flags = f'--appTitle=\"{new_name}\"'
                if new_icon and not is_reset_icon:
                    flags += f' --appIcon=\"{new_icon}\"'
                
                if '@@u' in exec_val:
                    exec_val = exec_val.replace('@@u', f'{flags} @@u')
                elif '%U' in exec_val:
                    exec_val = exec_val.replace('%U', f'{flags} %U')
                elif '%u' in exec_val:
                    exec_val = exec_val.replace('%u', f'{flags} %u')
                else:
                    exec_val = f'{exec_val} {flags}'
                
                new_lines.append(f'Exec={exec_val}\n')
                continue

        new_lines.append(line)

    insert_idx = -1
    for i, l in enumerate(new_lines):
        if l.strip() == '[Desktop Entry]':
            insert_idx = i + 1
            break

    if insert_idx != -1:
        if not has_name and new_name:
            new_lines.insert(insert_idx, f'Name={new_name}\n')
        if not has_generic and new_name:
            new_lines.insert(insert_idx, f'GenericName={new_name}\n')
        if not has_comment and new_comment:
            new_lines.insert(insert_idx, f'Comment={new_comment}\n')
        if not has_icon and new_icon:
            new_lines.insert(insert_idx, f'Icon={new_icon}\n')

    with open(dest_file, 'w') as f:
        f.writelines(new_lines)

    # Also update Electron appTitle & appIcon in config.json
    config_paths = []
    if app_id.startswith('flatpak:'):
        fp_id = app_id.split('flatpak:', 1)[1]
        config_paths.append(os.path.expanduser(f'~/.var/app/{fp_id}/config/teams-for-linux/config.json'))
    else:
        config_paths.append(os.path.expanduser('~/.config/teams-for-linux/config.json'))

    for cfg_path in config_paths:
        try:
            os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
            cfg_data = {}
            if os.path.isfile(cfg_path):
                with open(cfg_path, 'r') as cf:
                    cfg_data = json.load(cf)
            cfg_data['appTitle'] = new_name
            if is_reset_icon:
                cfg_data.pop('appIcon', None)
            elif new_icon:
                cfg_data['appIcon'] = new_icon
            with open(cfg_path, 'w') as cf:
                json.dump(cfg_data, cf, indent=2)
                cf.write('\n')
        except Exception:
            pass

    icon_display = f'Default System Icon ({new_icon})' if is_reset_icon else new_icon
    print(f'   • Taskbar Icon:    {GREEN}{icon_display}{NC}')
    print('')
"

# Refresh desktop database caches so KDE Plasma and taskbars update immediately
echo -e "${BLUE}${GEAR} Refreshing KDE Plasma desktop database caches...${NC}"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
fi

echo -e "${GREEN}${BOLD}${CHECK} Taskbar Hover Names & Desktop Entries Updated Successfully!${NC}"
echo -e "${YELLOW}⚠️ NOTE:${NC} Running Teams applications must be restarted (quit & re-launched) for Electron tray tooltips and icons to take effect."
echo ""
