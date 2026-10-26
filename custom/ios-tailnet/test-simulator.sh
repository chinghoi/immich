#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
temp_dir=$(mktemp -d)
fixture_pid=''
trap '[[ -z "$fixture_pid" ]] || kill "$fixture_pid" 2>/dev/null || true' EXIT
commit=$(python3 -c 'import json; print(json.load(open("custom/ios-tailnet/dependencies.json"))["libtailscaleCommit"])')
git clone --no-checkout --filter=blob:none https://github.com/tailscale/libtailscale.git "$temp_dir/libtailscale"
git -C "$temp_dir/libtailscale" checkout "$commit"
python3 - "$temp_dir/libtailscale/tstestcontrol/tstestcontrol.go" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();assert 'func main() {}' in s
p.write_text(s.replace('func main() {}','func unusedMain() {}'))
PY
cp custom/ios-tailnet/tests/fixture.go "$temp_dir/libtailscale/tstestcontrol/fixture.go"
(cd "$temp_dir/libtailscale" && go build -o "$temp_dir/fixture" ./tstestcontrol)
"$temp_dir/fixture" "$temp_dir/fixture.json" > "$RUNNER_TEMP/tailnet-fixture.log" 2>&1 &
fixture_pid=$!
for attempt in {1..60}; do [[ ! -f "$temp_dir/fixture.json" ]] || break; kill -0 "$fixture_pid"; sleep 1; done
test -s "$temp_dir/fixture.json"
python3 - "$temp_dir" <<'PY'
import json,pathlib,urllib.parse,sys
config=pathlib.Path('mobile/.dart_tool/package_config.json').resolve()
p=next(p for p in json.loads(config.read_text())['packages'] if p['name']=='native_video_player')
source=pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(urllib.parse.urljoin(config.as_uri(),p['rootUri'])).path))
pathlib.Path(sys.argv[1],'VideoProxyServer.swift').write_bytes((source/'ios/Classes/VideoProxyServer.swift').read_bytes())
PY
ruby custom/ios-tailnet/tests/create-project.rb "$root" "$temp_dir"
simulator=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if "iPhone" in d["name"]))')
xcrun simctl boot "$simulator" || true
xcrun simctl bootstatus "$simulator" -b
set -o pipefail
xcodebuild test -project "$temp_dir/TailnetTransport.xcodeproj" -scheme TailnetTransport \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$temp_dir/DerivedData" \
  -resultBundlePath "$RUNNER_TEMP/tailnet-transport.xcresult" CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$RUNNER_TEMP/tailnet-transport.log"
