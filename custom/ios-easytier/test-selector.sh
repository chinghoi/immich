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
cp "$ROOT/mobile/ios/Tailnet/Sources/EasyTierNodeList.swift" "$WORK/Sources/EmbeddedNetworkCore/"
cp "$ROOT/custom/ios-easytier/tests/NodeListTests.swift" "$WORK/Tests/EmbeddedNetworkCoreTests/"
cp "$ROOT/custom/ios-easytier/tests/SelectorTests.swift" "$WORK/Tests/EmbeddedNetworkCoreTests/"
cp "$ROOT/mobile/ios/Tailnet/Sources/EmbeddedLocalRoute.swift" "$WORK/Sources/EmbeddedNetworkCore/"
python3 - "$ROOT" "$WORK" <<'PY'
import pathlib,sys
root,work=map(pathlib.Path,sys.argv[1:])
source=(root/'mobile/ios/Runner/Core/URLSessionManager.swift').read_text()
source=source.replace('import native_video_player','import Security').replace('import ImmichTailnet','import ObjectiveC')
source=source.replace('Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as! String','"network-session-fixture"')
(work/'Sources/EmbeddedNetworkCore/URLSessionManager.swift').write_text(source)
PY
cp "$ROOT/custom/ios-easytier/tests/SessionLifetimeTests.swift" "$WORK/Tests/EmbeddedNetworkCoreTests/"
cd "$WORK"
swift test
