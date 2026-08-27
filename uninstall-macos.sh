#!/bin/zsh
set -euo pipefail

LABEL="app.namedrop.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Applications/NameDrop.app"
TRASH_STAMP="$(date +%s)"

descendant_pids() {
  local parent_pid="$1"
  local child_pid=""

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    descendant_pids "$child_pid"
    print -r -- "$child_pid"
  done < <(pgrep -P "$parent_pid" || true)
}

domain="gui/$(id -u)"
host_pid="$(launchctl print "$domain/$LABEL" 2>/dev/null | awk '/^[[:space:]]*pid =/ {print $3; exit}' || true)"
process_pids=""
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

if [[ -f "$PLIST_PATH" ]]; then
  mv "$PLIST_PATH" "$HOME/.Trash/$LABEL.plist.$TRASH_STAMP"
fi
if [[ -d "$APP_DIR" ]]; then
  mv "$APP_DIR" "$HOME/.Trash/NameDrop.app.$TRASH_STAMP"
fi
echo "Watcher stopped; the app and LaunchAgent were moved to Trash. Rename history was preserved."
