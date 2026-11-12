// SegueUpdater: installs a new Segue release on macOS.
//
// Segue runs in the App Sandbox, and everything a sandboxed app downloads
// is marked as "from the internet": macOS then refuses to open the new,
// un-notarized app. This small helper lives inside Segue.app, is started
// through Launch Services (so it isn't sandboxed), and does the update the
// way updaters outside the App Store do: download, quit Segue, swap the
// app in place, start the new one.
//
// Arguments: <zip url> <path to Segue.app> <pid of Segue> <version>
//            <title> <downloading> <installing> <failed>   (localized)
import AppKit

/// ~/Library/Logs/Segue/updater.log: what happened, for when it doesn't work.
func log(_ line: String) {
  let dir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Segue")
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let file = dir.appendingPathComponent("updater.log")
  let text = "\(Date()) \(line)\n"
  if let h = try? FileHandle(forWritingTo: file) {
    h.seekToEndOfFile()
    h.write(text.data(using: .utf8)!)
    try? h.close()
  } else {
    try? text.write(to: file, atomically: true, encoding: .utf8)
  }
}

struct Texts {
  let title, downloading, installing, failed: String
}

struct Job {
  let zipURL: URL
  let appURL: URL
  let pid: Int32
  let version: String
  let texts: Texts

  /// segue-updater://install?url=…&app=…&pid=…&v=…&t=…&d=…&i=…&f=…
  /// (how a sandboxed Segue starts us: Launch Services drops arguments
  /// from sandboxed apps, but hands over a URL).
  init?(url: URL) {
    guard let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
    guard let zip = v("url").flatMap(URL.init(string:)), let app = v("app"),
      let pid = v("pid").flatMap(Int32.init)
    else { return nil }
    self.init(
      zipURL: zip, appURL: URL(fileURLWithPath: app), pid: pid, version: v("v") ?? "",
      texts: Texts(
        title: v("t") ?? "Segue", downloading: v("d") ?? "Downloading",
        installing: v("i") ?? "Installing…", failed: v("f") ?? "Update failed"))
  }

  init(zipURL: URL, appURL: URL, pid: Int32, version: String, texts: Texts) {
    self.zipURL = zipURL
    self.appURL = appURL
    self.pid = pid
    self.version = version
    self.texts = texts
  }

  /// From the command line (testing): <zip url> <app> <pid> <version> <4 texts>.
  init?(arguments a: [String]) {
    guard a.count >= 9, let zip = URL(string: a[1]), let pid = Int32(a[3]) else { return nil }
    self.init(
      zipURL: zip, appURL: URL(fileURLWithPath: a[2]), pid: pid, version: a[4],
      texts: Texts(title: a[5], downloading: a[6], installing: a[7], failed: a[8]))
  }
}

final class Updater: NSObject, NSApplicationDelegate, URLSessionDownloadDelegate {
  var job: Job?
  var zipURL: URL { job!.zipURL }
  var appURL: URL { job!.appURL }
  var pid: Int32 { job!.pid }
  var version: String { job!.version }
  var texts: Texts { job!.texts }

  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 112),
    styleMask: [.titled], backing: .buffered, defer: false)
  let label = NSTextField(labelWithString: "")
  let bar = NSProgressIndicator()
  var session: URLSession!

  func applicationDidFinishLaunching(_ n: Notification) {
    if let j = Job(arguments: CommandLine.arguments) {
      start(j)
    } else {
      // Waiting for the URL; nothing comes within a few seconds: quit.
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        if self.job == nil {
          log("started without a job")
          NSApp.terminate(nil)
        }
      }
    }
  }

  func application(_ app: NSApplication, open urls: [URL]) {
    guard job == nil, let u = urls.first, let j = Job(url: u) else { return }
    start(j)
  }

  func start(_ j: Job) {
    job = j
    log("start: \(version) from \(zipURL) into \(appURL.path), pid \(pid), home \(NSHomeDirectory())")
    window.title = texts.title
    let box = NSView(frame: window.contentView!.bounds)
    label.frame = NSRect(x: 20, y: 62, width: 320, height: 20)
    bar.frame = NSRect(x: 20, y: 32, width: 320, height: 20)
    bar.isIndeterminate = false
    bar.minValue = 0
    bar.maxValue = 1
    box.addSubview(label)
    box.addSubview(bar)
    window.contentView = box
    window.center()
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    label.stringValue = "\(texts.downloading) \(version)…"
    session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    session.downloadTask(with: zipURL).resume()
  }

  func urlSession(
    _ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
    totalBytesWritten done: Int64, totalBytesExpectedToWrite total: Int64
  ) {
    if total > 0 { bar.doubleValue = Double(done) / Double(total) }
  }

  func urlSession(
    _ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo tmp: URL
  ) {
    let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    log("downloaded: HTTP \(code)")
    guard code == 200 else { return fail("HTTP \(code)") }
    let fm = FileManager.default
    let work = fm.temporaryDirectory.appendingPathComponent("segue-update-\(UUID().uuidString)")
    do {
      try fm.createDirectory(at: work, withIntermediateDirectories: true)
      let zip = work.appendingPathComponent("segue.zip")
      try fm.moveItem(at: tmp, to: zip)
      label.stringValue = texts.installing
      bar.isIndeterminate = true
      bar.startAnimation(nil)
      DispatchQueue.global().async { self.install(zip: zip, work: work) }
    } catch {
      fail(error.localizedDescription)
    }
  }

  func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
    if let e = e { fail(e.localizedDescription) }
  }

  func run(_ tool: String, _ a: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = a
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
  }

  func install(zip: URL, work: URL) {
    let fm = FileManager.default
    let unpacked = work.appendingPathComponent("new")
    guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else {
      return DispatchQueue.main.async { self.fail("unzip") }
    }
    let newApp = unpacked.appendingPathComponent("Segue.app")
    guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/Segue").path)
    else { return DispatchQueue.main.async { self.fail("no Segue.app in the archive") } }
    // Our own download carries no quarantine, but make sure.
    _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

    // Segue quits (it saves as it goes), then the app is swapped.
    if let app = NSRunningApplication(processIdentifier: pid) {
      DispatchQueue.main.sync { _ = app.terminate() }
      for _ in 0..<100 where !app.isTerminated { usleep(100_000) }
      if !app.isTerminated { _ = app.forceTerminate() }
      usleep(300_000)
    }
    do {
      let old = work.appendingPathComponent("old.app")
      if fm.fileExists(atPath: appURL.path) {
        try fm.moveItem(at: appURL, to: old)
      }
      do {
        try fm.moveItem(at: newApp, to: appURL)
      } catch {
        // Put the old one back rather than leave nothing.
        if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: appURL) }
        throw error
      }
      try? fm.removeItem(at: old)
    } catch {
      return DispatchQueue.main.async { self.fail(error.localizedDescription, relaunch: true) }
    }
    try? fm.removeItem(at: zip)
    log("replaced, starting the new version")
    DispatchQueue.main.async {
      let cfg = NSWorkspace.OpenConfiguration()
      NSWorkspace.shared.openApplication(at: self.appURL, configuration: cfg) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
      }
    }
  }

  func fail(_ why: String, relaunch: Bool = false) {
    log("failed: \(why)")
    bar.stopAnimation(nil)
    let alert = NSAlert()
    alert.messageText = texts.failed
    alert.informativeText = why
    alert.alertStyle = .warning
    alert.runModal()
    if relaunch {
      NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, _ in
        DispatchQueue.main.async { NSApp.terminate(nil) }
      }
    } else {
      NSApp.terminate(nil)
    }
  }
}

let app = NSApplication.shared
let delegate = Updater()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
