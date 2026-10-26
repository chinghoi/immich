import XCTest
import TailscaleKit
import Foundation
import Security
import AVFoundation

/// Runs on an iOS SIMULATOR, against a disposable control server on the runner.
/// The fixture certificate is pinned only in this test; production trust stays default.
final class TransportTests: XCTestCase {
  private var fixture: [String: String] = [:]

  override func setUpWithError() throws {
    let url = Bundle(for: Self.self).url(forResource: "fixture", withExtension: "json")!
    fixture = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
  }

  func testUnifiedHTTPImagesUploadsWebSocketRangeAndReconnect() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = Configuration(hostName: "immich-simulator", path: directory.path,
      authKey: nil, controlURL: fixture["controlURL"]!, ephemeral: false)
    let node = try TailscaleNode(config: config, logger: nil)
    try await node.up()
    let firstIPs = try await node.addrs()
    let (configuration, _) = try await URLSessionConfiguration.tailscaleSession(node)
    configuration.timeoutIntervalForRequest = 15
    let trust = FixtureTrust(certificate: Data(base64Encoded: fixture["certificate"]!)!)
    let session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let target = fixture["target"]!

    var login = URLRequest(url: URL(string: target + "/api/auth/login")!)
    login.httpMethod = "POST"
    let (_, loginResponse) = try await session.data(for: login)
    XCTAssertEqual((loginResponse as? HTTPURLResponse)?.statusCode, 200)
    let (thumbnail, _) = try await session.data(from: URL(string: target + "/api/assets/thumbnail")!)
    XCTAssertEqual(thumbnail.count, 8192) // also checks cookie propagation after login

