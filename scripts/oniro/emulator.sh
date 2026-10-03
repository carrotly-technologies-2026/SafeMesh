#!/usr/bin/env bash
# Start the Oniro emulator headless. View it with a VNC client at 127.0.0.1:5900.
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$ONIRO_IMAGES"
exec ./run.sh --headless "$@"
