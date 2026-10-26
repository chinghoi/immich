#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
commit=$(python3 -c 'import json; print(json.load(open("custom/ios-tailnet/dependencies.json"))["libtailscaleCommit"])')
source_dir="$root/.tailnet-build/libtailscale"
mkdir -p "$root/.tailnet-build"
if [[ ! -d "$source_dir/.git" ]]; then
  git init "$source_dir"
  git -C "$source_dir" remote add origin https://github.com/tailscale/libtailscale.git
fi
git -C "$source_dir" fetch --depth=1 origin "$commit"
git -C "$source_dir" checkout --detach FETCH_HEAD
test "$(git -C "$source_dir" rev-parse HEAD)" = "$commit"
logging_patch="$root/custom/ios-tailnet/patches/libtailscale-logging.patch"
if ! (cd "$source_dir" && patch --batch -p1 --reverse --dry-run -i "$logging_patch") >/dev/null 2>&1; then
  (cd "$source_dir" && patch --batch -p1 --forward -i "$logging_patch")
fi
# Upstream pipes xcodebuild to a prettifier without pipefail. Propagate failures.
make -C "$source_dir/swift" SHELL=/bin/bash '.SHELLFLAGS=-eu -o pipefail -c' ios-fat
mkdir -p "$root/mobile/ios/Tailnet/Frameworks"
ditto "$source_dir/swift/build/Build/Products/Release-iphonefat/TailscaleKit.xcframework" \
  "$root/mobile/ios/Tailnet/Frameworks/TailscaleKit.xcframework"
cp "$source_dir/LICENSE" "$root/mobile/ios/Tailnet/Frameworks/LICENSE-libtailscale.txt"