    for schemeTarget in [target, fixture["tlsTarget"]!] {
      for (start, end) in [(1024,2047),(4096,8191)] {
        var range = authorized(schemeTarget + "/api/assets/original?name=hello%20world")
        range.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: range)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"), "bytes \(start)-\(end)/8192")
        XCTAssertEqual(data, Data((start...end).map { UInt8($0 % 251) }))
      }
    }
    var invalidRange = authorized(target + "/api/assets/original")
    invalidRange.setValue("bytes=99999-", forHTTPHeaderField: "Range")
    let (_, invalidResponse) = try await session.data(for: invalidRange)
    XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 416)
    let (redirected, _) = try await session.data(for: authorized(target + "/api/redirect"))
    XCTAssertEqual(redirected, thumbnail)

    let boundary = "immich-fixture-boundary"
    var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"fixture.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
    body.append(thumbnail)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    let file = directory.appendingPathComponent("upload.multipart")
    try body.write(to: file)
    var upload = authorized(target + "/api/assets")
    upload.httpMethod = "POST"
    upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (uploadResult, uploadResponse) = try await session.upload(for: upload, fromFile: file)
    XCTAssertEqual((uploadResponse as? HTTPURLResponse)?.statusCode, 201)
    XCTAssertEqual((try JSONSerialization.jsonObject(with: uploadResult) as? [String: Any])?["bytes"] as? Int, 8192)

    for socketTarget in [target.replacingOccurrences(of: "http:", with: "ws:"), fixture["tlsTarget"]!.replacingOccurrences(of: "https:", with: "wss:")] {
      let socket = session.webSocketTask(with: authorized(socketTarget + "/api/socket"))
      socket.resume()
      try await socket.send(.string("immich-realtime"))
      let received = try await socket.receive()
      if case .string(let message) = received { XCTAssertEqual(message, "immich-realtime") } else { XCTFail("Wrong WebSocket frame") }
      socket.cancel(with: .normalClosure, reason: nil)
    }

    // Use the exact native-video dependency adapter with the SAME session.
    VideoProxyServer.shared.session = session
    let proxyURL = try XCTUnwrap(VideoProxyServer.shared.proxyURL(for: URL(string: target + "/api/assets/original")!))
    var video = URLRequest(url: proxyURL)
    video.setValue("Bearer fixture-only", forHTTPHeaderField: "Authorization")
    video.setValue("bytes=2048-4095", forHTTPHeaderField: "Range")
    let (videoData, videoResponse) = try await URLSession.shared.data(for: video)
    XCTAssertEqual((videoResponse as? HTTPURLResponse)?.statusCode, 206)
    XCTAssertEqual(videoData, Data((2048...4095).map { UInt8($0 % 251) }))
    // Exercise AVFoundation against a real MP4 through the dependency's proxy,
    // including a seek and clock advancement, rather than asserting Range alone.
    let movieURL = try XCTUnwrap(VideoProxyServer.shared.proxyURL(for: URL(string: target + "/api/assets/video")!))
    let movie = AVURLAsset(url: movieURL)
    let playable = try await movie.load(.isPlayable)
    XCTAssertTrue(playable)
    let player = AVPlayer(playerItem: AVPlayerItem(asset: movie))
    player.isMuted = true
    for _ in 0..<100 {
      if player.currentItem?.status != .unknown { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertEqual(player.currentItem?.status, .readyToPlay)
    let seeked = await player.seek(to: CMTime(seconds: 7, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    XCTAssertTrue(seeked)
    let initialTime = player.currentTime().seconds
    player.play()
    try await Task.sleep(nanoseconds: 1_000_000_000)
    XCTAssertGreaterThan(player.currentTime().seconds, initialTime + 0.2)
    player.pause()
    player.replaceCurrentItem(with: nil)
    let (statsData, _) = try await session.data(for: authorized(target + "/api/video-stats"))
    let stats = try JSONDecoder().decode([String: Int].self, from: statsData)
    XCTAssertGreaterThan(stats["ranges"] ?? 0, 0)
    VideoProxyServer.shared.session = nil

    let slow = Task { try await session.data(for: authorized(target + "/api/slow")) }
    try await Task.sleep(nanoseconds: 100_000_000)
    slow.cancel()
    do { _ = try await slow.value; XCTFail("Cancellation was ignored") } catch { }

    // Same protected directory restores the node identity after process-node restart.
    session.invalidateAndCancel()
    try await node.close()
    let restored = try TailscaleNode(config: config, logger: nil)
    try await restored.up()
    let restoredIPs = try await restored.addrs()
    XCTAssertEqual(firstIPs.ip4, restoredIPs.ip4)
    let (restoredConfiguration, _) = try await URLSessionConfiguration.tailscaleSession(restored)
    let restoredSession = URLSession(configuration: restoredConfiguration)
    // Up restores identity before every peer has learned the fresh endpoints.
    // Retry only this idempotent acceptance probe, for at most ~44 seconds.
    // This is not a production retry of arbitrary requests or POST bodies.
    let afterReconnect = try await recoveredData(authorized(target + "/api/assets/original"), session: restoredSession)
    XCTAssertEqual(afterReconnect.count, 8192)
    restoredSession.invalidateAndCancel()
    try await restored.close()
  }

  func testOrdinaryHTTPWithoutTailnetRemainsAvailable() async throws {
    let (data, response) = try await URLSession.shared.data(for: authorized(fixture["plainTarget"]! + "/api/assets/original"))
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(data.count, 8192)
  }

  private func authorized(_ address: String) -> URLRequest {
    var request = URLRequest(url: URL(string: address)!)
    request.setValue("Bearer fixture-only", forHTTPHeaderField: "Authorization")
    return request
  }

  private func recoveredData(_ request: URLRequest, session: URLSession) async throws -> Data {
    for attempt in 1...8 {
      do {
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return data
      } catch let error as URLError {
        guard [.badURL, .cannotConnectToHost, .networkConnectionLost, .timedOut].contains(error.code), attempt < 8 else { throw error }
        try await Task.sleep(nanoseconds: 500_000_000)
      }
    }
    throw URLError(.cannotConnectToHost)
  }
}

private final class FixtureTrust: NSObject, URLSessionDelegate {
  let certificate: Data
  init(certificate: Data) { self.certificate = certificate }
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust,
      let anchor = SecCertificateCreateWithData(nil, certificate as CFData) else {
      return completionHandler(.performDefaultHandling, nil)
    }
    SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
    SecTrustSetAnchorCertificatesOnly(trust, true)
    guard SecTrustEvaluateWithError(trust, nil) else { return completionHandler(.cancelAuthenticationChallenge, nil) }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}
