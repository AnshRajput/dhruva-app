import Flutter
import UIKit
import UniformTypeIdentifiers

/// Channel `app.dhruva/connectors` on iOS (Dart: lib/data/connectors/
/// system_sources.dart). iOS provides: the folder grant (UIDocumentPicker +
/// a persisted security-scoped bookmark), charging state and the app-settings
/// deep link. Calendar goes through the device_calendar_plus plugin and
/// notifications are unsupported on iOS, so those methods are not implemented
/// here (the Dart side never calls them on iOS).
public class DhruvaConnectorsPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pendingPick: FlutterResult?
  private let worker = DispatchQueue(label: "app.dhruva.connectors", qos: .utility)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "app.dhruva/connectors", binaryMessenger: registrar.messenger())
    let instance = DhruvaConnectorsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.modelImport = ModelImport(messenger: registrar.messenger())
  }

  /// Sideloaded-GGUF picker + streaming copy (channel `app.dhruva/model_import`).
  private var modelImport: ModelImport?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "folder.pick":
      pick(result)
    case "folder.reachable":
      worker.async { let ok = FolderGrant.reachable(); DispatchQueue.main.async { result(ok) } }
    case "folder.list":
      let cap = min(max((args?["maxFiles"] as? Int) ?? 2000, 1), 2000)
      worker.async {
        let out = FolderGrant.list(maxFiles: cap)
        DispatchQueue.main.async { result(out) }
      }
    case "folder.fetch":
      guard let entry = args?["entryId"] as? String, !entry.isEmpty,
        let dest = args?["dest"] as? String, !dest.isEmpty
      else {
        result(FlutterError(code: "bad_args", message: "Missing arguments.", details: nil))
        return
      }
      let maxBytes = (args?["maxBytes"] as? Int) ?? 0
      worker.async {
        do {
          try FolderGrant.fetch(entry: entry, dest: dest, maxBytes: maxBytes)
          DispatchQueue.main.async { result(nil) }
        } catch let e as FolderGrant.Failure {
          DispatchQueue.main.async {
            result(FlutterError(code: e.code, message: e.message, details: nil))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "unreadable", message: "Could not read the file.", details: nil))
          }
        }
      }
    case "folder.release":
      FolderGrant.release()
      result(nil)
    case "power.charging":
      UIDevice.current.isBatteryMonitoringEnabled = true
      let s = UIDevice.current.batteryState
      result(s == .charging || s == .full)
    case "app.settings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: picker

  private func pick(_ result: @escaping FlutterResult) {
    guard let top = Self.topViewController() else {
      result(FlutterError(code: "no_activity", message: "Open the app to choose a folder.", details: nil))
      return
    }
    pendingPick?(nil)
    pendingPick = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.allowsMultipleSelection = false
    picker.delegate = self
    top.present(picker, animated: true)
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let r = pendingPick
    pendingPick = nil
    guard let url = urls.first else {
      r?(nil)
      return
    }
    let granted = url.startAccessingSecurityScopedResource()
    defer { if granted { url.stopAccessingSecurityScopedResource() } }
    do {
      try FolderGrant.save(url: url)
      r?(["id": FolderGrant.grantId, "name": url.lastPathComponent])
    } catch {
      r?(FlutterError(code: "failed", message: "Could not keep access to that folder.", details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
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

/// One granted folder, persisted as a security-scoped bookmark in Application
/// Support (excluded from backup by the app's BackupExclusion).
///
/// Safety: listing only descends real directories under the root (symlinks are
/// skipped, never followed, depth and count are capped); fetching re-resolves
/// the entry under the root, refuses `..` segments, symlinks and anything whose
/// resolved path leaves the root, and the copy destination must be inside this
/// app's caches/tmp; reads stop at maxBytes.
enum FolderGrant {
  static let grantId = "ios-folder-bookmark"
  private static let extensions: Set<String> = ["txt", "md", "markdown", "pdf"]
  private static let maxDepth = 12

  struct Failure: Error {
    let code: String
    let message: String
  }

  private static var bookmarkURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("connectors", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("folder_bookmark.bin")
  }

  static func save(url: URL) throws {
    let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    try data.write(to: bookmarkURL, options: [.atomic, .completeFileProtection])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var file = bookmarkURL
    try? file.setResourceValues(values)
  }

  static func release() {
    try? FileManager.default.removeItem(at: bookmarkURL)
  }

  /// The granted folder, with security scope started. Call `stop` when done.
  private static func open() -> (url: URL, stop: () -> Void)? {
    guard let data = try? Data(contentsOf: bookmarkURL) else { return nil }
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    let started = url.startAccessingSecurityScopedResource()
    if stale, let fresh = try? url.bookmarkData() {
      try? fresh.write(to: bookmarkURL, options: [.atomic, .completeFileProtection])
    }
    return (url, { if started { url.stopAccessingSecurityScopedResource() } })
  }

  static func reachable() -> Bool {
    guard let g = open() else { return false }
    defer { g.stop() }
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: g.url.path, isDirectory: &isDir) && isDir.boolValue
  }

  static func list(maxFiles: Int) -> [[String: Any]] {
    guard let g = open() else { return [] }
    defer { g.stop() }
    let root = g.url.resolvingSymlinksInPath()
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
    ]
    guard
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var out: [[String: Any]] = []
    for case let item as URL in walker {
      if out.count >= maxFiles { break }
      guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
      if v.isSymbolicLink == true {
        walker.skipDescendants()
        continue
      }
      if v.isDirectory == true {
        if walker.level > maxDepth { walker.skipDescendants() }
        continue
      }
      guard v.isRegularFile == true, extensions.contains(item.pathExtension.lowercased()) else { continue }
      guard let rel = relativePath(of: item, under: root) else { continue }
      out.append([
        "id": rel,
        "name": item.lastPathComponent,
        "size": v.fileSize ?? 0,
        "modified": Int((v.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000),
      ])
    }
    return out
  }

  static func fetch(entry: String, dest: String, maxBytes: Int) throws {
    guard let g = open() else {
      throw Failure(code: "unreadable", message: "The folder is no longer available.")
    }
    defer { g.stop() }
    let root = g.url.resolvingSymlinksInPath()
    if entry.split(separator: "/").contains("..") || entry.hasPrefix("/") {
      throw Failure(code: "outside_grant", message: "That file is not inside the chosen folder.")
    }
    let candidate = root.appendingPathComponent(entry)
    if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
      throw Failure(code: "outside_grant", message: "That file is not inside the chosen folder.")
    }
    let resolved = candidate.resolvingSymlinksInPath()
    guard relativePath(of: resolved, under: root) != nil else {
      throw Failure(code: "outside_grant", message: "That file is not inside the chosen folder.")
    }
    let target = URL(fileURLWithPath: dest).standardizedFileURL
    let allowed = [FileManager.default.temporaryDirectory]
      + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    guard
      allowed.contains(where: {
        target.resolvingSymlinksInPath().path.hasPrefix($0.resolvingSymlinksInPath().path + "/")
          || target.path.hasPrefix($0.path + "/")
      })
    else { throw Failure(code: "bad_dest", message: "Cannot copy outside the app cache.") }
    try? FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

    guard let input = try? FileHandle(forReadingFrom: resolved) else {
      throw Failure(code: "unreadable", message: "Could not open the file.")
    }
    defer { try? input.close() }
    FileManager.default.createFile(atPath: target.path, contents: nil)
    guard let output = try? FileHandle(forWritingTo: target) else {
      throw Failure(code: "unreadable", message: "Could not write the copy.")
    }
    defer { try? output.close() }
    var written = 0
    do {
      while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
        written += chunk.count
        if written > maxBytes {
          try? FileManager.default.removeItem(at: target)
          throw Failure(code: "too_large", message: "File is larger than the limit.")
        }
        try output.write(contentsOf: chunk)
      }
    } catch let e as Failure {
      throw e
    } catch {
      try? FileManager.default.removeItem(at: target)
      throw Failure(code: "unreadable", message: "Could not read the file.")
    }
  }

  /// `item` relative to `root`, or nil when it is not strictly inside it.
  private static func relativePath(of item: URL, under root: URL) -> String? {
    let r = root.resolvingSymlinksInPath().path
    let p = item.resolvingSymlinksInPath().path
    guard p.hasPrefix(r + "/") else { return nil }
    return String(p.dropFirst(r.count + 1))
  }
}
