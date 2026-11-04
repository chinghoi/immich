import Foundation

/// Avoid tearing down a working transport for a single slow response, and
/// bound repeated recovery when the server itself is offline.
struct EmbeddedRecoveryPolicy {
  private var lastRecovery: Date?

  mutating func shouldRecover(first: Bool, second: Bool, now: Date) -> Bool {
    guard !first && !second else { return false }
    if let lastRecovery, now.timeIntervalSince(lastRecovery) < 60 { return false }
    lastRecovery = now
    return true
  }

  static func pingURL(_ raw: String?, ownIP: String) -> URL? {
    guard let raw, var url = URLComponents(string: raw),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host else { return nil }
    let target = host.split(separator: ".", omittingEmptySubsequences: false)
    let own = ownIP.split(separator: ".", omittingEmptySubsequences: false)
    guard target.count == 4, own.count == 4,
          target.allSatisfy({ UInt8($0) != nil }),
          own.allSatisfy({ UInt8($0) != nil }),
          target.prefix(3) == own.prefix(3) else { return nil }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    url.path = "/" + (path.isEmpty ? "" : path + "/") + (path == "api" || path.hasSuffix("/api") ? "" : "api/") + "server/ping"
    url.query = nil
    url.fragment = nil
    url.user = nil
    url.password = nil
    return url.url
  }
}
