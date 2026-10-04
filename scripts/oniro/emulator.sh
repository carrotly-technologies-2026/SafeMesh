#!/usr/bin/env bash
# Start one Oniro emulator headless. Usage: emulator.sh [A|B|C] (default A)
#   A: hdc 127.0.0.1:55555, VNC 127.0.0.1:5900   (original image folder)
#   B: hdc 127.0.0.1:55556, VNC 127.0.0.1:5901   (~/oniro/instance-B)
#   C: hdc 127.0.0.1:55557, VNC 127.0.0.1:5902   (~/oniro/instance-C)
set -euo pipefail
source "$(dirname "$0")/common.sh"
node="${1:-A}"
index="$(node_index "$node")"
dir="$(node_dir "$node")"

if [[ ! -d "$dir" ]]; then
  echo "Creating emulator $node in $dir..."
  mkdir -p "$dir"
  # Read-only images are shared copy-on-write (instant on btrfs/xfs); userdata starts fresh from the zip.
  for f in bzImage ramdisk.img updater.img system.img vendor.img; do
    cp --reflink=auto "$ONIRO_IMAGES/$f" "$dir/$f"
  done
  unzip -j -o "$ONIRO_ZIP" images/userdata.img -d "$dir"
fi

exec "$ONIRO_IMAGES/run.sh" --headless --connect "$(node_target "$node")" \
  --vnc-display "$index" --serial-port $((4444 + index)) --smp 4 "$dir" "${@:2}"
