import XCTest
@testable import EmbeddedNetworkCore

final class RecoveryPolicyTests: XCTestCase {
  func testUnreachableServerTriggersOneBoundedRecovery() {
    var policy = EmbeddedRecoveryPolicy()
    let now = Date(timeIntervalSince1970: 1000)
    XCTAssertFalse(policy.shouldRecover(first: false, second: true, now: now))
    XCTAssertTrue(policy.shouldRecover(first: false, second: false, now: now))
    XCTAssertFalse(policy.shouldRecover(first: false, second: false, now: now.addingTimeInterval(20)))
    XCTAssertTrue(policy.shouldRecover(first: false, second: false, now: now.addingTimeInterval(61)))
  }

  func testPingIsRestrictedToSelectedOverlayAndPreservesPortAndBasePath() {
    XCTAssertEqual(EmbeddedRecoveryPolicy.pingURL("http://10.77.23.1:2283/api", ownIP: "10.77.23.2")?.absoluteString,
                   "http://10.77.23.1:2283/api/server/ping")
    XCTAssertEqual(EmbeddedRecoveryPolicy.pingURL("https://10.77.23.1:8443/immich", ownIP: "10.77.23.2")?.absoluteString,
                   "https://10.77.23.1:8443/immich/api/server/ping")
    XCTAssertNil(EmbeddedRecoveryPolicy.pingURL("https://example.invalid", ownIP: "10.77.23.2"))
    XCTAssertNil(EmbeddedRecoveryPolicy.pingURL("http://10.77.24.1", ownIP: "10.77.23.2"))
    XCTAssertNil(EmbeddedRecoveryPolicy.pingURL(nil, ownIP: "10.77.23.2"))
  }
}
