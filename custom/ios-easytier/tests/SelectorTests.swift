import XCTest
@testable import EmbeddedNetworkCore

final class SelectorTests: XCTestCase {
  private func reset() async {
    UserDefaults.standard.removeObject(forKey: "immich.network.mode")
    UserDefaults.standard.removeObject(forKey: TailnetPlugin.enabledKey)
    await ProviderProbe.shared.reset()
  }
  func testRapidSwitchAndPathEventsNeverRunBothProviders() async throws {
    await reset()
    let selector = EmbeddedNetworkController()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask { try await selector.select(.tailscale) }
        group.addTask { try await selector.select(.easytier) }
        group.addTask { try await selector.checkLoopback() }
      }
      try await group.waitForAll()
    }
    try await selector.select(.none)
    let (active, overlap) = await ProviderProbe.shared.snapshot()
    XCTAssertTrue(active.isEmpty)
    XCTAssertFalse(overlap)
    XCTAssertEqual(TailnetPlugin.mode, .none)
  }
  func testFailedStopDoesNotLoseOwnershipBeforeRetry() async throws {
    await reset()
    let selector = EmbeddedNetworkController()
    try await selector.select(.tailscale)
    await ProviderProbe.shared.failNextStop("tailscale")
    do { try await selector.select(.easytier); XCTFail("stop should fail") } catch {}
    let first = await ProviderProbe.shared.snapshot()
    XCTAssertEqual(first.0, ["tailscale"])
    try await selector.select(.easytier)
    let second = await ProviderProbe.shared.snapshot()
    XCTAssertEqual(second.0, ["easytier"])
    XCTAssertFalse(second.1)
    try await selector.select(.none)
  }
  func testStartupFailureKeepsSelectionWithoutFallingBack() async throws {
    await reset()
    let selector = EmbeddedNetworkController()
    await ProviderProbe.shared.failNextStart("easytier")
    do { try await selector.select(.easytier); XCTFail("start should fail") } catch {}
    XCTAssertEqual(TailnetPlugin.mode, .easytier)
    let first = await ProviderProbe.shared.snapshot()
    XCTAssertTrue(first.0.isEmpty)
    try await selector.reconnect()
    let second = await ProviderProbe.shared.snapshot()
    XCTAssertEqual(second.0, ["easytier"])
    try await selector.select(.none)
  }
}
