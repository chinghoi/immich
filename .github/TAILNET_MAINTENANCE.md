# iOS Tailscale fork maintenance

The historical main branch is preserved in archive/main-before-tailnet-20261026.
This commit only appends isolated maintenance files; it does not replace main
with upstream or change its App/server/Web/Android source.

Custom development: ios/tailscale. Validated stable line: ios/stable.
Upstream discovery mirror: upstream/main. Candidate branches: sync/tailnet-vX.Y.Z.

The scheduled check runs every 6 hours and can be delayed or disabled by GitHub.
No Apple signing, TestFlight, App Store publishing, or server upgrade occurs.
Read the implementation and actual verification record on the custom branch:
https://github.com/chinghoi/immich/tree/ios/tailscale/custom/ios-tailnet

Only fully successful protocol tests plus simulator and unsigned device builds
can promote a candidate, by a non-forced fast-forward to its exact tested SHA.
Failed/conflicted updates preserve the previous stable branch and release.
