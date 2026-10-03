# Shared paths for the Oniro (Linux) workflow. Override any of them via the environment.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HDC="${HDC:-$HOME/setup-ohos-sdk/linux/23/toolchains/hdc}"
ONIRO_IMAGES="${ONIRO_IMAGES:-$HOME/oniro/images}"
STATE_DIR="$REPO/.cache/oniro"
HAP="$REPO/entry/build/default/outputs/default/entry-default-signed.hap"
