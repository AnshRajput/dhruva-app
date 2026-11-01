import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceHealthChannel") {
      DeviceHealthChannel.register(with: registrar.messenger())
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
