"""Apply audited iOS seams to exact lockfile dependencies; fail on drift."""
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
    elif 'version: 9.5.6' not in (source / 'pubspec.yaml').read_text():
        raise SystemExit('background_downloader pin changed: review the iOS adapter patch')

    patch_path = ROOT / 'custom/ios-tailnet/patches' / patch
    command = ['git', 'apply', '--whitespace=nowarn']
    # patch --batch --reverse --dry-run can auto-detect the opposite direction
    # and return success for an UNPATCHED file. git apply never guesses direction.
    applied = subprocess.run(command + ['--reverse', '--check', str(patch_path)],
                             cwd=source, capture_output=True)
    if applied.returncode != 0:
        subprocess.run(command + ['--check', str(patch_path)], cwd=source, check=True)
        subprocess.run(command + [str(patch_path)], cwd=source, check=True)
    # Prove the exact result is present, including on a warm dependency cache.
    subprocess.run(command + ['--reverse', '--check', str(patch_path)], cwd=source, check=True)
    if name == 'background_downloader':
        swift = (source / 'ios/background_downloader/Sources/background_downloader/UrlSessionDelegate.swift').read_text()
        for required in ['public static var configurationFactory:', 'public static func resetSession()',
                         'configurationFactory?(sessionIdentifier)']:
            if required not in swift:
                raise SystemExit('background_downloader transport seam missing: ' + required)
    print(f'{name}: exact iOS seam applied and reverse-checked')
