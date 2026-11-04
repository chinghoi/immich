"""Public builds must not ship an owner's subscription or signing material."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[2]
sources = root / "mobile/ios/Tailnet/Sources"
subscription = (sources / "EasyTierNodeList.swift").read_text()
assert not re.search(r'https?://', subscription), "Subscription URLs must come from phone configuration"
assert 'stored["subscriptionURL"]' in (sources / "EasyTierConfiguration.swift").read_text()
assert 'sources: sources' in (sources / "EasyTierConfiguration.swift").read_text()
for folder in [root / 'custom', root / 'mobile/ios/Tailnet']:
    for path in folder.rglob('*'):
        assert path.suffix.lower() not in {'.p12', '.pfx', '.mobileprovision', '.keychain'}, "Private signing material in source"
print('Owner-free subscription bootstrap and signing-material checks passed')
