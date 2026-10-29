import XCTest
@testable import EmbeddedNetworkCore

final class SessionLifetimeTests: XCTestCase {
  func testReturnedFFIPointerSurvivesSessionReplacementUntilDartCanRetainIt() async throws {
    UserDefaults.standard.set("none", forKey: "immich.network.mode")
    let manager = URLSessionManager.shared
    weak var returnedSession = manager.session
    let pointer = manager.sessionPointer
    XCTAssertNotEqual(Int(bitPattern: pointer), 0)
    manager.recreateSession()
    // Pigeon delivers the integer asynchronously; native reset can win that race.
    try await Task.sleep(nanoseconds: 1_000_000_000)
    XCTAssertNotNil(returnedSession, "Dart can receive a freed URLSession when transport reset races the pointer response")
  }
  func testLocalRouteClassificationRequiresActualMatchingPrefix() {
    XCTAssertTrue(EmbeddedLocalRoute.matches([192,168,50,20], local: [192,168,50,10], mask: [255,255,255,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([192,168,60,20], local: [192,168,50,10], mask: [255,255,255,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([192,168,50,20], local: [192,168,50,10], mask: [0,0,0,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([127,0,0,1], local: [192,168,50,10], mask: [255,255,255,0]))
  }
}
