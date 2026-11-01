import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackupExclusion.apply()
    PrivacyChannel.installCover()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceHealthChannel") {
      DeviceHealthChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PrivacyChannel") {
      PrivacyChannel.register(with: registrar.messenger())
    }
  }
}

/// Battery & heat guard native side (Dart: core/device_health). Answers
/// `read` with `{battery: Int, charging: Bool, thermal: String}`. The
/// simulator reports battery level -1; Dart treats that as "no reading",
/// never an error.
enum DeviceHealthChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let channel = FlutterMethodChannel(name: "app.dhruva/device_health", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let device = UIDevice.current
      let level = device.batteryLevel  // -1.0 when unavailable
      let state = device.batteryState
      let thermal: String
      switch ProcessInfo.processInfo.thermalState {
      case .nominal: thermal = "nominal"
      case .fair: thermal = "fair"
      case .serious: thermal = "serious"
      case .critical: thermal = "critical"
      @unknown default: thermal = "unknown"
      }
      result([
        "battery": level < 0 ? -1 : Int((level * 100).rounded()),
        "charging": state == .charging || state == .full,
        "thermal": thermal,
      ])
    }
  }
}

/// Backup lockdown (daily-assistant spec B1). Marks the app's data
/// directories (Documents: Drift DB; Application Support: models, flags,
/// later the connector index) `NSURLIsExcludedFromBackupKey` so iCloud and
/// iTunes/Finder backups never contain chats or connector data. The flag on a
/// directory covers everything created inside it later; direct children are
/// marked too as belt and braces. Runs on every launch (cheap, idempotent).
enum BackupExclusion {
  static func apply() {
    let fm = FileManager.default
    let roots: [URL] = [
      fm.urls(for: .documentDirectory, in: .userDomainMask).first,
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
    ].compactMap { $0 }
    for var root in roots {
      try? fm.createDirectory(at: root, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? root.setResourceValues(values)
      let children = (try? fm.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil)) ?? []
      for var child in children {
        try? child.setResourceValues(values)
      }
    }
  }
}

/// "Hide content in app switcher" (Settings > Privacy; Dart: core/privacy).
/// Dart sends `setHideInSwitcher(Bool)`. While enabled, an opaque cover goes
/// over the scene's window as it becomes inactive (that is when iOS takes the
/// app-switcher snapshot) and comes off when it is active again. Uses scene
/// notifications so it needs no override in the Flutter scene delegate.
enum PrivacyChannel {
  static var enabled = false
  private static let coverTag = 0xD40A

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.dhruva/privacy", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setHideInSwitcher" else {
        result(FlutterMethodNotImplemented)
        return
      }
      enabled = (call.arguments as? Bool) ?? false
      result(nil)
    }
  }

  static func installCover() {
    let center = NotificationCenter.default
    center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) {
      note in
      guard enabled, let window = (note.object as? UIWindowScene)?.windows.first,
        window.viewWithTag(coverTag) == nil
      else { return }
      let cover = UIView(frame: window.bounds)
      cover.tag = coverTag
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .systemBackground
      window.addSubview(cover)
    }
    center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) {
      note in
      (note.object as? UIWindowScene)?.windows.forEach {
        $0.viewWithTag(coverTag)?.removeFromSuperview()
      }
    }
  }
}
