import Foundation
import Network
import ImmichEasyTier

/// SDK-specific work stays here. SOCKS is loopback-only, no TUN or system VPN.
/// The core is statically linked into the app; no executable is downloaded.
actor EasyTierProvider: EmbeddedTransport {
  private var port: UInt16?

  // Rust start/status/drop may block. They must never run on the UI executor.
  private func core<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .utility, operation: operation).value
  }
  func prepare() async throws {
    guard TailnetPlugin.mode == .easytier else { return }
    if port != nil { return }
    let options = try EasyTierConfiguration.options()
    let started = await core { options.withCString { immich_et_start($0) } }
    guard started > 0, let candidate = UInt16(exactly: started) else { throw TailnetFailure.invalidState }
    port = candidate
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
      if await listening(candidate) {
        await TailnetPlugin.install(ProxyConfiguration(
          socksv5Proxy: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: candidate)!)))
        return
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    try await stop(forgetIdentity: false)
    throw TailnetFailure.startupTimedOut
  }
  private func listening(_ port: UInt16) async -> Bool {
    await withCheckedContinuation { continuation in
      let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
      let queue = DispatchQueue(label: "immich.easytier.probe")
      var finished = false // accessed only on the connection's queue
      let finish: (Bool) -> Void = { ready in
        guard !finished else { return }
        finished = true
        connection.cancel()
        continuation.resume(returning: ready)
      }
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          connection.send(content: Data([5, 1, 0]), completion: .contentProcessed { error in
            if error != nil { finish(false); return }
            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
              finish(error == nil && data == Data([5, 0]))
            }
          })
        case .failed, .cancelled: finish(false)
        default: break
        }
      }
      connection.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 1) { finish(false) }
    }
  }
  func checkLoopback() async throws {
    guard let port else { try await prepare(); return }
    if !(await listening(port)) { try await reconnect() }
  }
  func reconnect() async throws {
    try await stop(forgetIdentity: false)
    try await prepare()
  }
  func stop(forgetIdentity: Bool) async throws {
    let result = await core { immich_et_stop() }
    port = nil
    await TailnetPlugin.install(nil)
    guard result == 0 else { throw TailnetFailure.invalidState }
    if forgetIdentity { try EasyTierConfiguration.forget() }
  }
  func status(targetHost: String?) async throws -> [String: Any] {
    guard port != nil else {
      return ["enabled": true, "state": try EasyTierConfiguration.load() == nil ? "NeedsConfiguration" : "Unavailable",
              "targetRoute": "Unlinked", "background": "foreground-only"]
    }
    let target = targetHost ?? ""
    let json: String? = await core {
      target.withCString {
        guard let pointer = immich_et_status($0) else { return nil }
        defer { immich_et_free(pointer) }
        return String(cString: pointer)
      }
    }
    guard let json, let data = json.data(using: .utf8),
          var status = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw TailnetFailure.invalidState
    }
    status.removeValue(forKey: "port")
    status["enabled"] = true
    status["background"] = "foreground-only"
    return status
  }
}
