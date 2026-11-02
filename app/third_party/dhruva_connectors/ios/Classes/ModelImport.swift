import Flutter
import UIKit
import UniformTypeIdentifiers

/// Channel `app.dhruva/model_import` on iOS (Dart: lib/data/downloads/
/// model_file_channel.dart). Picks a model file with UIDocumentPicker (opened
/// in place, not as a copy) and stream-copies it into app storage in 1 MiB
/// chunks, so a multi-GB GGUF never sits in memory and is never copied twice.
/// Methods: pick | copy | cancel. Errors: no_space, cancelled, unreadable,
/// no_activity, failed.
final class ModelImport: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "app.dhruva.model_import", qos: .utility)
  private var pendingPick: FlutterResult?
  /// The picked file, security-scoped until the copy finishes or a new pick starts.
  private var picked: URL?
  private let cancelled = CancelFlag()

  private final class CancelFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
  }

  private struct Failure: Error {
    let code: String
    let message: String
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "app.dhruva/model_import", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result)
    case "copy":
      let args = call.arguments as? [String: Any]
      guard let uri = args?["uri"] as? String, let dest = args?["dest"] as? String,
        !dest.isEmpty, let url = picked, url.absoluteString == uri
      else {
        result(FlutterError(code: "unreadable", message: "Pick the file again.", details: nil))
        return
      }
      copy(url: url, dest: URL(fileURLWithPath: dest), result)
    case "cancel":
      cancelled.set(true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: picker

  private func pick(_ result: @escaping FlutterResult) {
    guard let top = Self.topViewController() else {
      result(FlutterError(code: "no_activity", message: "Open the app to choose a file.", details: nil))
      return
    }
    pendingPick?(nil)
    pendingPick = result
    releasePicked()
    // GGUF has no system UTI: accept its extension, and any data as the fallback.
    var types: [UTType] = [.data]
    if let gguf = UTType(filenameExtension: "gguf") { types.insert(gguf, at: 0) }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let r = pendingPick
    pendingPick = nil
    guard let url = urls.first else {
      r?(nil)
      return
    }
    guard url.startAccessingSecurityScopedResource() else {
      r?(FlutterError(code: "unreadable", message: "Could not read that file.", details: nil))
      return
    }
    picked = url
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    r?(["uri": url.absoluteString, "name": url.lastPathComponent, "size": size])
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
  }

  private func releasePicked() {
    picked?.stopAccessingSecurityScopedResource()
    picked = nil
  }

  // MARK: copy

  private func copy(url: URL, dest: URL, _ result: @escaping FlutterResult) {
    cancelled.set(false)
    let flag = cancelled
    worker.async { [weak self] in
      var copied = 0
      do {
        let total = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard let input = try? FileHandle(forReadingFrom: url) else {
          throw Failure(code: "unreadable", message: "Could not open that file.")
        }
        defer { try? input.close() }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let output = try FileHandle(forWritingTo: dest)
        defer { try? output.close() }
        var lastReport = Date.distantPast
        while true {
          if flag.isSet { throw Failure(code: "cancelled", message: "Import cancelled.") }
          // autoreleasepool: each 1 MiB Data is freed per iteration, not at the end.
          let done: Bool = try autoreleasepool {
            guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { return true }
            try output.write(contentsOf: chunk)
            copied += chunk.count
            return false
          }
          if Date().timeIntervalSince(lastReport) >= 0.1 || done {
            lastReport = Date()
            let args: [String: Int] = ["copied": copied, "total": max(total, copied)]
            DispatchQueue.main.async { self?.channel.invokeMethod("progress", arguments: args) }
          }
          if done { break }
        }
        DispatchQueue.main.async {
          self?.releasePicked()
          result(copied)
        }
      } catch {
        try? FileManager.default.removeItem(at: dest)
        let f = Self.map(error)
        DispatchQueue.main.async {
          self?.releasePicked()
          result(FlutterError(code: f.code, message: f.message, details: nil))
        }
      }
    }
  }

  private static func map(_ error: Error) -> Failure {
    if let f = error as? Failure { return f }
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
      return Failure(code: "no_space", message: "Not enough free space.")
    }
    if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) {
      return Failure(code: "no_space", message: "Not enough free space.")
    }
    return Failure(code: "failed", message: "Could not copy the file.")
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
