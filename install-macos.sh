#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
LABEL="app.namedrop.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/NameDrop"
STATE_DIR="$HOME/Library/Application Support/NameDrop"
VENV_DIR="$STATE_DIR/venv"
APP_DIR="$HOME/Applications/NameDrop.app"
APP_BINARY="$APP_DIR/Contents/MacOS/NameDrop"
SIGNING_IDENTITY="${NAMEDROP_SIGNING_IDENTITY:--}"

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"NameDrop Local Code Signing"'; then
  SIGNING_IDENTITY="NameDrop Local Code Signing"
fi

descendant_pids() {
  local parent_pid="$1"
  local child_pid=""

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    descendant_pids "$child_pid"
    print -r -- "$child_pid"
  done < <(pgrep -P "$parent_pid" || true)
}

stop_existing_job() {
  local domain="gui/$(id -u)"
  local host_pid=""
  local process_pids=""
  local process_pid=""

  host_pid="$(launchctl print "$domain/$LABEL" 2>/dev/null | awk '/^[[:space:]]*pid =/ {print $3; exit}' || true)"
  if [[ -n "$host_pid" ]]; then
    process_pids="$(descendant_pids "$host_pid")"
  fi

  launchctl bootout "$domain/$LABEL" 2>/dev/null || true

  if [[ -n "$process_pids" ]]; then
    while IFS= read -r process_pid; do
      [[ -n "$process_pid" ]] && kill "$process_pid" 2>/dev/null || true
    done <<< "$process_pids"
  fi
  [[ -n "$host_pid" ]] && kill "$host_pid" 2>/dev/null || true

  sleep 0.2
  if [[ -n "$process_pids" ]]; then
    while IFS= read -r process_pid; do
      [[ -n "$process_pid" ]] && kill -9 "$process_pid" 2>/dev/null || true
    done <<< "$process_pids"
  fi
  [[ -n "$host_pid" ]] && kill -9 "$host_pid" 2>/dev/null || true
}

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "NameDrop requires an Apple-silicon Mac." >&2
  exit 1
fi

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( os_major < 26 )); then
  echo "NameDrop requires macOS 26 or newer." >&2
  exit 1
fi

command -v xcrun >/dev/null || {
  echo "Install Apple's Command Line Tools first: xcode-select --install" >&2
  exit 1
}

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents" "$PROJECT_DIR/bin" \
  "$STATE_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin"

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python3" -m pip install --quiet --disable-pip-version-check -r "$PROJECT_DIR/requirements.txt"

xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  "$PROJECT_DIR/helper/namer.swift" \
  -o "$PROJECT_DIR/bin/namedrop-namer"

xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  "$PROJECT_DIR/helper/toast.swift" \
  -o "$PROJECT_DIR/bin/namedrop-toast"

xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
  "$PROJECT_DIR/helper/host.swift" \
  -o "$APP_BINARY"

cp "$PROJECT_DIR/helper/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/renamer.py" "$APP_DIR/Contents/Resources/renamer.py"
cp "$PROJECT_DIR/bin/namedrop-namer" "$APP_DIR/Contents/Resources/bin/namedrop-namer"
cp "$PROJECT_DIR/bin/namedrop-toast" "$APP_DIR/Contents/Resources/bin/namedrop-toast"
cp "$PROJECT_DIR/assets/NameDrop.icns" "$APP_DIR/Contents/Resources/NameDrop.icns"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"

sed \
  -e "s|__APP_BINARY__|$APP_BINARY|g" \
  -e "s|__LOG_DIR__|$LOG_DIR|g" \
  "$PROJECT_DIR/launchd/$LABEL.plist.template" > "$PLIST_PATH"

stop_existing_job
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "NameDrop is installed and running."
echo "New supported files in $HOME/Downloads will be renamed automatically."
echo "Run ./status.sh to inspect the watcher."
