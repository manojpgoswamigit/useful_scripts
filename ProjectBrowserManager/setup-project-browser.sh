#!/bin/bash
# ==============================================================================
# setup-project-browser.sh
#
# Interactive per-project preferred web browser manager for Antigravity / VS Code.
# Redirects CLI & extension link opens (sf, xdg-open, gio, kde-open) per workspace
# without altering OS-level default browser settings.
# ==============================================================================

# Detect if script is being sourced in current shell
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  IS_SOURCED=1
else
  IS_SOURCED=0
  set -e
fi

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
ROCKET="🚀"
GLOBE="🌐"
TEST_ICON="🧪"
GEAR="⚙"

WRAPPER_BASE_DIR="$HOME/.local/share/antigravity-wrappers"
VSCODE_DIR="./.vscode"
SETTINGS_FILE="$VSCODE_DIR/settings.json"
TASKS_FILE="$VSCODE_DIR/tasks.json"
ENV_HELPER_FILE="$VSCODE_DIR/env.sh"

print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║        🌐 Antigravity / VS Code Project Browser Configurator         ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

show_help() {
  print_banner
  echo -e "${BOLD}USAGE:${NC}"
  echo "  ./setup-project-browser.sh [OPTION | BROWSER_NAME]"
  echo "  source ./setup-project-browser.sh [BROWSER_NAME]   (Activates instantly in current shell)"
  echo ""
  echo -e "${BOLD}COMMANDS / OPTIONS:${NC}"
  echo -e "  ${GREEN}[browser_name]${NC}  Configures project (e.g. firefox, chrome, brave, edge, helium, vivaldi, zen)"
  echo -e "  ${GREEN}--status, -s${NC}    Displays current workspace browser configuration & PATH status"
  echo -e "  ${GREEN}--test, -t${NC}      Tests opening a link with the configured project browser"
  echo -e "  ${GREEN}--reset, -r${NC}     Removes project browser configuration from .vscode/settings.json"
  echo -e "  ${GREEN}--help, -h${NC}      Displays this help menu"
  echo ""
  echo -e "${BOLD}EXAMPLES:${NC}"
  echo "  ./setup-project-browser.sh                # Interactive menu selection (Auto-scans PC)"
  echo "  ./setup-project-browser.sh firefox        # Quick-set to Firefox"
  echo "  ./setup-project-browser.sh helium         # Quick-set to Helium Browser"
  echo "  source ./setup-project-browser.sh chrome  # Quick-set & activate in current shell"
  echo "  source .vscode/env.sh                     # Activate existing project browser in current shell"
  echo "  ./setup-project-browser.sh --test         # Test launch link in configured browser"
  echo "  ./setup-project-browser.sh --status       # Check workspace configuration status"
  echo ""
}

