import Foundation

public enum EmbeddedNetworkMode: String { case none, tailscale, easytier }
enum TailnetFailure: Error { case disabled, invalidState, startupTimedOut }

/// Provider implementations own SDK state; the selector alone owns persistence,
/// mutual exclusion and HTTP-session replacement. Keep Immich code SDK-agnostic.
protocol EmbeddedTransport: Actor {
  func prepare() async throws
  func checkLoopback() async throws
  func reconnect() async throws
  func stop(forgetIdentity: Bool) async throws
  func status(targetHost: String?) async throws -> [String: Any]
}

actor EmbeddedNetworkController {
  private let tailscale = TailscaleProvider()
  private let easytier = EasyTierProvider()
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  // Actors are reentrant at await; serialize the COMPLETE transition, not just
  // the mode assignment. Rapid taps/status/path events cannot start both SDKs.
  private func acquire() async {
    if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
  }
  private func release() {
    if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
  }
  private func provider(_ mode: EmbeddedNetworkMode) -> (any EmbeddedTransport)? {
    switch mode {
    case .none: return nil
    case .tailscale: return tailscale
    case .easytier: return easytier
    }
  }
  func select(_ mode: EmbeddedNetworkMode) async throws {
    await acquire(); defer { release() }
    let previous = TailnetPlugin.mode
    if previous != mode {
      // Set selected policy BEFORE clearing the proxy: new sessions fail closed
      // throughout startup. In off mode they regain ordinary system networking.
      UserDefaults.standard.set(mode.rawValue, forKey: "immich.network.mode")
      UserDefaults.standard.set(mode == .tailscale, forKey: TailnetPlugin.enabledKey)
      await TailnetPlugin.install(nil)
      try await provider(previous)?.stop(forgetIdentity: false)
    }
    try await provider(mode)?.prepare()
  }
  func prepare() async throws {
    await acquire(); defer { release() }
    try await provider(TailnetPlugin.mode)?.prepare()
  }
  func checkLoopback() async throws {
    await acquire(); defer { release() }
    try await provider(TailnetPlugin.mode)?.checkLoopback()
  }
  func reconnect() async throws {
    await acquire(); defer { release() }
    try await provider(TailnetPlugin.mode)?.reconnect()
  }
  func login() async throws {
    await acquire(); defer { release() }
    guard TailnetPlugin.mode == .tailscale else { throw TailnetFailure.disabled }
    try await tailscale.login()
  }
  func logout() async throws {
    await acquire(); defer { release() }
    let previous = TailnetPlugin.mode
    UserDefaults.standard.set("none", forKey: "immich.network.mode")
    UserDefaults.standard.set(false, forKey: TailnetPlugin.enabledKey)
    await TailnetPlugin.install(nil)
    try await provider(previous)?.stop(forgetIdentity: true)
  }
  func status(targetHost: String?) async throws -> [String: Any] {
    await acquire(); defer { release() }
    let mode = TailnetPlugin.mode
    var status = try await provider(mode)?.status(targetHost: targetHost) ??
      ["enabled": false, "state": "Disabled", "targetRoute": "Unlinked"]
    status["mode"] = mode.rawValue
    return status
  }
  func configuration() async throws -> [String: Any] {
    await acquire(); defer { release() }
    return try EasyTierConfiguration.publicFields()
  }
  func saveConfiguration(_ fields: [String: Any]) async throws {
    await acquire(); defer { release() }
    try EasyTierConfiguration.save(fields)
    if TailnetPlugin.mode == .easytier { try await easytier.reconnect() }
  }
}
