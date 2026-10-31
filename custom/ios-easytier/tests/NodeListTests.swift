import XCTest
@testable import EmbeddedNetworkCore

final class NodeListTests: XCTestCase {
  func testSubscriptionAcceptsOnlyVerifiedPublicTCPAddresses() throws {
    let data = Data("""
      {"schema":1,"validation":"easytier-encrypted-relay","nodes":[
        {"url":"tcp://93.184.216.34:11010"},{"url":"tcp://93.184.216.34:11010"},
        {"url":"tcp://192.168.50.10:11010"},{"url":"tcp://198.18.1.1:11010"},
        {"url":"udp://93.184.216.34:11010"},{"url":"tcp://user@93.184.216.34:11010"},
        {"url":"tcp://127.0.0.1:11010"},{"url":"tcp://10.77.23.1:11010"}]}
      """.utf8)
    XCTAssertEqual(EasyTierNodeList.decode(data), ["tcp://93.184.216.34:11010"])
  }
  func testDiscoveryAndMalformedOrOversizedListsAreNotConfiguration() {
    XCTAssertTrue(EasyTierNodeList.decode(Data(#"{"schema":1,"nodes":[{"url":"tcp://93.184.216.34:11010"}]}"#.utf8)).isEmpty)
    XCTAssertTrue(EasyTierNodeList.decode(Data("not JSON".utf8)).isEmpty)
    XCTAssertTrue(EasyTierNodeList.decode(Data(repeating: 32, count: 65537)).isEmpty)
  }
  func testSubscriptionValidationAndCacheScope() {
    XCTAssertTrue(EasyTierNodes.validSubscription("https://nodes.example.invalid/nodes.json"))
    XCTAssertFalse(EasyTierNodes.validSubscription("http://nodes.example.invalid/nodes.json"))
    XCTAssertFalse(EasyTierNodes.validSubscription("https://user:password@nodes.example.invalid/nodes.json"))
    XCTAssertNotEqual(EasyTierNodes.scope(["https://a.example.invalid/list"]), EasyTierNodes.scope(["https://b.example.invalid/list"]))
  }
  func testSubscriptionChangeCannotReuseAnotherSourcesNodes() async throws {
    let suite = "node-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let a = ["https://a.example.invalid/list"], b = ["https://b.example.invalid/list"]
    defaults.set(["tcp://93.184.216.34:11010"], forKey: EasyTierNodes.scope(a))
    let nodes = EasyTierNodes(defaults: defaults, fetch: { _ in throw URLError(.notConnectedToInternet) })
    let old = await nodes.endpoints(sources: a, force: true)
    let changed = await nodes.endpoints(sources: b, force: true)
    let empty = await nodes.endpoints(sources: [], force: true)
    XCTAssertEqual(old, ["tcp://93.184.216.34:11010"])
    XCTAssertTrue(changed.isEmpty)
    XCTAssertTrue(empty.isEmpty)
  }
  func testFailedPrimaryUsesBackupAndKeepsVerifiedCache() async throws {
    let suite = "node-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let nodes = EasyTierNodes(defaults: defaults, fetch: { url in
      if url.host == "a.example.invalid" { throw URLError(.timedOut) }
      return Data(#"{"schema":1,"validation":"easytier-encrypted-relay","nodes":[{"url":"tcp://93.184.216.34:11010"}]}"#.utf8)
    })
    let result = await nodes.endpoints(sources: ["https://a.example.invalid/list", "https://b.example.invalid/list"], force: true)
    XCTAssertEqual(result, ["tcp://93.184.216.34:11010"])
  }
}
