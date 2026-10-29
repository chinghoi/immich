#!/usr/bin/env python3
"""Exercise the real Rust Options type with the JSON keys emitted by Swift."""
from pathlib import Path
import tempfile, subprocess, os
root = Path(__file__).resolve().parents[2]
source = (root / "custom/ios-easytier/core/src/lib.rs").read_text()
options = source[source.index("#[derive(Deserialize)]"):source.index("fn quoted(")]
swift = (root / "mobile/ios/Tailnet/Sources/EasyTierConfiguration.swift").read_text()
assert '"allowP2P": allowP2P' in swift, "Update the native contract fixture when Swift changes"
with tempfile.TemporaryDirectory(prefix="immich-config-contract-") as temporary:
    p = Path(temporary)
    (p / "src").mkdir()
    (p / "Cargo.toml").write_text('[package]\nname="immich-config-contract"\nversion="0.0.0"\nedition="2024"\n[dependencies]\nserde={version="1",features=["derive"]}\nserde_json="1"\n')
    (p / "src/lib.rs").write_text("use serde::Deserialize;\n" + options + r'''
#[test]
fn swift_saved_configuration_survives_strategy_changes_and_restart() {
    for tcp in [true, false] {
        for p2p in [true, false] {
            let input = serde_json::json!({
                "networkName":"test", "networkSecret":"local-test-only",
                "peer":"tcp://127.0.0.1:11010", "ipv4":"10.77.23.2",
                "instanceId":"b60ee0cf-e733-4cdd-9937-26934bb81065",
                "tcpOnly":tcp, "allowP2P":p2p
            });
            let saved = serde_json::to_string(&input).unwrap();
            let actual: Options = serde_json::from_str(&saved).expect("Swift saved JSON must load after restart");
            assert_eq!(actual.tcp_only, tcp);
            assert_eq!(actual.allow_p2p, p2p);
        }
    }
}
''')
    subprocess.run(["cargo", "test", "--manifest-path", str(p / "Cargo.toml")], check=True)
