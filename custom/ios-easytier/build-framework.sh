#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/mobile/ios/EasyTierCore/Frameworks/ImmichEasyTier.xcframework"
cd "$ROOT/custom/ios-easytier/core"
export IPHONEOS_DEPLOYMENT_TARGET=18.1
python3 ../test-config-contract.py
python3 ../patch-tcp-policy.py
cargo fmt --all
cargo test --locked --lib
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --locked --release --target "$target"
done
mkdir -p target/universal-simulator
lipo -create target/aarch64-apple-ios-sim/release/libimmich_easytier.a \
  target/x86_64-apple-ios/release/libimmich_easytier.a \
  -output target/universal-simulator/libimmich_easytier.a
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libimmich_easytier.a -headers ../include \
  -library target/universal-simulator/libimmich_easytier.a -headers ../include \
  -output "$OUT"
