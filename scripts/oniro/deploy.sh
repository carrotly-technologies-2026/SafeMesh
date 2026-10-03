#!/usr/bin/env bash
# Build the OpenHarmony HAP, install it on the emulator and launch it.
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$REPO"
"$HDC" tconn 127.0.0.1:55555 >/dev/null
oniro-app build
"$HDC" install -r "$HAP"
"$HDC" shell aa start -b org.safemesh.alerts -a EntryAbility
