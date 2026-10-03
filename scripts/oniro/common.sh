# Shared paths for the Oniro (Linux) workflow. Override any of them via the environment.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OHOS_SDK="${OHOS_SDK:-$HOME/setup-ohos-sdk/linux/23}"
HDC="${HDC:-$OHOS_SDK/toolchains/hdc}"
ONIRO_IMAGES="${ONIRO_IMAGES:-$HOME/oniro/images}"
STATE_DIR="$REPO/.cache/oniro"
# The "oniro" product builds the "oniro" target (NearLink stub, OpenHarmony API 23).
HAP="$REPO/entry/build/oniro/outputs/oniro/entry-oniro-signed.hap"
