import native_video_player
import ImmichTailnet
import background_downloader

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notification
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    SwiftNativeVideoPlayerPlugin.cookieStorage = URLSessionManager.cookieStorage
    UrlSessionDelegate.configurationFactory = { identifier in
      let configuration = TailnetPlugin.isEnabled ? URLSessionConfiguration.default
        : URLSessionConfiguration.background(withIdentifier: identifier)
      URLSessionManager.configure(configuration)
      return configuration
    }
    TailnetPlugin.serverHost = {
      let saved = UserDefaults.group.stringArray(forKey: SERVER_URLS_KEY) ?? []
      return saved.first.flatMap { URL(string: $0)?.host }
    }
    TailnetPlugin.rebuildSession = {
      URLSessionManager.shared.recreateSession()
      UrlSessionDelegate.resetSession()
    }
    TailnetPlugin.expireTransfers = {
      URLSessionManager.shared.session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
      UrlSessionDelegate.resetSession()
    }
    URLSessionManager.patchBackgroundDownloader()
    BackgroundWorkerApiImpl.registerBackgroundWorkers()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    AppDelegate.registerPlugins(with: engineBridge.pluginRegistry, messenger: messenger)
  }

  public static func registerPlugins(with registry: FlutterPluginRegistry, messenger: FlutterBinaryMessenger) {
    TailnetPlugin.register(with: registry.registrar(forPlugin: "ImmichTailnet")!)
    NativeSyncApiImpl.register(with: registry.registrar(forPlugin: NativeSyncApiImpl.name)!)
    PermissionApiSetup.setUp(binaryMessenger: messenger, api: PermissionApiImpl())
    LocalImageApiSetup.setUp(binaryMessenger: messenger, api: LocalImageApiImpl())
    RemoteImageApiSetup.setUp(binaryMessenger: messenger, api: RemoteImageApiImpl())
    BackgroundWorkerFgHostApiSetup.setUp(binaryMessenger: messenger, api: BackgroundWorkerApiImpl())
    ConnectivityApiSetup.setUp(binaryMessenger: messenger, api: ConnectivityApiImpl())
    NetworkApiSetup.setUp(binaryMessenger: messenger, api: NetworkApiImpl())
  }

  public static func cancelPlugins(with engine: FlutterEngine) {
    (engine.valuePublished(byPlugin: NativeSyncApiImpl.name) as? NativeSyncApiImpl)?.detachFromEngine()
  }
}
