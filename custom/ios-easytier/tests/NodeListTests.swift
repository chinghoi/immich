import XCTest
@testable import EmbeddedNetworkCore

final class NodeListTests: XCTestCase {
  func testSubscriptionAcceptsOnlyVerifiedPublicTCPAddresses() throws {
    let data = Data("""
      {"schema":1,"validation":"easytier-encrypted-relay","nodes":[
        {"url":"tcp://101.251.179.30:11010"},{"url":"tcp://101.251.179.30:11010"},
        {"url":"tcp://192.168.50.10:11010"},{"url":"tcp://198.18.1.1:11010"},
        {"url":"udp://101.251.179.30:11010"},{"url":"tcp://user@101.251.179.30:11010"},
        {"url":"tcp://127.0.0.1:11010"},{"url":"tcp://10.77.23.1:11010"}]}
      """.utf8)
    XCTAssertEqual(EasyTierNodeList.decode(data), ["tcp://101.251.179.30:11010"])
  }
  func testDiscoveryAndMalformedOrOversizedListsAreNotConfiguration() {
    XCTAssertTrue(EasyTierNodeList.decode(Data(#"{"schema":1,"nodes":[{"url":"tcp://101.251.179.30:11010"}]}"#.utf8)).isEmpty)
    XCTAssertTrue(EasyTierNodeList.decode(Data("not JSON".utf8)).isEmpty)
    XCTAssertTrue(EasyTierNodeList.decode(Data(repeating: 32, count: 65537)).isEmpty)
  }
}
