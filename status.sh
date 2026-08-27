#!/bin/zsh
set -euo pipefail

LABEL="app.namedrop.agent"
LOG_DIR="$HOME/Library/Logs/NameDrop"

if ! job=$(launchctl print "gui/$(id -u)/$LABEL" 2>&1); then
  echo "Status: stopped"
  echo "Run ./install-macos.sh to install or restart it."
  exit 1
fi

state=$(print -r -- "$job" | awk '/state =/ {print $3; exit}')
pid=$(print -r -- "$job" | awk '/pid =/ {print $3; exit}')
echo "Status: $state"
if [[ -n "$pid" ]]; then
  echo "Host PID: $pid"
  ps -o %cpu=,%mem=,rss=,etime= -p "$pid" | awk '{printf "Host usage: %s%% CPU, %s%% memory, %.1f MB RAM, uptime %s\n", $1, $2, $3/1024, $4}'
  worker=$(pgrep -P "$pid" | head -1 || true)
  if [[ -n "$worker" ]]; then
    ps -o %cpu=,%mem=,rss=,etime= -p "$worker" | awk '{printf "Worker usage: %s%% CPU, %s%% memory, %.1f MB RAM, uptime %s\n", $1, $2, $3/1024, $4}'
  fi
fi

if [[ -s "$LOG_DIR/helper-error.log" ]]; then
  echo "Recent errors:"
  tail -n 5 "$LOG_DIR/helper-error.log"
fi
