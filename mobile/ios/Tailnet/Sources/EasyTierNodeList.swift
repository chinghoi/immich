import Foundation
import CryptoKit

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
  private let defaults: UserDefaults
  private let fetch: @Sendable (URL) async throws -> Data
  private var refreshing = Set<String>()
  private var lastAttempt = [String: Date]()
  init(defaults: UserDefaults = .standard,
       fetch: @escaping @Sendable (URL) async throws -> Data = EasyTierNodes.download) {
    self.defaults = defaults
    self.fetch = fetch
    // Retire the old cache that had an implicit, compiled-in owner.
    defaults.removeObject(forKey: "immich.easytier.verifiedNodes.v1")
  }
  static func validSubscription(_ value: String) -> Bool {
    guard value.utf8.count <= 2048, let u = URLComponents(string: value),
          u.scheme == "https", let host = u.host, !host.isEmpty,
          u.user == nil, u.password == nil, u.fragment == nil else { return false }
    return true
  }
  static func scope(_ sources: [String]) -> String {
    let bytes = Data(sources.joined(separator: "\u{0}").utf8)
    return "immich.easytier.nodes.v2." + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  func endpoints(sources: [String], force: Bool = false) async -> [String] {
    let sources = sources.filter(Self.validSubscription)
    guard !sources.isEmpty else { return [] }
    let key = Self.scope(sources)
    let cached = (defaults.stringArray(forKey: key) ?? []).filter(EasyTierNodeList.valid)
    if !force && Date().timeIntervalSince(lastAttempt[key] ?? .distantPast) < 600 { return cached }
    if !force && !cached.isEmpty {
      Task { await refresh(sources: sources, key: key) }
      return cached
    }
    await refresh(sources: sources, key: key)
    return (defaults.stringArray(forKey: key) ?? []).filter(EasyTierNodeList.valid)
  }
  private func refresh(sources: [String], key: String) async {
    guard !refreshing.contains(key) else { return }
    refreshing.insert(key)
    lastAttempt[key] = Date()
    defer { refreshing.remove(key) }
    for source in sources {
      guard let url = URL(string: source) else { continue }
      do {
        let nodes = EasyTierNodeList.decode(try await fetch(url))
        if !nodes.isEmpty { defaults.set(nodes, forKey: key); return }
      } catch { /* Only this subscription's cache and manual fallback may be reused. */ }
    }
  }
  private static func download(_ url: URL) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.connectionProxyDictionary = [:]
    configuration.timeoutIntervalForRequest = 4
    configuration.timeoutIntervalForResource = 5
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
          response.url == url, response.expectedContentLength <= 65536 else { throw URLError(.badServerResponse) }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 65536 else { throw URLError(.dataLengthExceedsMaximum) }
      data.append(byte)
    }
    return data
  }
}