# Register system-wide XDG URL handler for Electron/VS Code openExternal calls
install_desktop_url_handler() {
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

  cat << 'SMART_EOF' > "$HOME/.local/bin/antigravity-smart-open"
#!/bin/bash
URL="$1"

PROJECT_BROWSER_BIN=$(python3 -c "
import os, json

def find_bin():
    ws_file = os.path.expanduser('~/.config/antigravity-project-browser/active-workspace.json')
    if os.path.isfile(ws_file):
        try:
            with open(ws_file) as f:
                ws_dir = json.load(f).get('workspace_dir', '')
            if ws_dir and os.path.isdir(ws_dir):
                p = os.path.join(ws_dir, '.vscode', 'settings.json')
                if os.path.isfile(p):
                    with open(p) as f:
                        d = json.load(f)
                    b = d.get('terminal.integrated.env.linux', {}).get('BROWSER') or d.get('workbench.externalBrowser') or d.get('openInBrowser.default') or ''
                    if b: return b
        except Exception: pass
    return ''

print(find_bin())
" 2>/dev/null || true)

if [ -n "$PROJECT_BROWSER_BIN" ] && command -v "$PROJECT_BROWSER_BIN" >/dev/null 2>&1; then
  exec "$PROJECT_BROWSER_BIN" "$URL"
else
  FALLBACK=$(which brave-origin brave google-chrome-stable firefox 2>/dev/null | head -n 1)
  if [ -n "$FALLBACK" ]; then
    exec "$FALLBACK" "$URL"
  else
    exec /usr/bin/xdg-open "$URL"
  fi
fi
SMART_EOF
  chmod +x "$HOME/.local/bin/antigravity-smart-open"

  cat << 'DESKTOP_EOF' > "$HOME/.local/share/applications/antigravity-browser-opener.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Antigravity Smart Browser Router
Comment=Per-project browser router for Antigravity & VS Code
Exec=/home/mpi/.local/bin/antigravity-smart-open %u
Icon=internet-web-browser
Terminal=false
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
DESKTOP_EOF

  xdg-mime default antigravity-browser-opener.desktop x-scheme-handler/http 2>/dev/null || true
  xdg-mime default antigravity-browser-opener.desktop x-scheme-handler/https 2>/dev/null || true
}

# Install global smart wrappers into Antigravity IDE bin and ~/.local/bin to intercept IDE extension processes
install_global_smart_wrappers() {
  local target_dirs=("$HOME/.gemini/antigravity-ide/bin" "$HOME/.local/bin")
  for target_dir in "${target_dirs[@]}"; do
    mkdir -p "$target_dir"

    # 1. Global Smart sf wrapper
    cat << 'GLOBAL_SF_EOF' > "$target_dir/sf"
#!/bin/bash
REAL_SF=$(which -a sf 2>/dev/null | grep -v "antigravity-ide/bin/sf" | grep -v ".local/bin/sf" | grep -v "antigravity-wrappers" | head -n 1)
if [ -z "$REAL_SF" ] && [ -f "$HOME/.nvm/versions/node/v24.16.0/bin/sf" ]; then
  REAL_SF="$HOME/.nvm/versions/node/v24.16.0/bin/sf"
elif [ -z "$REAL_SF" ] && [ -f "/usr/local/bin/sf" ]; then
  REAL_SF="/usr/local/bin/sf"
fi

PROJECT_BROWSER=$(python3 -c "
import os, json

def find_browser():
    curr = os.getcwd()
    while curr and curr != '/':
        p = os.path.join(curr, '.vscode', 'settings.json')
        if os.path.isfile(p):
            try:
                with open(p) as f:
                    d = json.load(f)
                b = d.get('salesforcedx-vscode-core.preferredBrowser') or d.get('openInBrowser.default') or d.get('workbench.externalBrowser') or ''
                if b: return b
            except Exception: pass
        curr = os.path.dirname(curr)

    ws_file = os.path.expanduser('~/.config/antigravity-project-browser/active-workspace.json')
    if os.path.isfile(ws_file):
        try:
            with open(ws_file) as f:
                ws_dir = json.load(f).get('workspace_dir', '')
            if ws_dir and os.path.isdir(ws_dir):
                p = os.path.join(ws_dir, '.vscode', 'settings.json')
                if os.path.isfile(p):
                    with open(p) as f:
                        d = json.load(f)
                    b = d.get('salesforcedx-vscode-core.preferredBrowser') or d.get('openInBrowser.default') or d.get('workbench.externalBrowser') or ''
                    if b: return b
        except Exception: pass
    return ''

print(find_browser())
" 2>/dev/null || true)

if [ -n "$PROJECT_BROWSER" ]; then
  SF_FLAG="$PROJECT_BROWSER"
  case "$PROJECT_BROWSER" in
    firefox*|librewolf|waterfox|zen|*/firefox*) SF_FLAG="firefox" ;;
    edge*|msedge|*/msedge|*/microsoft-edge*) SF_FLAG="edge" ;;
    *) SF_FLAG="chrome" ;;
  esac

  has_browser=0
  for arg in "$@"; do
    if [[ "$arg" == "--browser" || "$arg" == "-b" || "$arg" == --browser=* ]]; then
      has_browser=1
      break
    fi
  done

  if [[ $has_browser -eq 0 ]]; then
    if [[ "$1" == "org" && ("$2" == "login" || "$2" == "open") ]]; then
      exec "$REAL_SF" "$@" --browser "$SF_FLAG"
    elif [[ "$1" == "force:auth:web:login" || "$1" == "auth:web:login" || "$1" == "force:org:open" || "$1" == "force:source:open" ]]; then
      exec "$REAL_SF" "$@" --browser "$SF_FLAG"
    fi
  fi
fi

if [ -n "$REAL_SF" ]; then
  exec "$REAL_SF" "$@"
else
  echo "sf binary not found on system PATH." >&2
  exit 127
fi
GLOBAL_SF_EOF
    chmod +x "$target_dir/sf"

    # 2. Global Smart xdg-open wrapper
    cat << 'GLOBAL_XDG_EOF' > "$target_dir/xdg-open"
