#!/usr/bin/env bash
# Start or stop the mesh hub (8765) and exercise authority (8768), and forward both ports into the emulator.
# Usage: services.sh start|stop|status
set -euo pipefail
source "$(dirname "$0")/common.sh"
mkdir -p "$STATE_DIR"

start_one() {
  local name="$1" script="$2"
  if [[ -f "$STATE_DIR/$name.pid" ]] && kill -0 "$(cat "$STATE_DIR/$name.pid")" 2>/dev/null; then
    echo "$name already running (pid $(cat "$STATE_DIR/$name.pid"))"; return
  fi
  nohup node "$REPO/scripts/$script" >>"$STATE_DIR/$name.log" 2>&1 &
  echo $! >"$STATE_DIR/$name.pid"
  echo "$name started (pid $!, log $STATE_DIR/$name.log)"
}

stop_one() {
  local name="$1"
  if [[ -f "$STATE_DIR/$name.pid" ]]; then
    kill "$(cat "$STATE_DIR/$name.pid")" 2>/dev/null && echo "$name stopped" || echo "$name was not running"
    rm -f "$STATE_DIR/$name.pid"
  fi
}

case "${1:-}" in
  start)
    start_one hub mesh-lab-server.mjs
    start_one authority demo-authority-server.mjs
    sleep 1
    "$HDC" tconn 127.0.0.1:55555 >/dev/null
    for port in 8765 8768; do
      "$HDC" fport ls | grep -q "tcp:$port tcp:$port" || "$HDC" rport "tcp:$port" "tcp:$port"
    done
    ;;
  stop)
    stop_one hub
    stop_one authority
    ;;
  status)
    ss -ltn | grep -E ':(8765|8768)\b' || echo "no services listening"
    "$HDC" fport ls
    ;;
  *) echo "Usage: $0 start|stop|status" >&2; exit 1 ;;
esac
