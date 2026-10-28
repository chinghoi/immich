#!/usr/bin/env python3
"""Isolated patch to the pinned dependency, applied only in cloud build workspaces."""
import json
from pathlib import Path
import subprocess

metadata = json.loads(subprocess.check_output(["cargo", "metadata", "--locked", "--format-version", "1"]))
package = next(p for p in metadata["packages"] if p["name"] == "easytier")
assert "8428a89d2dabc94c97d370ec607c6ca142473626" in package["source"], "Review patch when upgrading EasyTier"
source = Path(package["manifest_path"]).parent / "src/connector/direct.rs"
original = source.read_text()
anchor = '            .filter(|l| mapped_listener_port(l).is_some() && l.host().is_some())'
insertion = """
            // Immich adapter: TCP-only may use UDP STUN control probes, never UDP data.
            .filter(|l| {
                let flags = self.global_ctx.get_flags();
                !(flags.disable_udp_hole_punching && flags.default_protocol == "tcp" && l.scheme() == "udp")
            })"""
if insertion not in original:
    assert original.count(anchor) == 1, "Pinned direct connector changed"
    source.write_text(original.replace(anchor, anchor + insertion))
print("Applied pinned EasyTier TCP data policy")
