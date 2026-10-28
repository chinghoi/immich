#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/EmbeddedNetworkCore" "$WORK/Tests/EmbeddedNetworkCoreTests"
cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EmbeddedNetworkCore", platforms: [.macOS(.v13)],
  targets: [.target(name: "EmbeddedNetworkCore"), .testTarget(name: "EmbeddedNetworkCoreTests", dependencies: ["EmbeddedNetworkCore"])])
SWIFT
cp "$ROOT/mobile/ios/Tailnet/Sources/EmbeddedNetworkController.swift" "$WORK/Sources/EmbeddedNetworkCore/"
cp "$ROOT/custom/ios-easytier/tests/ProviderStubs.swift" "$WORK/Sources/EmbeddedNetworkCore/"
cp "$ROOT/custom/ios-easytier/tests/SelectorTests.swift" "$WORK/Tests/EmbeddedNetworkCoreTests/"
cd "$WORK"
swift test
