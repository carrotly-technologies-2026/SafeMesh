#!/usr/bin/env bash
# Build the OpenHarmony ("oniro" product) HAP, install it on the emulator and launch it.
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$REPO"
[[ -f signatures/OpenHarmony.p12 && -f signatures/app1-profile.p7b ]] || "$(dirname "$0")/sign.sh"
"$HDC" tconn 127.0.0.1:55555 >/dev/null
oniro-app build --product oniro
"$HDC" install -r "$HAP"
"$HDC" shell aa start -b org.safemesh.alerts -a EntryAbility