#!/bin/bash
PROJECT_BROWSER_BIN=$(python3 -c "
import os, json

def find_bin():
    curr = os.getcwd()
    while curr and curr != '/':
        p = os.path.join(curr, '.vscode', 'settings.json')
        if os.path.isfile(p):
            try:
                with open(p) as f:
                    d = json.load(f)
                b = d.get('terminal.integrated.env.linux', {}).get('BROWSER') or d.get('workbench.externalBrowser') or d.get('openInBrowser.default') or ''
                if b: return b
            except Exception: pass
        curr = os.path.dirname(curr)

    ws_file = os.path.expanduser('~/.config/antigravity-project-browser/active-workspace.json')
    if os.path.isfile(ws_file):
        try:
            with open(ws_file) as f:
                ws_dir = json.load(f).get('workspace_dir', '')
            if ws_dir and os.path.isdir(ws_dir):
                p = os.path.join(ws_dir, '.vscode', 'settings.json')
                if os.path.isfile(p):
                    with open(p) as f:
                        d = json.load(f)
                    b = d.get('terminal.integrated.env.linux', {}).get('BROWSER') or d.get('workbench.externalBrowser') or d.get('openInBrowser.default') or ''
                    if b: return b
        except Exception: pass
    return ''

print(find_bin())
" 2>/dev/null || true)

if [ -n "$PROJECT_BROWSER_BIN" ] && command -v "$PROJECT_BROWSER_BIN" >/dev/null 2>&1; then
  exec "$PROJECT_BROWSER_BIN" "$@"
else
  exec /usr/bin/xdg-open "$@"
fi
GLOBAL_XDG_EOF
    chmod +x "$target_dir/xdg-open"

    # 3. Global Smart gio wrapper
    cat << 'GLOBAL_GIO_EOF' > "$target_dir/gio"
#!/bin/bash
if [ "$1" = "open" ]; then
  shift
  PROJECT_BROWSER_BIN=$(python3 -c "
import os, json

def find_bin():
    curr = os.getcwd()
    while curr and curr != '/':
        p = os.path.join(curr, '.vscode', 'settings.json')
        if os.path.isfile(p):
            try:
                with open(p) as f:
                    d = json.load(f)
                b = d.get('terminal.integrated.env.linux', {}).get('BROWSER') or d.get('workbench.externalBrowser') or d.get('openInBrowser.default') or ''
                if b: return b
            except Exception: pass
        curr = os.path.dirname(curr)

    ws_file = os.path.expanduser('~/.config/antigravity-project-browser/active-workspace.json')
    if os.path.isfile(ws_file):
        try:
            with open(ws_file) as f:
                ws_dir = json.load(f).get('workspace_dir', '')
            if ws_dir and os.path.isdir(ws_dir):
                p = os.path.join(ws_dir, '.vscode', 'settings.json')
                if os.path.isfile(p):
                    with open(p) as f:
                        d = json.load(f)
                    b = d.get('terminal.integrated.env.linux', {}).get('BROWSER') or d.get('workbench.externalBrowser') or d.get('openInBrowser.default') or ''
                    if b: return b
        except Exception: pass
    return ''

print(find_bin())
" 2>/dev/null || true)

  if [ -n "$PROJECT_BROWSER_BIN" ] && command -v "$PROJECT_BROWSER_BIN" >/dev/null 2>&1; then
    exec "$PROJECT_BROWSER_BIN" "$@"
  fi
fi
exec /usr/bin/gio "$@"
GLOBAL_GIO_EOF
    chmod +x "$target_dir/gio"

    # 4. Global Smart kde-open wrappers
    cp "$target_dir/xdg-open" "$target_dir/kde-open"
    cp "$target_dir/xdg-open" "$target_dir/kde-open5"
    cp "$target_dir/xdg-open" "$target_dir/sensible-browser"
    cp "$target_dir/xdg-open" "$target_dir/x-www-browser"
  done
}

# Scan system for installed browsers (Predefined list + Dynamic Desktop file auto-discovery)
scan_system_browsers() {
  python3 -c "
import os, glob, re, shutil, json

browsers_def = [
  ('Firefox', 'firefox', ['firefox']),
  ('Firefox Developer Edition', 'firefox-developer-edition', ['firefox-developer-edition', 'firefox-dev']),
  ('Firefox Nightly', 'firefox-nightly', ['firefox-nightly', 'firefox-trunk']),
  ('Google Chrome', 'chrome', ['google-chrome-stable', 'google-chrome', 'chrome']),
  ('Google Chrome Beta', 'chrome-beta', ['google-chrome-beta']),
  ('Google Chrome Dev', 'chrome-dev', ['google-chrome-unstable']),
  ('Chromium', 'chromium', ['chromium', 'chromium-browser']),
  ('Brave', 'brave', ['brave-browser', 'brave', 'brave-origin']),
  ('Microsoft Edge', 'edge', ['microsoft-edge-stable', 'microsoft-edge', 'msedge']),
  ('Microsoft Edge Dev', 'edge-dev', ['microsoft-edge-dev']),
  ('Helium Browser', 'helium', ['helium-browser', 'helium']),
  ('Vivaldi', 'vivaldi', ['vivaldi-stable', 'vivaldi']),
  ('Zen Browser', 'zen', ['zen-browser', 'zen']),
  ('LibreWolf', 'librewolf', ['librewolf']),
  ('Waterfox', 'waterfox', ['waterfox']),
  ('Thorium', 'thorium', ['thorium-browser', 'thorium']),
  ('Opera', 'opera', ['opera', 'opera-developer']),
  ('Tor Browser', 'tor-browser', ['torbrowser-launcher', 'tor-browser']),
  ('Falkon', 'falkon', ['falkon']),
  ('Epiphany (GNOME Web)', 'epiphany', ['epiphany']),
  ('Midori', 'midori', ['midori']),
  ('Qutebrowser', 'qutebrowser', ['qutebrowser'])
]

installed = []
seen_real_paths = set()

# 1. Look up predefined browser candidates
for name, slug, cands in browsers_def:
    for c in cands:
        bin_path = shutil.which(c)
        if bin_path:
            real_p = os.path.realpath(bin_path)
            if real_p not in seen_real_paths:
                seen_real_paths.add(real_p)
                installed.append({'name': name, 'slug': slug, 'bin': bin_path})
                break

# 2. Scan system desktop files for additional installed browsers
dt_files = glob.glob('/usr/share/applications/*.desktop') + glob.glob(os.path.expanduser('~/.local/share/applications/*.desktop'))
for dt in dt_files:
    if 'antigravity-browser-opener' in dt:
        continue
    try:
        with open(dt, 'r', errors='ignore') as f:
            content = f.read()
        if re.search(r'Categories=.*WebBrowser', content):
            name_m = re.search(r'^Name=(.+)$', content, re.MULTILINE)
            exec_m = re.search(r'^Exec=(.+)$', content, re.MULTILINE)
            if name_m and exec_m:
                name = name_m.group(1).strip()
                cmd = exec_m.group(1).strip().split()[0].replace('\"', '').replace(\"'\".encode().decode(), '')
                if cmd not in ['bash', 'sh', 'env', 'python', 'python3', 'antigravity-smart-open']:
                    bin_path = shutil.which(cmd)
                    if bin_path:
                        real_p = os.path.realpath(bin_path)
                        if real_p not in seen_real_paths:
                            seen_real_paths.add(real_p)
                            slug = os.path.basename(bin_path).lower().replace('-browser', '').replace('-stable', '')
                            installed.append({'name': f'{name} (Auto-discovered)', 'slug': slug, 'bin': bin_path})
    except Exception:
        pass

print(json.dumps(installed))
"
}

get_workspace_config() {
  python3 -c "
import os, json
curr = os.getcwd()
while curr and curr != '/':
    p = os.path.join(curr, '.vscode', 'settings.json')
    if os.path.isfile(p):
        try:
            with open(p, 'r') as f:
                data = json.load(f)
            browser = data.get('salesforcedx-vscode-core.preferredBrowser') or data.get('openInBrowser.default') or data.get('workbench.externalBrowser') or ''
            env_browser = data.get('terminal.integrated.env.linux', {}).get('BROWSER', '')
            path = data.get('terminal.integrated.env.linux', {}).get('PATH', '')
            if browser:
                print(f'{browser}|{env_browser}|{path}')
                break
        except Exception: pass
    curr = os.path.dirname(curr)
" 2>/dev/null || true
}

show_status() {
  print_banner
  echo -e "${BOLD}📂 Current Workspace Directory:${NC} $(pwd)"
  echo ""

  CFG=$(get_workspace_config || true)
  if [ -z "$CFG" ]; then
    echo -e "${YELLOW}${INFO} No project browser configured in this workspace (.vscode/settings.json).${NC}"
    echo -e "   Run ${BOLD}./setup-project-browser.sh${NC} to set one up."
    return 0
  fi

  IFS='|' read -r CONFIG_SLUG CONFIG_BIN CONFIG_PATH <<< "$CFG"
  WRAPPER_DIR="$WRAPPER_BASE_DIR/$CONFIG_SLUG"

  echo -e "${GREEN}${CHECK} Preferred Browser Setting:${NC} ${BOLD}$CONFIG_SLUG${NC}"
  echo -e "   Target Binary: $CONFIG_BIN"
  echo -e "   Wrapper Dir:   $WRAPPER_DIR"
  echo ""

  if [[ ":$PATH:" == *":$WRAPPER_DIR:"* ]]; then
    echo -e "${GREEN}${CHECK} Active Subshell PATH:${NC} Wrapper directory IS active in this terminal session."
  else
    echo -e "${YELLOW}⚠️  Active Subshell PATH:${NC} Wrapper directory is NOT yet active in this current terminal tab."
    echo -e "   ${BOLD}To activate in this terminal, run:${NC} ${GREEN}source .vscode/env.sh${NC}"
    echo -e "   ${DIM}(Or open a new terminal tab in Antigravity/VS Code)${NC}"
  fi
  echo ""
}

reset_workspace() {
  print_banner
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}${INFO} No .vscode/settings.json found in current directory to reset.${NC}"
    return 0
  fi

  python3 -c "
import json, os
file_path = '$SETTINGS_FILE'
try:
    with open(file_path, 'r') as f:
        data = json.load(f)
    data.pop('salesforcedx-vscode-core.preferredBrowser', None)
    data.pop('openInBrowser.default', None)
    data.pop('workbench.externalBrowser', None)
    if 'terminal.integrated.env.linux' in data:
        data['terminal.integrated.env.linux'].pop('BROWSER', None)
        p = data['terminal.integrated.env.linux'].get('PATH', '')
        parts = [item for item in p.split(':') if 'antigravity-wrappers' not in item]
        if parts:
            data['terminal.integrated.env.linux']['PATH'] = ':'.join(parts)
        else:
            data['terminal.integrated.env.linux'].pop('PATH', None)
        if not data['terminal.integrated.env.linux']:
            data.pop('terminal.integrated.env.linux')
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('SUCCESS')
except Exception as e:
    print('ERROR:', e)
"
  rm -f "$ENV_HELPER_FILE"
  echo -e "${GREEN}${CHECK} Workspace browser settings reset successfully.${NC}"
}

run_test() {
  CFG=$(get_workspace_config || true)
  if [ -z "$CFG" ]; then
    echo -e "${RED}${CROSS} Error: No browser configured for this project yet.${NC}"
    echo -e "   Please run ${BOLD}./setup-project-browser.sh${NC} first."
    return 1
  fi

  IFS='|' read -r CONFIG_SLUG CONFIG_BIN CONFIG_PATH <<< "$CFG"
  WRAPPER_DIR="$WRAPPER_BASE_DIR/$CONFIG_SLUG"
  TEST_URL="${1:-https://example.com}"

  echo -e "${CYAN}${TEST_ICON} Testing Link Open...${NC}"
  echo -e "   Configured Browser: ${BOLD}$CONFIG_SLUG${NC} ($CONFIG_BIN)"
  echo -e "   Wrapper Directory:  $WRAPPER_DIR"
  echo -e "   Target URL:         $TEST_URL"
  echo ""

  if [ -f "$WRAPPER_DIR/xdg-open" ]; then
    echo -e "${GREEN}${ROCKET} Executing wrapper xdg-open ($WRAPPER_DIR/xdg-open)...${NC}"
    "$WRAPPER_DIR/xdg-open" "$TEST_URL" >/dev/null 2>&1 &
    echo -e "${GREEN}${CHECK} Launched successfully! Check your $CONFIG_SLUG window.${NC}"
  else
    echo -e "${RED}${CROSS} Wrapper binary not found at $WRAPPER_DIR/xdg-open.${NC}"
  fi
}

# --- CLI Arguments Dispatcher ---
case "${1:-}" in
  --help|-h)
    show_help
    if [ "$IS_SOURCED" -eq 1 ]; then return 0; else exit 0; fi
    ;;
  --status|-s)
    show_status
    if [ "$IS_SOURCED" -eq 1 ]; then return 0; else exit 0; fi
    ;;
  --reset|-r)
    reset_workspace
    if [ "$IS_SOURCED" -eq 1 ]; then return 0; else exit 0; fi
    ;;
  --test|-t)
    run_test "${2:-https://example.com}"
    if [ "$IS_SOURCED" -eq 1 ]; then return 0; else exit 0; fi
    ;;
