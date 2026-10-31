import Foundation
import Darwin

/// Uses the physical interface prefix, never an SSID or a private-IP guess.
enum EmbeddedLocalRoute {
  static func matches(_ remote: [UInt8], local: [UInt8], mask: [UInt8]) -> Bool {
    guard !remote.isEmpty, remote.count == local.count, local.count == mask.count,
          mask.contains(where: { $0 != 0 }) else { return false }
    return zip(zip(remote, local), mask).allSatisfy { pair in
      (pair.0.0 & pair.1) == (pair.0.1 & pair.1)
    }
  }
  private static func bytes(_ value: UnsafePointer<sockaddr>?) -> [UInt8]? {
    guard let value else { return nil }
    if value.pointee.sa_family == UInt8(AF_INET) {
      var ip = UnsafeRawPointer(value).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
      return withUnsafeBytes(of: &ip) { Array($0) }
    }
    if value.pointee.sa_family == UInt8(AF_INET6) {
      var ip = UnsafeRawPointer(value).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
      return withUnsafeBytes(of: &ip) { Array($0) }
    }
    return nil
  }
  static func contains(endpoint: String) -> Bool {
    let candidate = URLComponents(string: endpoint)?.host ?? ""
    let host = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: "%").first.map(String.init) ?? ""
    var v4 = in_addr(), v6 = in6_addr()
    let remote: [UInt8]
    if inet_pton(AF_INET, host, &v4) == 1 { remote = withUnsafeBytes(of: &v4) { Array($0) } }
    else if inet_pton(AF_INET6, host, &v6) == 1 { remote = withUnsafeBytes(of: &v6) { Array($0) } }
    else { return false }
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else { return false }
    defer { freeifaddrs(head) }
    var entry = head
    while let current = entry {
      let interface = current.pointee
      let name = String(cString: interface.ifa_name)
      if name.hasPrefix("en"), (interface.ifa_flags & UInt32(IFF_UP)) != 0,
         let local = bytes(UnsafePointer(interface.ifa_addr)),
         let mask = bytes(UnsafePointer(interface.ifa_netmask)),
         matches(remote, local: local, mask: mask) { return true }
      entry = interface.ifa_next
    }
    return false
  }
  static func fingerprint() -> String {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else { return "" }
    defer { freeifaddrs(head) }
    var result = [String](), entry = head
    while let current = entry {
      let interface = current.pointee, name = String(cString: current.pointee.ifa_name)
      if (name.hasPrefix("en") || name.hasPrefix("pdp_ip")), let address = bytes(UnsafePointer(interface.ifa_addr)) {
        result.append(name + ":" + address.map(String.init).joined(separator: "."))
      }
      entry = interface.ifa_next
    }
    return result.sorted().joined(separator: "|")
  }
}
