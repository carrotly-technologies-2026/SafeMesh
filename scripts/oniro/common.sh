# Shared paths for the Oniro (Linux) workflow. Override any of them via the environment.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OHOS_SDK="${OHOS_SDK:-$HOME/setup-ohos-sdk/linux/23}"
HDC="${HDC:-$OHOS_SDK/toolchains/hdc}"
ONIRO_IMAGES="${ONIRO_IMAGES:-$HOME/oniro/images}"
STATE_DIR="$REPO/.cache/oniro"
# The "oniro" product builds the "oniro" target (NearLink stub, OpenHarmony API 23).
HAP="$REPO/entry/build/oniro/outputs/oniro/entry-oniro-signed.hap"

# Emulator instances for the three-node mesh: A uses the original image folder, B and C get their own copies.
ONIRO_ZIP="${ONIRO_ZIP:-$(dirname "$ONIRO_IMAGES")/oniro_emulator.zip}"
NODES=(A B C)
node_index() { case "$1" in A) echo 0 ;; B) echo 1 ;; C) echo 2 ;; *) echo "Unknown node '$1' (use A, B or C)" >&2; return 1 ;; esac; }
node_dir() { [[ "$1" == A ]] && echo "$ONIRO_IMAGES" || echo "$(dirname "$ONIRO_IMAGES")/instance-$1"; }
node_target() { echo "127.0.0.1:$((55555 + $(node_index "$1")))"; }
# The app connects to 127.0.0.1:8765 (A), 8766 (B) or 8767 (C) inside its emulator; all map to the hub's 8765.
node_hub_port() { echo $((8765 + $(node_index "$1"))); }
# True when the node's emulator answers hdc (tconn prints different messages for new and existing connections).
node_online() {
  "$HDC" tconn "$(node_target "$1")" >/dev/null 2>&1 || true
  "$HDC" list targets 2>/dev/null | grep -qx "$(node_target "$1")"
}
