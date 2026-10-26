"""Apply two small, audited iOS seams to exact lockfile dependencies.

Run after flutter pub get and before CocoaPods/SPM resolution. A dependency
update that changes either seam fails here rather than silently losing routing.
"""
import json
import pathlib
import subprocess
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'mobile/.dart_tool/package_config.json'
packages = {p['name']: p for p in json.loads(CONFIG.read_text())['packages']}
for name, patch in [('background_downloader', 'background-downloader.patch'),
                    ('native_video_player', 'video-loopback.patch')]:
    uri = urllib.parse.urljoin(CONFIG.as_uri(), packages[name]['rootUri'])
    source = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
    if name == 'native_video_player':
        sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
        if sha != 'cdf621bdb7edaf996e118a58a48f6441187d79c6':
            raise SystemExit('native_video_player pin changed: review the iOS adapter patch')
    else:
        if 'version: 9.5.6' not in (source / 'pubspec.yaml').read_text():
            raise SystemExit('background_downloader pin changed: review the iOS adapter patch')
    patch_path = ROOT / 'custom/ios-tailnet/patches' / patch
    command = ['patch', '--batch', '-p1', '-i', str(patch_path)]
    applied = subprocess.run(command + ['--reverse', '--dry-run'], cwd=source, capture_output=True)
    if applied.returncode != 0:
        subprocess.run(command + ['--forward'], cwd=source, check=True)
    print(f'{name}: iOS seam verified')
