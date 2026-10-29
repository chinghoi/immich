import Foundation

/// Public addresses only. Credentials remain in the provider's Keychain entry.
enum EasyTierNodeList {
  static func valid(_ value: String) -> Bool {
    guard let u = URLComponents(string: value), u.scheme == "tcp",
          let host = u.host, let port = u.port, (1024...65535).contains(port),
          u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
          u.path.isEmpty else { return false }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    let p = parts.compactMap { Int($0) }
    guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
    let a = p[0], b = p[1]
    return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
      (a == 100 && (64...127).contains(b)) || (a == 169 && b == 254) ||
      (a == 172 && (16...31).contains(b)) || (a == 192 && [168,0,2].contains(b)) ||
      (a == 198 && [18,19,51].contains(b)) || (a == 203 && b == 0))
  }
  static func decode(_ data: Data) -> [String] {
    guard data.count <= 65536,
          let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          doc["schema"] as? Int == 1,
          doc["validation"] as? String == "easytier-encrypted-relay",
          let nodes = doc["nodes"] as? [[String: Any]] else { return [] }
    var result = [String]()
    for node in nodes.prefix(8) {
      if let url = node["url"] as? String, valid(url), !result.contains(url) { result.append(url) }
    }
    return result
  }
}

actor EasyTierNodes {
  static let shared = EasyTierNodes()
  private let cacheKey = "immich.easytier.verifiedNodes.v1"
  private var refreshing = false
  private var lastAttempt = Date.distantPast
  private let sources = [
    "https://nodes.example.invalid/nodes.json",
    "https://backup.example.invalid/nodes.json"
  ]
  func endpoints(force: Bool = false) async -> [String] {
    let cached = (UserDefaults.standard.stringArray(forKey: cacheKey) ?? []).filter(EasyTierNodeList.valid)
    if !force && Date().timeIntervalSince(lastAttempt) < 600 { return cached }
    if !force && !cached.isEmpty {
      Task { await refresh() }
      return cached
    }
    await refresh()
    return (UserDefaults.standard.stringArray(forKey: cacheKey) ?? []).filter(EasyTierNodeList.valid)
  }
  private func refresh() async {
    guard !refreshing else { return }
    refreshing = true
    lastAttempt = Date()
    defer { refreshing = false }
    // Control-plane fetch must never depend on the overlay it is bootstrapping.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.connectionProxyDictionary = [:]
    configuration.timeoutIntervalForRequest = 4
    configuration.timeoutIntervalForResource = 5
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    for source in sources {
      guard let url = URL(string: source) else { continue }
      do {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == url.host, response.url?.path == url.path,
              response.expectedContentLength <= 65536 else { continue }
        var data = Data()
        for try await byte in bytes {
          guard data.count < 65536 else { throw URLError(.dataLengthExceedsMaximum) }
          data.append(byte)
        }
        let nodes = EasyTierNodeList.decode(data)
        if !nodes.isEmpty {
          UserDefaults.standard.set(nodes, forKey: cacheKey)
          return
        }
      } catch { /* Keep previously verified addresses and the user's manual fallback. */ }
    }
  }
}
