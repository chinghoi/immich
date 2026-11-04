#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
output="$root/mobile/build/tailnet-distribution"
mkdir -p "$output/Payload"
device_app=$(find "$root/mobile/build/ios/iphoneos" -maxdepth 1 -name '*.app' -print -quit)
simulator_app=$(find "$root/mobile/build/ios/iphonesimulator" -maxdepth 1 -name '*.app' -print -quit)
test -n "$device_app" && test -n "$simulator_app"
ditto "$device_app" "$output/Payload/$(basename "$device_app")"
ditto -c -k --keepParent "$output/Payload" "$output/Immich-Tailnet-UNSIGNED.ipa"
ditto -c -k --keepParent "$simulator_app" "$output/Immich-Tailnet-SIMULATOR.zip"
python3 - "$output" <<'PY'
import hashlib,json,os,pathlib,subprocess,sys
metadata=json.load(open('custom/ios-tailnet/dependencies.json'))
metadata['easyTier']=json.load(open('custom/ios-easytier/dependencies.json'))
metadata['easyTier']['cargoLockSHA256']=hashlib.sha256(pathlib.Path('custom/ios-easytier/core/Cargo.lock').read_bytes()).hexdigest()
metadata.update(commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 signing='UNSIGNED: re-signing and a device provisioning profile are required',
 verification='Cloud simulator and unsigned build only; no real-device or home-tailnet acceptance')
metadata['patches']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in pathlib.Path('custom/ios-tailnet/patches').glob('*.patch')}
pathlib.Path(sys.argv[1],'build-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
PY
(cd "$output" && shasum -a 256 ./*.ipa ./*.zip build-metadata.json > SHA256SUMS)
