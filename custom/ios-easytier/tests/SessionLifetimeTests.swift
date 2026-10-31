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
    manager.releaseSessionPointer(Int64(Int(bitPattern: pointer)))
    XCTAssertNotNil(returnedSession, "The old session must stay usable until Dart installs the new generation")
    let current = manager.sessionPointer
    manager.releaseSessionPointer(Int64(Int(bitPattern: current)))
    manager.confirmSessionPointer(Int64(Int(bitPattern: current)))
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNil(returnedSession, "The bridge must release its handoff after Dart acknowledges")
  }
  func testRepeatedPointerAcquisitionsHaveIndependentAcknowledgements() async throws {
    let manager = URLSessionManager.shared
    weak var old = manager.session
    let first = manager.sessionPointer, second = manager.sessionPointer
    manager.recreateSession()
    manager.releaseSessionPointer(Int64(Int(bitPattern: first)))
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNotNil(old)
    manager.releaseSessionPointer(Int64(Int(bitPattern: second)))
    manager.releaseSessionPointer(Int64(Int(bitPattern: second))) // duplicate acknowledgements are harmless
    let current = manager.sessionPointer
    manager.releaseSessionPointer(Int64(Int(bitPattern: current)))
    manager.confirmSessionPointer(Int64(Int(bitPattern: current)))
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNil(old)
  }
  func testOldSessionRemainsUsableUntilCurrentGenerationIsInstalled() async throws {
    let manager = URLSessionManager.shared
    let previous = manager.session
    let stalePointer = manager.sessionPointer
    manager.recreateSession()
    manager.releaseSessionPointer(Int64(Int(bitPattern: stalePointer)))
    manager.confirmSessionPointer(Int64(Int(bitPattern: stalePointer)))

    // This is the call that throws NSGenericException after invalidation.
    let request = URL(string: "ws://127.0.0.1:9/socket")!
    let socket = previous.webSocketTask(with: request)
    socket.cancel()

    let current = manager.sessionPointer
    manager.releaseSessionPointer(Int64(Int(bitPattern: current)))
    manager.confirmSessionPointer(Int64(Int(bitPattern: current)))
  }

  func testExpiredBackgroundCallbackCannotCancelANewerForegroundEpoch() {
    var window = EmbeddedRecoveryWindow()
    let old = window.begin()
    window.end()
    let current = window.begin()
    XCTAssertFalse(window.expire(old))
    XCTAssertEqual(window.token, current)
    XCTAssertTrue(window.expire(current))
    XCTAssertFalse(window.expire(current))
  }
  func testLocalRouteClassificationRequiresActualMatchingPrefix() {
    XCTAssertTrue(EmbeddedLocalRoute.matches([192,168,50,20], local: [192,168,50,10], mask: [255,255,255,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([192,168,60,20], local: [192,168,50,10], mask: [255,255,255,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([192,168,50,20], local: [192,168,50,10], mask: [0,0,0,0]))
    XCTAssertFalse(EmbeddedLocalRoute.matches([127,0,0,1], local: [192,168,50,10], mask: [255,255,255,0]))
  }
}
