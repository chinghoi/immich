# Candidate validation

Validated code commit: `a5ffacaeaa4d58bab7cc5aff0fa3e80f79c22101`.
[Successful cloud run 40659714323](https://github.com/chinghoi/immich/actions/runs/40659714323), 2026-10-28.

| Check | Result |
| --- | --- |
| Exclusive provider selector, stop failure retry, startup failure recovery | 3 Swift tests passed |
| Configuration boundaries, invalid FFI input, encrypted TCP direct/relay HTTP Range byte integrity and restart | 3 Rust tests passed |
| Real EasyTier C ABI linkage, arm64 and x86_64 iOS simulator | Passed |
| Dart analysis | No issues |
| Mode selection, foreground restrictions, existing bridge behavior, small screen/keyboard/large text, Android exclusion | 12 Flutter tests passed |
| Existing Tailscale iOS simulator protocol regression | 2 XCTest tests passed |
| Complete Immich iOS simulator Debug build | Passed |
| Complete Immich iOS device Release build, unsigned | Passed |

Frameworks: pinned TailscaleKit plus pinned EasyTier v2.6.4, separate SDK pods with a shared process-local transport seam. The successful source artifact supplies normalized Dart/Rust formatting; syncing that formatting and these verification notes does not change runtime behavior.

The custom code preserves the official server compatibility, authentication and media logic. Switching providers does not rewrite the configured Immich server URL. Secrets stay in device Keychain; build/signing credentials are never uploaded to Actions.

Still pending: installation and lifecycle acceptance on the actual iPhone, a matching EasyTier Mac peer/TCP relay deployment, and throughput/video measurements on the user's cellular network. Cloud protocol tests do not establish carrier performance or prove that any UDP restriction has been removed.
