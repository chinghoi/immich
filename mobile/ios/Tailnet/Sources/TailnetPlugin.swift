import Flutter
import Foundation
import Network
import UIKit

/// This module never creates a NetworkExtension or changes the device's VPN.
/// Credentials from loopback() remain in this process and never cross Flutter.
public final class TailnetPlugin: NSObject, FlutterPlugin {
  public static let enabledKey = "immich.tailnet.enabled"
  public static let transportChanged = Notification.Name("immich.tailnet.transportChanged")
  public static var rebuildSession: (() -> Void)?
  public static var expireTransfers: (() -> Void)?
  public static var releaseSessionPointer: ((Int64) -> Void)?
  public static var confirmSessionPointer: ((Int64) -> Void)?
  public static var serverHost: (() -> String?)?
  public static var serverURL: (() -> String?)?
  public static var probeServer: ((URL) async -> Bool)?
  private static var graceTask: UIBackgroundTaskIdentifier = .invalid
  private static let controller = EmbeddedNetworkController()
  private static let lock = NSLock()
  private static var proxy: ProxyConfiguration?
  private let channel: FlutterMethodChannel
  private static let monitor = NWPathMonitor()
  private static var monitoring = false
  @MainActor private static var previousPath: String?
  @MainActor private static var recoveryTask: Task<Void, Never>?
  @MainActor private static var recoveryWindow = EmbeddedRecoveryWindow()

  public static var mode: EmbeddedNetworkMode {
    if let value = UserDefaults.standard.string(forKey: "immich.network.mode") {
      return EmbeddedNetworkMode(rawValue: value) ?? .none
    }
    return UserDefaults.standard.bool(forKey: enabledKey) ? .tailscale : .none
  }
  public static var isEnabled: Bool { mode != .none }

  public static func configure(_ configuration: URLSessionConfiguration) {
    lock.lock()
    defer { lock.unlock() }
    if isEnabled {
      // Fail closed while authorization/startup/reconnect is incomplete.
      let blocked = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: 9))
      configuration.proxyConfigurations = [proxy ?? blocked]
    }
  }

  static func install(_ value: ProxyConfiguration?) async {
    await MainActor.run {
      lock.lock()
      proxy = value
      lock.unlock()
      if let rebuildSession {
        rebuildSession()
      } else {
        NotificationCenter.default.post(name: transportChanged, object: nil)
      }
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.immich/tailnet", binaryMessenger: registrar.messenger())
    let instance = TailnetPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: Self.transportChanged, object: nil)
    Self.startPathMonitor()
  }

  private static func startPathMonitor() {
    lock.lock()
    guard !monitoring else { lock.unlock(); return }
    monitoring = true
    lock.unlock()
    monitor.pathUpdateHandler = { path in
      let signature = "\(path.status)-\(path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map { $0.name }.sorted())-\(EmbeddedLocalRoute.fingerprint())"
      Task { @MainActor in
        let previous = Self.previousPath
        Self.previousPath = signature
        guard previous != nil, previous != signature, path.status == .satisfied else { return }
        Self.scheduleRecovery()
      }
    }
    monitor.start(queue: DispatchQueue(label: "immich.tailnet.path"))
  }

  @MainActor private static func scheduleRecovery() {
    recoveryTask?.cancel()
    guard isEnabled, UIApplication.shared.applicationState == .active else { return }
    recoveryTask = Task { @MainActor in
      do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
      guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
      try? await controller.checkLoopback()
    }
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func changed() { channel.invokeMethod("transportChanged", arguments: nil) }

  @MainActor public func applicationDidBecomeActive(_ application: UIApplication) {
    Self.recoveryWindow.end()
    if Self.graceTask != .invalid {
      application.endBackgroundTask(Self.graceTask)
      Self.graceTask = .invalid
    }
    guard Self.isEnabled else { return }
    Self.scheduleRecovery()
  }

  @MainActor public func applicationDidEnterBackground(_ application: UIApplication) {
    Self.recoveryTask?.cancel()
    guard Self.isEnabled, Self.graceTask == .invalid else { return }
    let epoch = Self.recoveryWindow.begin()
    // A legitimate, finite UIKit task for finishing current file transfers.
    // iOS owns the budget. No background modes, timers, audio or VPN workaround.
    Self.graceTask = application.beginBackgroundTask(withName: "Finish Immich transfers") {
      guard Self.recoveryWindow.expire(epoch) else { return }
      Self.expireTransfers?()
      application.endBackgroundTask(Self.graceTask)
      Self.graceTask = .invalid
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task {
      do {
        let response: Any?
        switch call.method {
        case "enabled": response = Self.isEnabled
        case "releaseClientPointer":
          guard let pointer = (call.arguments as? [String: Any])?["pointer"] as? NSNumber else {
            throw TailnetFailure.invalidState
          }
          Self.releaseSessionPointer?(pointer.int64Value)
          response = nil
        case "confirmSessionPointer":
          guard let pointer = (call.arguments as? [String: Any])?["pointer"] as? NSNumber else {
            throw TailnetFailure.invalidState
          }
          Self.confirmSessionPointer?(pointer.int64Value)
          response = nil
        case "prepare":
          if Self.isEnabled {
            guard await MainActor.run(body: { UIApplication.shared.applicationState != .background }) else { throw TailnetFailure.disabled }
            try await Self.controller.prepare()
          }
          response = nil
        case "select":
          guard let args = call.arguments as? [String: Any],
                let mode = EmbeddedNetworkMode(rawValue: args["mode"] as? String ?? "") else {
            throw TailnetFailure.invalidState
          }
          try await Self.controller.select(mode)
          response = nil
        case "configuration":
          response = try await Self.controller.configuration()
        case "saveConfiguration":
          guard let args = call.arguments as? [String: Any] else { throw TailnetFailure.invalidState }
          try await Self.controller.saveConfiguration(args)
          response = nil
        case "enable":
          try await Self.controller.select(.tailscale)
          response = nil
        case "disable":
          try await Self.controller.select(.none)
          response = nil
        case "login":
          guard Self.isEnabled else { throw TailnetFailure.disabled }
          try await Self.controller.login()
          response = nil
        case "reconnect":
          guard Self.isEnabled else { throw TailnetFailure.disabled }
          try await Self.controller.reconnect()
          response = nil
        case "logout":
          try await Self.controller.logout()
          response = nil
        case "status":
          let arguments = call.arguments as? [String: Any]
          if await MainActor.run(body: { UIApplication.shared.applicationState == .background }) {
            response = ["mode": Self.mode.rawValue, "enabled": Self.isEnabled, "state": "Suspended", "targetRoute": "Unlinked"]
            break
          }
          response = try await Self.controller.status(targetHost: arguments?["serverHost"] as? String ?? Self.serverHost?())
        default:
          await MainActor.run { result(FlutterMethodNotImplemented) }
          return
        }
        await MainActor.run { result(response) }
      } catch {
        // Never include Go errors, auth URLs, node keys, or SOCKS credentials in logs.
        await MainActor.run {
          result(FlutterError(code: "TAILNET_UNAVAILABLE", message: "Network unavailable. Check the selected transport and its configuration.", details: nil))
        }
      }
    }
  }
}

