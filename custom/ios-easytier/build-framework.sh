#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/mobile/ios/Tailnet/Frameworks/ImmichEasyTier.xcframework"
cd "$ROOT/custom/ios-easytier/core"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
export IPHONEOS_DEPLOYMENT_TARGET=18.1
cargo test --lib
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  cargo build --release --target "$target"
done
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libimmich_easytier.a -headers ../include \
  -library target/aarch64-apple-ios-sim/release/libimmich_easytier.a -headers ../include \
  -output "$OUT"
