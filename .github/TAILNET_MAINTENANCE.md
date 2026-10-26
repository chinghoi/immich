# iOS Tailscale fork maintenance

Historical main: archive/main-before-tailnet-20261026. Custom code: ios/tailscale.
Stable line: ios/stable. Discovery mirror: upstream/main. No force push is used.

Actual permission test: Actions run 40261139589 was refused workflows writes.
The default GITHUB_TOKEN cannot perform full upstream synchronization in this fork.
Without an optional TAILNET_SYNC_TOKEN, the GitHub cron therefore only discovers
main/stable changes and reports its mode explicitly. It does not claim promotion.

An authorized ChatGPT task has been created and enabled to check every 6 hours and
use the existing GitHub plugin for writes. Its first scheduled run has not occurred.
It must verify the exact candidate commit passed all Tailnet iOS checks before a
non-forced fast-forward. Failed/conflicted work preserves the last good version.

For standalone GitHub maintenance, optionally provision a short-lived fine-grained
TAILNET_SYNC_TOKEN restricted to this repository with Contents, Workflows,
Pull requests and Actions read/write permissions. Never put the token in source.

No Apple signing, TestFlight, App Store publication or home-server upgrade occurs.
Details and actual verification records:
https://github.com/chinghoi/immich/tree/ios/tailscale/custom/ios-tailnet
