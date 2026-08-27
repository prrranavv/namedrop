#!/bin/zsh
set -euo pipefail

LABEL="app.namedrop.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Applications/NameDrop.app"
TRASH_STAMP="$(date +%s)"

domain="gui/$(id -u)"
host_pid="$(launchctl print "$domain/$LABEL" 2>/dev/null | awk '/^[[:space:]]*pid =/ {print $3; exit}' || true)"
worker_pids=""
if [[ -n "$host_pid" ]]; then
  worker_pids="$(pgrep -P "$host_pid" || true)"
fi

launchctl bootout "$domain/$LABEL" 2>/dev/null || true
if [[ -n "$worker_pids" ]]; then
  while IFS= read -r worker_pid; do
    [[ -n "$worker_pid" ]] && kill "$worker_pid" 2>/dev/null || true
  done <<< "$worker_pids"
fi

if [[ -f "$PLIST_PATH" ]]; then
  mv "$PLIST_PATH" "$HOME/.Trash/$LABEL.plist.$TRASH_STAMP"
fi
if [[ -d "$APP_DIR" ]]; then
  mv "$APP_DIR" "$HOME/.Trash/NameDrop.app.$TRASH_STAMP"
fi
echo "Watcher stopped; the app and LaunchAgent were moved to Trash. Rename history was preserved."
