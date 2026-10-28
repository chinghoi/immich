import Foundation
import Network
import TailscaleKit

private struct SilentTailnetLogger: LogSink {
  let logFileHandle: Int32? = -1 // libtailscale explicitly maps -1 to logger.Discard
  func log(_ message: String) {}
}

actor TailscaleProvider: EmbeddedTransport {
  private var node: TailscaleNode?
  private var upTask: Task<Void, Never>?
  private var installed = false
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  // Swift actors are reentrant across await. Serialize node transitions so a
  // path notification cannot close a node halfway through login/reconnection.
  private func acquire() async {
    if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
  }
  private func release() {
    if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
  }

  private func stateDirectory() throws -> URL {
    var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
      .appendingPathComponent("ImmichTailnet", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    return directory
  }

  func prepare() async throws {
    await acquire()
    do {
      try await prepareUnlocked()
    } catch {
      release()
      throw error
    }
    release()
    try await waitForReady()
  }

  /// NetworkRepository calls prepare before using the shared URLSession. Wait
  /// for a saved tailnet identity to finish starting, so splash-session requests
  /// don't hit the SOCKS listener before it can route them. Return at auth gates
  /// so the UI remains available to authorize or approve this device.
  private func waitForReady(timeout: TimeInterval = 15) async throws {
    guard TailnetPlugin.mode == .tailscale else { return }
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      await acquire()
      guard let node else {
        release()
        throw TailnetFailure.invalidState
      }

      let state: String?
      do {
        let data = try await node.statusJSON()
        let status = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        state = status?["BackendState"] as? String
      } catch {
        release()
        try? await Task.sleep(nanoseconds: 250_000_000)
        continue
      }
      release()

      if state == "Running" || state == "NeedsLogin" || state == "NeedsMachineAuth" {
        return
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }

    throw TailnetFailure.startupTimedOut
  }

  private func prepareUnlocked() async throws {
    if node == nil {
      let config = Configuration(hostName: "immich-ios", path: try stateDirectory().path,
                                 authKey: nil, controlURL: kDefaultControlURL, ephemeral: false)
      let created = try TailscaleNode(config: config, logger: SilentTailnetLogger())
      node = created
      // up() waits for authorization. Do not block the UI or the login screen.
      upTask = Task { try? await created.up() }
    }
    guard !installed, let node else { return }
    let configuration = URLSessionConfiguration.ephemeral
    _ = try await configuration.proxyVia(node)
    guard let proxy = configuration.proxyConfigurations.first else { throw TailnetFailure.invalidState }
    installed = true
    await TailnetPlugin.install(proxy)
  }

  func login() async throws {
    await acquire(); defer { release() }
    try await prepareUnlocked()
    guard let node else { throw TailnetFailure.invalidState }
    try await LocalAPIClient(localNode: node, logger: nil).startLoginInteractive()
  }

  func status(targetHost: String?) async throws -> [String: Any] {
    await acquire(); defer { release() }
    guard TailnetPlugin.mode == .tailscale else {
      return ["enabled": false, "state": "Disabled", "targetRoute": "Unlinked"]
    }
    try await prepareUnlocked()
    guard let node else { throw TailnetFailure.invalidState }
    let data = try await node.statusJSON()
    let status = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    // Deliberately whitelist fields; statusJSON also contains detailed tailnet data.
    return ["enabled": true, "state": status["BackendState"] as? String ?? "Starting",
            "targetRoute": targetRoute(for: targetHost, status: status),
            "authURL": status["AuthURL"] as? String ?? "",
            "background": "foreground-only"]
  }

  /// Report the path to the server currently configured in Immich, without
  /// returning the rest of the tailnet's peer list to Flutter.
  private func targetRoute(for targetHost: String?, status: [String: Any]) -> String {
    let trimDots = CharacterSet(charactersIn: ".")
    guard let targetHost = targetHost?.trimmingCharacters(in: trimDots).lowercased(),
          !targetHost.isEmpty,
          let peers = status["Peer"] as? [String: Any] else {
      return "Unlinked"
    }

    let peer = peers.values.compactMap { $0 as? [String: Any] }.first { candidate in
      let dnsName = (candidate["DNSName"] as? String ?? "")
        .trimmingCharacters(in: trimDots).lowercased()
      if dnsName == targetHost { return true }
      let addresses = candidate["TailscaleIPs"] as? [String] ?? []
      return addresses.contains { $0.lowercased() == targetHost }
    }
    guard let peer else { return "Unlinked" }

    if !(peer["CurAddr"] as? String ?? "").isEmpty { return "Direct" }
    if !(peer["Relay"] as? String ?? "").isEmpty ||
       !(peer["PeerRelay"] as? String ?? "").isEmpty { return "Relay" }
    if peer["Online"] as? Bool == true { return "Connecting" }
    return "Unlinked"
  }

  func checkLoopback() async throws {
    await acquire(); defer { release() }
    try await prepareUnlocked()
    guard let node else { return }
    do {
      _ = try await localRequest(node, endpoint: "status", method: "GET", timeout: 3)
    } catch {
      // iOS may reclaim the cached loopback listener during suspension. Recreate
      // the node with the SAME protected identity, never mint a new identity here.
      try await stopUnlocked(forgetIdentity: false)
      if TailnetPlugin.mode == .tailscale { try await prepareUnlocked() }
    }
  }

  func reconnect() async throws {
    await acquire(); defer { release() }
    try await stopUnlocked(forgetIdentity: false)
    if TailnetPlugin.mode == .tailscale { try await prepareUnlocked() }
  }

  func stop(forgetIdentity: Bool) async throws {
    await acquire(); defer { release() }
    try await stopUnlocked(forgetIdentity: forgetIdentity)
  }

  private func stopUnlocked(forgetIdentity: Bool) async throws {
    let old = node
    node = nil
    installed = false
    upTask?.cancel()
    upTask = nil
    if let old {
      if forgetIdentity { _ = try? await localRequest(old, endpoint: "logout", method: "POST", timeout: 5) }
      // Clear the transport even if an already-closed SDK handle reports an error.
      try? await old.close()
    }
    await TailnetPlugin.install(nil)
    if forgetIdentity { try FileManager.default.removeItem(at: stateDirectory()) }
  }

  private func localRequest(_ node: TailscaleNode, endpoint: String, method: String, timeout: TimeInterval) async throws -> Data {
    let (configuration, loopback) = try await URLSessionConfiguration.tailscaleSession(node)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    guard let url = URL(string: "http://\(loopback.address)/localapi/v0/\(endpoint)") else { throw TailnetFailure.invalidState }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("localapi", forHTTPHeaderField: "Sec-Tailscale")
    let basic = Data("tsnet:\(loopback.localAPIKey)".utf8).base64EncodedString()
    request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw TailnetFailure.invalidState }
    return data
  }
}
