#!/usr/bin/env bash
# Prepare OpenHarmony debug signing for the "oniro" product from the public SDK keystore.
# Unlike `oniro-app sign`, this never rewrites build-profile.json5, so the HarmonyOS product stays unsigned.
set -euo pipefail
source "$(dirname "$0")/common.sh"
LIB="$OHOS_SDK/toolchains/lib"
SIG="$REPO/signatures"
cp "$LIB/OpenHarmony.p12" "$SIG/OpenHarmony.p12"
java -jar "$LIB/hap-sign-tool.jar" sign-profile \
  -keyAlias "openharmony application profile release" -signAlg SHA256withECDSA -mode localSign \
  -profileCertFile "$SIG/OpenHarmonyProfileRelease.pem" -inFile "$SIG/UnsgnedReleasedProfileTemplate.json" \
  -keystoreFile "$SIG/OpenHarmony.p12" -outFile "$SIG/app1-profile.p7b" -keyPwd 123456 -keystorePwd 123456
echo "Signing material ready in $SIG (OpenHarmony.p12 and app1-profile.p7b are git-ignored)."
