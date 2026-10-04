#!/usr/bin/env bash
# Build the OpenHarmony ("oniro" product) HAP, then install and launch it on every running emulator (A, B, C).
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$REPO"
[[ -f signatures/OpenHarmony.p12 && -f signatures/app1-profile.p7b ]] || "$(dirname "$0")/sign.sh"
oniro-app build --product oniro
for node in "${NODES[@]}"; do
  target="$(node_target "$node")"
  if ! node_online "$node"; then
    echo "Emulator $node ($target) is not running, skipped."; continue
  fi
  echo "Emulator $node ($target):"
  "$HDC" -t "$target" install -r "$HAP"
  "$HDC" -t "$target" shell aa start -b org.safemesh.alerts -a EntryAbility
done
