import Foundation
import Security
import Darwin

/// Credentials never enter UserDefaults, app logs, backups, or CI secrets.
/// Only the non-secret fields are returned to Flutter; a blank password reuses
/// the saved value. Forget removes only this provider's configuration.
enum EasyTierConfiguration {
  private static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.test.immich.embedded-easytier",
    kSecAttrAccount as String: "network"
  ]
  static func load() throws -> [String: Any]? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data,
          let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw TailnetFailure.invalidState
    }
    return fields
  }
  static func publicFields() throws -> [String: Any] {
    guard var fields = try load() else { return ["tcpOnly": true, "hasSecret": false] }
    fields["hasSecret"] = !(fields.removeValue(forKey: "networkSecret") as? String ?? "").isEmpty
    return fields
  }
  static func save(_ input: [String: Any]) throws {
    let name = (input["networkName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let peer = (input["peer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let ip = (input["ipv4"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let tcp = input["tcpOnly"] as? Bool ?? true
    let previous = try load()
    let allowP2P = input["allowP2P"] as? Bool ?? previous?["allowP2P"] as? Bool ?? true
    let automatic = input["autoNodes"] as? Bool ?? true
    let subscription = (input["subscriptionURL"] as? String ?? previous?["subscriptionURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let backup = (input["backupSubscriptionURL"] as? String ?? previous?["backupSubscriptionURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard (subscription.isEmpty || EasyTierNodes.validSubscription(subscription)),
          (backup.isEmpty || EasyTierNodes.validSubscription(backup)) else { throw TailnetFailure.invalidState }
    let entered = input["networkSecret"] as? String ?? ""
    let secret = entered.isEmpty ? previous?["networkSecret"] as? String ?? "" : entered
    var address = in_addr()
    guard !name.isEmpty, name.utf8.count <= 128, !secret.isEmpty, secret.utf8.count <= 1024,
          inet_pton(AF_INET, ip, &address) == 1,
          (automatic && !subscription.isEmpty) || validPeer(peer, tcpOnly: tcp) else {
      throw TailnetFailure.invalidState
    }
    let fields: [String: Any] = ["networkName": name, "networkSecret": secret,
      "peer": peer, "ipv4": ip, "tcpOnly": tcp, "allowP2P": allowP2P, "autoNodes": automatic, "subscriptionURL": subscription, "backupSubscriptionURL": backup]
    let data = try JSONSerialization.data(withJSONObject: fields)
    let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updated == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw TailnetFailure.invalidState }
    } else if updated != errSecSuccess { throw TailnetFailure.invalidState }
  }
  static func forget() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw TailnetFailure.invalidState }
    UserDefaults.standard.removeObject(forKey: "immich.easytier.instanceID")
  }
  static func validPeer(_ peer: String, tcpOnly: Bool) -> Bool {
    guard let url = URLComponents(string: peer), let scheme = url.scheme,
          (scheme == "tcp" || (!tcpOnly && scheme == "udp")), url.host != nil,
          let port = url.port, port > 0, port <= 65535, url.user == nil, url.password == nil,
          url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return false }
    return true
  }
  static func options(forceNodes: Bool = false) async throws -> String {
    guard let stored = try load() else { throw TailnetFailure.invalidState }
    let key = "immich.easytier.instanceID"
    let id = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString.lowercased()
    UserDefaults.standard.set(id, forKey: key)
    let tcp = stored["tcpOnly"] as? Bool ?? true
    let manual = stored["peer"] as? String ?? ""
    let automatic = stored["autoNodes"] as? Bool ?? true
    let sources = [stored["subscriptionURL"] as? String ?? "", stored["backupSubscriptionURL"] as? String ?? ""].filter { !$0.isEmpty }
    let peers = automatic ? await EasyTierNodes.shared.endpoints(sources: sources, force: forceNodes) : []
    let fallback = validPeer(manual, tcpOnly: tcp) ? manual : ""
    guard !peers.isEmpty || !fallback.isEmpty else { throw TailnetFailure.invalidState }
    // App-only preferences must never cross the strict Rust JSON boundary.
    let fields: [String: Any] = [
      "networkName": stored["networkName"] as? String ?? "",
      "networkSecret": stored["networkSecret"] as? String ?? "",
      "ipv4": stored["ipv4"] as? String ?? "",
      "tcpOnly": tcp, "allowP2P": stored["allowP2P"] as? Bool ?? true,
      "peer": fallback, "peers": peers, "instanceId": id
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
  }
}
