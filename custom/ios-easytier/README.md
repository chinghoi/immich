# Immich iOS optional network providers

## Contract and isolation

The UI offers exactly one of `none`, `tailscale`, `easytier`. Only the selected provider can own the loopback proxy. Selection is persisted; the old `immich.tailnet.enabled` preference migrates to Tailscale without losing its identity. Switching stops the previous SDK, cancels old URLSession work, and prepares the next SDK. A selected provider with missing credentials or failed startup stays blocked until the user fixes it or selects ordinary networking. There is no automatic fallback from a selected provider to an unintended provider.

The existing Immich HTTP, WebSocket, image, downloader, and video session integration is retained. Cookie/header/certificate handling, server compatibility, media logic and authentication are not replaced. Turning embedded networking off restores ordinary system URLSession behavior. The system VPN configuration is never created or changed; another system VPN can still affect the SDK's outer network connections.

Source ownership:

- `mobile/lib/embedded_network/`: mode/config/status UI and narrow control channel.
- `mobile/lib/tailnet/`: compatibility wrappers so existing upstream insertion points stay stable.
- `mobile/ios/Tailnet/Sources/EmbeddedNetworkController.swift`: exclusive lifecycle, persisted selection, session changes.
- `TailscaleProvider.swift`: Tailscale SDK and identity. No EasyTier dependency.
- `EasyTierProvider.swift`, `EasyTierConfiguration.swift`: EasyTier adapter and device-local Keychain configuration. No Tailscale dependency.
- `custom/ios-easytier/core/`: small Rust C ABI around pinned upstream EasyTier, without TUN, root, or NetworkExtension.
- \`mobile/ios/EasyTierCore/\`: separate SDK pod and framework, with no dependency on Tailscale.
- The upstream app bar contains one imported status widget, rather than an inline provider implementation.

Keep fork changes at these seams when merging a new stable Immich tag. The existing upstream-maintenance process still targets the established Tailscale branch; this candidate branch is not silently promoted. After validation/merge, the same maintenance workflow picks up these modules. Review the URLSession/downloader/video hooks and rerun protocol tests after every upstream update.

## EasyTier setup

The Mac must also run EasyTier with the SAME network name and secret, a DIFFERENT virtual IP in the SAME /24, and a reachable TCP listener or relay. The phone does not magically join the Tailscale network through EasyTier. A public relay must allow both peers to join/forward traffic and have sufficient egress bandwidth. Do not put actual network credentials in this public repository, workflow inputs, or logs.

In the app choose EasyTier, enter the network name/secret, a `tcp://host:port` peer and the phone's virtual IPv4 (for example `10.77.23.2`). The secret stays in this phone's Keychain, excluded from migration/backups; reading configuration returns only `hasSecret`. Leaving the password blank reuses it. Save and connect. Clear-current-identity removes only the selected provider's saved state.

For TCP-only mode, BOTH endpoints should use TCP-capable paths and the intended relay. The phone disables automatic UDP/TCP hole punching and connects to its explicitly supplied TCP peer. No KCP/QUIC/WireGuard components are enabled in this core build. KCP also uses UDP and is not a promised solution to UDP throttling. TCP can suffer loss/congestion and TCP-over-TCP effects; performance remains a measurement, not a guarantee.

In Immich use the Mac's EasyTier IP, for example `http://10.77.23.1:2283`. Tailscale's `100.x` address and MagicDNS name are not EasyTier addresses. Changing network mode does NOT rewrite the Immich server URL, log the user in to a different server, or migrate accounts. An existing private TLS name can be used only if it resolves/reaches the intended server and its certificate remains valid.

No system DNS, routes, router/firewall settings, existing Mac services, or tailnet policies are changed by this app implementation. The local SOCKS listener binds only `127.0.0.1` and is never published. Outer TCP tunnels remain encrypted by EasyTier.

## Status and iOS lifecycle

The top status icon follows the selected provider. Ordinary mode is labelled ordinary networking, not a disconnected VPN. Tailscale preserves its existing target-peer status. EasyTier reports the route to the configured server's virtual IPv4: one-hop direct, multi-hop relay, no matching route unlinked. Protocol comes from the next hop's live connection. A running core, a route, and successful media throughput are separate facts; the icon does not claim a speed test.

Both SDKs run inside the Immich process. iOS may suspend/terminate it; they cannot promise always-on connectivity or background automatic backup. Finite UIKit background time can finish some current work. Widgets/extensions are separate processes and do not share the tunnel. Ordinary networking retains the official background transport.

## Build, test, provenance

- EasyTier v2.6.4, commit `8428a89d2dabc94c97d370ec607c6ca142473626`.
- Upstream's iOS source requires the TUN/MagicDNS compilation features. The adapter never supplies a TUN descriptor, forces runtime no-TUN mode, and does not accept system DNS configuration. These build features do not create a VPN or change system routes.
- Cloud-only Rust builds produce static XCFramework slices for arm64 iOS and universal arm64/x86_64 simulator.
- Cloud builds stay unsigned; Apple identities, private keys and provisioning profiles remain on the signing Mac.
- Rust tests cover malformed input/config injection boundaries, real direct and two-hop relay encrypted TCP paths through loopback SOCKS, HTTP Range byte integrity, and stop/restart.
- Flutter regressions cover all three mode requests and foreground restrictions; existing Tailscale simulator protocol tests remain required.
- Unsigned app builds validate native linkage. They do not establish device performance, suspension reliability, or real home/phone connectivity.

Upstream EasyTier is LGPL-3.0; this fork's Immich license remains AGPL. Static distribution must retain the upstream license/notices, exact corresponding sources and build instructions, and provide the materials needed for relinking as applicable. Do not remove notices when packaging/signing.

Official references: [EasyTier no-TUN](https://easytier.cn/en/guide/network/no-root.html), [configuration](https://easytier.cn/en/guide/network/configurations.html), [pinned core](https://github.com/EasyTier/EasyTier/tree/8428a89d2dabc94c97d370ec607c6ca142473626).
