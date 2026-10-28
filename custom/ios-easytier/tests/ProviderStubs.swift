import Foundation

// Only compiled by the standalone selector tests, never included in the app.
enum TailnetPlugin {
  static let enabledKey = "immich.tailnet.enabled"
  static var mode: EmbeddedNetworkMode {
    if let value = UserDefaults.standard.string(forKey: "immich.network.mode") {
      return EmbeddedNetworkMode(rawValue: value) ?? .none
    }
    return UserDefaults.standard.bool(forKey: enabledKey) ? .tailscale : .none
  }
  static func install(_ unused: Int?) async {}
}
enum ProbeError: Error { case stopped, startup, overlap }
actor ProviderProbe {
  static let shared = ProviderProbe()
  var active = Set<String>()
  var failStop: String?
  var failStart: String?
  var overlap = false
  func reset() { active = []; failStop = nil; failStart = nil; overlap = false }
  func failNextStop(_ name: String) { failStop = name }
  func failNextStart(_ name: String) { failStart = name }
  func start(_ name: String) throws {
    if failStart == name { failStart = nil; throw ProbeError.startup }
    if !active.subtracting([name]).isEmpty { overlap = true; throw ProbeError.overlap }
    active.insert(name)
  }
  func stop(_ name: String) throws {
    if failStop == name { failStop = nil; throw ProbeError.stopped }
    active.remove(name)
  }
  func snapshot() -> (Set<String>, Bool) { (active, overlap) }
}
actor TailscaleProvider: EmbeddedTransport {
  func prepare() async throws {
    try await Task.sleep(nanoseconds: 10_000_000)
    try await ProviderProbe.shared.start("tailscale")
  }
  func checkLoopback() async throws { try await prepare() }
  func reconnect() async throws { try await stop(forgetIdentity: false); try await prepare() }
  func stop(forgetIdentity: Bool) async throws { try await ProviderProbe.shared.stop("tailscale") }
  func status(targetHost: String?) async throws -> [String: Any] { ["state": "Running"] }
  func login() async throws { try await prepare() }
}
actor EasyTierProvider: EmbeddedTransport {
  func prepare() async throws {
    try await Task.sleep(nanoseconds: 10_000_000)
    try await ProviderProbe.shared.start("easytier")
  }
  func checkLoopback() async throws { try await prepare() }
  func reconnect() async throws { try await stop(forgetIdentity: false); try await prepare() }
  func stop(forgetIdentity: Bool) async throws { try await ProviderProbe.shared.stop("easytier") }
  func status(targetHost: String?) async throws -> [String: Any] { ["state": "Running"] }
}
enum EasyTierConfiguration {
  static func publicFields() throws -> [String: Any] { [:] }
  static func save(_ fields: [String: Any]) throws {}
}