esac

print_banner

# --- Scan System for Installed Browsers ---
SYSTEM_BROWSERS_JSON=$(scan_system_browsers)

CHOSEN_INPUT="${1:-}"
SELECTED_NAME=""
SELECTED_SLUG=""
SELECTED_BIN=""

if [ -n "$CHOSEN_INPUT" ]; then
  CHOSEN_LOWER=$(echo "$CHOSEN_INPUT" | tr '[:upper:]' '[:lower:]')

  # Search scanner output first
  MATCH_INFO=$(CHOSEN_LOWER="$CHOSEN_LOWER" JSON="$SYSTEM_BROWSERS_JSON" python3 -c "
import os, json
data = json.loads(os.environ['JSON'])
chosen = os.environ['CHOSEN_LOWER']
for item in data:
    if chosen in [item['slug'].lower(), item['name'].lower(), os.path.basename(item['bin']).lower()]:
        print(f\"{item['name']}|{item['slug']}|{item['bin']}\")
        break
" 2>/dev/null || true)

  if [ -n "$MATCH_INFO" ]; then
    IFS='|' read -r SELECTED_NAME SELECTED_SLUG SELECTED_BIN <<< "$MATCH_INFO"
  else
    # Fallback: check if argument is executable command on PATH
    if command -v "$CHOSEN_INPUT" >/dev/null 2>&1; then
      SELECTED_BIN="$(command -v "$CHOSEN_INPUT")"
      SELECTED_SLUG="$(basename "$SELECTED_BIN" | tr '[:upper:]' '[:lower:]' | sed 's/-browser//; s/-stable//')"
      SELECTED_NAME="$CHOSEN_INPUT"
    else
      echo -e "${RED}${CROSS} Error: Could not find browser binary for '$CHOSEN_INPUT' on system PATH.${NC}"
      if [ "$IS_SOURCED" -eq 1 ]; then return 1; else exit 1; fi
    fi
  fi
else
  # Interactive Selection from System Scan
  echo -e "${BOLD}📂 Active Workspace Directory:${NC} $(pwd)"
  echo ""

  INSTALLED_COUNT=$(echo "$SYSTEM_BROWSERS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")

  if [ "$INSTALLED_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No web browsers detected automatically on system PATH.${NC}"
    read -rp "Please enter the binary name or full path of your browser: " CUSTOM_BIN
    if command -v "$CUSTOM_BIN" >/dev/null 2>&1; then
      SELECTED_BIN="$(command -v "$CUSTOM_BIN")"
      SELECTED_SLUG="$(basename "$SELECTED_BIN" | tr '[:upper:]' '[:lower:]' | sed 's/-browser//; s/-stable//')"
      SELECTED_NAME="$CUSTOM_BIN"
    else
      echo -e "${RED}${CROSS} Error: Invalid browser command '$CUSTOM_BIN'.${NC}"
      if [ "$IS_SOURCED" -eq 1 ]; then return 1; else exit 1; fi
    fi
  else
    echo -e "${CYAN}${GLOBE} Installed Web Browsers Detected on Your PC:${NC}"
    echo ""
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for i, item in enumerate(data):
    print(f\"  \033[1m{i+1})\033[0m \033[32m{item['name']}\033[0m \033[2m({item['bin']})\033[0m\")
" <<< "$SYSTEM_BROWSERS_JSON"
    echo ""
    read -rp "Enter choice [1-$INSTALLED_COUNT]: " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$INSTALLED_COUNT" ]; then
      INDEX=$((CHOICE - 1))
      MATCH_INFO=$(INDEX="$INDEX" JSON="$SYSTEM_BROWSERS_JSON" python3 -c "
import os, json
data = json.loads(os.environ['JSON'])
idx = int(os.environ['INDEX'])
item = data[idx]
print(f\"{item['name']}|{item['slug']}|{item['bin']}\")
")
      IFS='|' read -r SELECTED_NAME SELECTED_SLUG SELECTED_BIN <<< "$MATCH_INFO"
    else
      echo -e "${RED}${CROSS} Invalid selection. Aborting.${NC}"
      if [ "$IS_SOURCED" -eq 1 ]; then return 1; else exit 1; fi
    fi
  fi
fi

echo ""
echo -e "${BLUE}${GEAR} Configuring workspace for ${BOLD}$SELECTED_NAME${NC} (${SELECTED_BIN})..."

# Save active workspace directory for global smart wrappers fallback
mkdir -p "$HOME/.config/antigravity-project-browser"
python3 -c "
import json, os
ws_path = os.path.abspath('.')
with open(os.path.expanduser('~/.config/antigravity-project-browser/active-workspace.json'), 'w') as f:
    json.dump({'workspace_dir': ws_path}, f, indent=2)
"

# Install global smart wrappers into ~/.gemini/antigravity-ide/bin & ~/.local/bin
install_global_smart_wrappers

# Install system-wide XDG URL desktop handler for Electron / VS Code openExternal API
install_desktop_url_handler

WRAPPER_DIR="$WRAPPER_BASE_DIR/$SELECTED_SLUG"
mkdir -p "$WRAPPER_DIR"

# Determine Salesforce CLI --browser flag compatibility
SF_BROWSER_FLAG="$SELECTED_SLUG"
case "$SELECTED_SLUG" in
  firefox*|librewolf|waterfox|zen) SF_BROWSER_FLAG="firefox" ;;
  edge*|msedge) SF_BROWSER_FLAG="edge" ;;
  *) SF_BROWSER_FLAG="chrome" ;;
esac

# 1. Create sf wrapper
cat << SF_EOF > "$WRAPPER_DIR/sf"
#!/bin/bash
WRAPPER_BASE="$WRAPPER_BASE_DIR"
REAL_SF="\$(which -a sf 2>/dev/null | grep -v "antigravity-ide/bin/sf" | grep -v ".local/bin/sf" | grep -v "\$WRAPPER_BASE" | head -n 1)"

if [ -z "\$REAL_SF" ] && [ -f "\$HOME/.nvm/versions/node/v24.16.0/bin/sf" ]; then
  REAL_SF="\$HOME/.nvm/versions/node/v24.16.0/bin/sf"
elif [ -z "\$REAL_SF" ] && [ -f "/usr/local/bin/sf" ]; then
  REAL_SF="/usr/local/bin/sf"
fi

has_browser=0
for arg in "\$@"; do
  if [[ "\$arg" == "--browser" || "\$arg" == "-b" || "\$arg" == --browser=* ]]; then
    has_browser=1
    break
  fi
done

if [[ \$has_browser -eq 0 ]]; then
  if [[ "\$1" == "org" && ("\$2" == "login" || "\$2" == "open") ]]; then
    exec "\$REAL_SF" "\$@" --browser "$SF_BROWSER_FLAG"
  elif [[ "\$1" == "force:auth:web:login" || "\$1" == "auth:web:login" || "\$1" == "force:org:open" || "\$1" == "force:source:open" ]]; then
    exec "\$REAL_SF" "\$@" --browser "$SF_BROWSER_FLAG"
  fi
fi

if [ -n "\$REAL_SF" ]; then
  exec "\$REAL_SF" "\$@"
else
  echo "sf binary not found on system PATH." >&2
  exit 127
fi
SF_EOF
chmod +x "$WRAPPER_DIR/sf"

# 2. Create xdg-open wrapper
cat << XDG_EOF > "$WRAPPER_DIR/xdg-open"
#!/bin/bash
exec "$SELECTED_BIN" "\$@"
XDG_EOF
chmod +x "$WRAPPER_DIR/xdg-open"

# 3. Create gio wrapper
cat << GIO_EOF > "$WRAPPER_DIR/gio"
#!/bin/bash
if [ "\$1" = "open" ]; then
  shift
  exec "$SELECTED_BIN" "\$@"
else
  exec /usr/bin/gio "\$@"
fi
GIO_EOF
chmod +x "$WRAPPER_DIR/gio"

# 4. Create kde-open, kde-open5, sensible-browser, x-www-browser wrappers
cat << KDE_EOF > "$WRAPPER_DIR/kde-open"
#!/bin/bash
exec "$SELECTED_BIN" "\$@"
KDE_EOF
chmod +x "$WRAPPER_DIR/kde-open"
cp "$WRAPPER_DIR/kde-open" "$WRAPPER_DIR/kde-open5"
cp "$WRAPPER_DIR/kde-open" "$WRAPPER_DIR/sensible-browser"
cp "$WRAPPER_DIR/kde-open" "$WRAPPER_DIR/x-www-browser"

# 5. Configure local project .vscode/settings.json
mkdir -p "$VSCODE_DIR"

BROWSER_BIN="$SELECTED_BIN" \
BROWSER_SLUG="$SELECTED_SLUG" \
SF_BROWSER_FLAG="$SF_BROWSER_FLAG" \
python3 -c "
import os, json

file_path = './.vscode/settings.json'
browser_bin = os.environ['BROWSER_BIN']
browser_slug = os.environ['BROWSER_SLUG']
sf_flag = os.environ['SF_BROWSER_FLAG']

os.makedirs(os.path.dirname(file_path), exist_ok=True)
data = {}
if os.path.exists(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except Exception:
        data = {}

env_linux = data.get('terminal.integrated.env.linux', {})
if not isinstance(env_linux, dict):
    env_linux = {}

wrapper_path = '\${env:HOME}/.local/share/antigravity-wrappers/' + browser_slug
env_linux['BROWSER'] = browser_bin
env_linux['PATH'] = wrapper_path + ':\${env:PATH}'

data['terminal.integrated.env.linux'] = env_linux
data['workbench.externalBrowser'] = browser_bin
data['salesforcedx-vscode-core.preferredBrowser'] = sf_flag
data['openInBrowser.default'] = browser_bin

with open(file_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

# 6. Configure local project .vscode/tasks.json
BROWSER_BIN="$SELECTED_BIN" \
BROWSER_NAME="$SELECTED_NAME" \
python3 -c "
import os, json

tasks_file = './.vscode/tasks.json'
browser_bin = os.environ['BROWSER_BIN']
browser_name = os.environ['BROWSER_NAME']

os.makedirs(os.path.dirname(tasks_file), exist_ok=True)
tasks_data = {}
if os.path.exists(tasks_file):
    try:
        with open(tasks_file, 'r') as f:
            tasks_data = json.load(f)
    except Exception:
        tasks_data = {}

if 'version' not in tasks_data:
    tasks_data['version'] = '2.0.0'
if 'tasks' not in tasks_data or not isinstance(tasks_data['tasks'], list):
    tasks_data['tasks'] = []

task_label = f'Open URL in {browser_name}'
task_found = False
for t in tasks_data['tasks']:
    if isinstance(t, dict) and t.get('label') == task_label:
        t['command'] = f'{browser_bin} \${{input:url}}'
        task_found = True
        break

if not task_found:
    tasks_data['tasks'].append({
        'label': task_label,
        'type': 'shell',
        'command': f'{browser_bin} \${{input:url}}',
        'problemMatcher': []
    })

if 'inputs' not in tasks_data or not isinstance(tasks_data['inputs'], list):
    tasks_data['inputs'] = []

input_found = False
for inp in tasks_data['inputs']:
    if isinstance(inp, dict) and inp.get('id') == 'url':
        input_found = True
        break

if not input_found:
    tasks_data['inputs'].append({
        'id': 'url',
        'type': 'promptString',
        'description': f'URL to open in {browser_name}',
        'default': 'https://test.salesforce.com'
    })

with open(tasks_file, 'w') as f:
    json.dump(tasks_data, f, indent=2)
    f.write('\n')
"

# 7. Generate .vscode/env.sh helper for quick sourcing
cat << ENV_EOF > "$ENV_HELPER_FILE"
# Source this file to activate the project browser in your current shell session:
export PATH="$WRAPPER_DIR:\$PATH"
export BROWSER="$SELECTED_BIN"
ENV_EOF
chmod +x "$ENV_HELPER_FILE"

# If script is being sourced, export to current shell immediately!
if [ "$IS_SOURCED" -eq 1 ]; then
  export PATH="$WRAPPER_DIR:$PATH"
  export BROWSER="$SELECTED_BIN"
fi

echo -e "${GREEN}${BOLD}${CHECK} Configuration Completed Successfully!${NC}"
echo -e "   ${BOLD}Browser:${NC}     $SELECTED_NAME ($SELECTED_BIN)"
echo -e "   ${BOLD}Wrappers:${NC}    $WRAPPER_DIR & ~/.local/bin/ (Global Smart Interceptor Installed)"
echo -e "   ${BOLD}Settings:${NC}    $SETTINGS_FILE (Added workbench.externalBrowser)"
echo -e "   ${BOLD}Env Script:${NC}  $ENV_HELPER_FILE"
echo ""

echo -e "${CYAN}${BOLD}📋 HOW TO USE IN YOUR TERMINAL & VS CODE EXTENSIONS:${NC}"
if [ "$IS_SOURCED" -eq 1 ]; then
  echo -e "  ${GREEN}${CHECK} Current shell activated!${NC} PATH and BROWSER environment variables updated immediately."
else
  echo -e "  1. ${BOLD}In THIS current terminal tab right now:${NC}"
  echo -e "     Run: ${GREEN}source .vscode/env.sh${NC}"
  echo -e "     ${DIM}(Bash subshells cannot mutate an existing terminal's PATH automatically without sourcing)${NC}"
  echo ""
  echo -e "  2. ${BOLD}In IDE Extensions (Salesforce DX, etc.) & New Terminal Tabs:${NC}"
  echo -e "     All commands (e.g. Salesforce extension UI buttons, ${DIM}sf org open${NC}, ${DIM}xdg-open${NC}, Ctrl+Click links) will launch in ${BOLD}$SELECTED_NAME${NC}."
fi
echo ""

# Test Link Output
echo -e "${MAGENTA}${BOLD}----------------------------------------------------------------------${NC}"
echo -e "${TEST_ICON} ${BOLD}TEST YOUR BROWSER SETUP NOW:${NC}"
echo -e "   Click or Ctrl+Click this link directly in this terminal to test opening in ${BOLD}$SELECTED_NAME${NC}:"
echo -e "   👉 ${CYAN}${BOLD}https://example.com${NC}"
echo ""
echo -e "   Or run this CLI command (after running ${GREEN}source .vscode/env.sh${NC} or in a new terminal tab):"
echo -e "   ${GREEN}xdg-open https://example.com${NC}"
echo -e "${MAGENTA}${BOLD}----------------------------------------------------------------------${NC}"

echo ""
echo -e "${GREEN}✨ Done! Happy coding!${NC}"
