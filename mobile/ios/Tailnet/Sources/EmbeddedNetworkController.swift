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
  private var owner: EmbeddedNetworkMode = .none
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
  private func activateSelected() async throws -> (any EmbeddedTransport)? {
    let mode = TailnetPlugin.mode
    if owner != mode {
      // Keep ownership until stop succeeds. A retry cannot start a second SDK
      // after a failed stop merely because the persisted selection changed.
      try await provider(owner)?.stop(forgetIdentity: false)
      owner = mode
    }
    return provider(mode)
  }
  func select(_ mode: EmbeddedNetworkMode) async throws {
    await acquire(); defer { release() }
    if TailnetPlugin.mode != mode {
      UserDefaults.standard.set(mode.rawValue, forKey: "immich.network.mode")
      UserDefaults.standard.set(mode == .tailscale, forKey: TailnetPlugin.enabledKey)
      await TailnetPlugin.install(nil)
    }
    let selected = try await activateSelected()
    try await selected?.prepare()
  }
  func prepare() async throws {
    await acquire(); defer { release() }
    let selected = try await activateSelected()
    try await selected?.prepare()
  }
  func checkLoopback() async throws {
    await acquire(); defer { release() }
    let selected = try await activateSelected()
    try await selected?.checkLoopback()
  }
  func reconnect() async throws {
    await acquire(); defer { release() }
    let selected = try await activateSelected()
    try await selected?.reconnect()
  }
  func login() async throws {
    await acquire(); defer { release() }
    guard TailnetPlugin.mode == .tailscale else { throw TailnetFailure.disabled }
    _ = try await activateSelected()
    try await tailscale.login()
  }
  func logout() async throws {
    await acquire(); defer { release() }
    let previous = TailnetPlugin.mode
    UserDefaults.standard.set("none", forKey: "immich.network.mode")
    UserDefaults.standard.set(false, forKey: TailnetPlugin.enabledKey)
    await TailnetPlugin.install(nil)
    try await provider(owner)?.stop(forgetIdentity: owner == previous)
    if owner != previous { try await provider(previous)?.stop(forgetIdentity: true) }
    owner = .none
  }
  func status(targetHost: String?) async throws -> [String: Any] {
    await acquire(); defer { release() }
    let mode = TailnetPlugin.mode
    let selected = try await activateSelected()
    var status = try await selected?.status(targetHost: targetHost) ??
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
    if TailnetPlugin.mode == .easytier {
      let selected = try await activateSelected()
      try await selected?.reconnect()
    }
  }
}
