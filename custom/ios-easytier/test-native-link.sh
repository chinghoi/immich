#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/main.c" <<'C'
#include <stddef.h>
#include "ImmichEasyTier.h"
int main(void) {
  if (immich_et_start(NULL) != -1 || immich_et_stop() != 0) return 1;
  char *status = immich_et_status("");
  if (status == NULL) return 2;
  immich_et_free(status);
  return 0;
}
C
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
LIB="$ROOT/mobile/ios/EasyTierCore/Frameworks/ImmichEasyTier.xcframework/ios-arm64_x86_64-simulator/libimmich_easytier.a"
# Catch missing exports and native link dependencies BEFORE the full app build.
for arch in arm64 x86_64; do
  xcrun clang -target "$arch-apple-ios18.1-simulator" -isysroot "$SDK" \
    -I "$ROOT/custom/ios-easytier/include" "$WORK/main.c" "$LIB" \
    -framework Security -framework SystemConfiguration -framework CoreFoundation \
    -framework Foundation -lc++ -lresolv -liconv -o "$WORK/abi-$arch"
done
