import Cocoa
import FlutterMacOS
import Combine
import SwiftUI

class MainFlutterWindow: NSWindow {
  private var notch: NotchController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // "Living notch": now playing around the MacBook's camera notch.
    let channel = FlutterMethodChannel(
      name: "fm.segue/notch",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    notch = NotchController(channel: channel)

    super.awakeFromNib()
  }
}

// MARK: - Model

/// What the notch shows; set from Flutter over the method channel.
final class NotchModel: ObservableObject {
  @Published var title = ""
  @Published var artist = ""
  @Published var artwork: NSImage?
  @Published var playing = false
  @Published var accent = Color(red: 1, green: 0.6, blue: 0.46)
  @Published var hasTrack = false
  @Published var expanded = false
  @Published var hovering = false
  @Published var enabled = true

  var open: Bool { expanded || hovering }
  var visible: Bool { enabled && hasTrack }

  /// Size of the black shape right now.
  var shapeSize: CGSize {
    if !visible { return CGSize(width: notchWidth, height: notchHeight) }
    if open { return CGSize(width: 420, height: notchHeight + 104) }
    // Collapsed: a little wider than the notch, cover left, bars right.
    return CGSize(width: notchWidth + 84, height: notchHeight)
  }

  /// Position at `positionAt`, moving on while playing.
  @Published var position: Double = 0
  @Published var duration: Double = 0
  @Published var positionAt = Date()

  var notchWidth: CGFloat = 190
  var notchHeight: CGFloat = 32

  func progress(at now: Date) -> Double {
    guard duration > 0 else { return 0 }
    let p = position + (playing ? now.timeIntervalSince(positionAt) : 0)
    return min(max(p / duration, 0), 1)
  }

  /// Sends play/pause/next/prev back to the app.
  var command: (String) -> Void = { _ in }
}

// MARK: - Window

/// A borderless panel over the notch that never takes focus. Clicks on its
/// transparent parts fall through to the menu bar.
final class NotchPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class NotchController {
  private let model = NotchModel()
  private let channel: FlutterMethodChannel
  private var panel: NotchPanel?
  private var lastTitle = ""
  private var peekWork: DispatchWorkItem?
  private var artworkURL = ""
  private var sizing: AnyCancellable?
  private var shrinkWork: DispatchWorkItem?

  /// Room for the expanded island; the visible shape is drawn inside it.
  static let canvas = CGSize(width: 520, height: 200)

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    model.command = { [weak self] op in
      self?.channel.invokeMethod("command", arguments: op)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call)
      result(nil)
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil, queue: .main
    ) { [weak self] _ in self?.place() }
    // The window is only as big as what's visible, so it never catches
    // clicks meant for the menu bar or the tabs below it. It grows before
    // the island opens and shrinks after it has closed.
    sizing = model.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.fit() }
  }

  private var currentOpen = false

  private func fit() {
    guard panel != nil else { return }
    let open = model.open && model.visible
    if open == currentOpen { return }
    currentOpen = open
    shrinkWork?.cancel()
    if open {
      // Exactly the open island: leaving it closes it.
      place()
    } else {
      let work = DispatchWorkItem { [weak self] in self?.place() }
      shrinkWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
  }

  /// The built-in display with a camera notch, if any.
  private static func notchScreen() -> NSScreen? {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
  }

  private func makePanel() {
    guard panel == nil else { return }
    let p = NotchPanel(
      contentRect: NSRect(origin: .zero, size: Self.canvas),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.level = .statusBar + 1
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    p.isMovable = false
    p.hidesOnDeactivate = false
    let host = HoverHostingView(rootView: NotchView(model: model))
    host.onHover = { [weak self] inside in
      withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
        self?.model.hovering = inside
      }
    }
    host.frame = NSRect(origin: .zero, size: Self.canvas)
    p.contentView = host
    panel = p
    place()
  }

  /// Top centre of the notched screen, [size] or just the visible shape.
  private func place(size: CGSize? = nil) {
    guard let p = panel, let screen = Self.notchScreen() else {
      panel?.orderOut(nil)
      return
    }
    let left = screen.auxiliaryTopLeftArea?.width ?? 0
    let right = screen.auxiliaryTopRightArea?.width ?? 0
    model.notchWidth = max(150, screen.frame.width - left - right)
    model.notchHeight = screen.safeAreaInsets.top
    let s = size ?? model.shapeSize
    let f = screen.frame
    p.setFrame(
      NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height,
             width: s.width, height: s.height),
      display: true)
    if model.visible { p.orderFrontRegardless() } else { p.orderOut(nil) }
  }

  private func handle(_ call: FlutterMethodCall) {
    guard let a = call.arguments as? [String: Any] else { return }
    switch call.method {
    case "enabled":
      model.enabled = a["value"] as? Bool ?? true
      if model.enabled { makePanel() } else { panel?.orderOut(nil) }
    case "update":
      guard Self.notchScreen() != nil else { return }
      makePanel()
      let title = a["title"] as? String ?? ""
      model.hasTrack = !title.isEmpty
      model.title = title
      model.artist = a["artist"] as? String ?? ""
      model.playing = a["playing"] as? Bool ?? false
      model.position = (a["position"] as? Double) ?? 0
      model.duration = (a["duration"] as? Double) ?? 0
      model.positionAt = Date()
      if let c = a["accent"] as? Int {
        model.accent = Color(
          red: Double((c >> 16) & 0xff) / 255,
          green: Double((c >> 8) & 0xff) / 255,
          blue: Double(c & 0xff) / 255)
      }
      loadArtwork(a["artwork"] as? String ?? "")
      if !currentOpen { place() }
      // A new song once it actually plays: open for a moment to show it.
      if !title.isEmpty && model.playing && title != lastTitle {
        lastTitle = title
        peek()
      }
    default:
      break
    }
  }

  private func peek() {
    peekWork?.cancel()
    model.expanded = true
    let work = DispatchWorkItem { [weak self] in self?.model.expanded = false }
    peekWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
  }

  private func loadArtwork(_ url: String) {
    guard url != artworkURL else { return }
    artworkURL = url
    if url.isEmpty {
      model.artwork = nil
      return
    }
    if url.hasPrefix("/") || url.hasPrefix("file:") {
      let path = url.hasPrefix("file:") ? (URL(string: url)?.path ?? url) : url
      model.artwork = NSImage(contentsOfFile: path)
      return
    }
    guard let u = URL(string: url) else { return }
    URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
      guard let data = data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async {
        if self?.artworkURL == url { self?.model.artwork = image }
      }
    }.resume()
  }
}

/// Hosting view that sees the mouse even while Segue isn't the active app
/// (SwiftUI's onHover doesn't), and takes the first click on its buttons.
final class HoverHostingView<Content: View>: NSHostingView<Content> {
  var onHover: (Bool) -> Void = { _ in }
  private var area: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let a = area { removeTrackingArea(a) }
    let a = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(a)
    area = a
  }

  override func mouseEntered(with event: NSEvent) { onHover(true) }
  override func mouseExited(with event: NSEvent) { onHover(false) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

/// Notch-coloured shape: flat top that melts into the screen edge, round
/// bottom corners, and small inward curves where it meets the menu bar.
struct NotchShape: Shape {
  var bottomRadius: CGFloat
  var topRadius: CGFloat = 6

  var animatableData: CGFloat {
    get { bottomRadius }
    set { bottomRadius = newValue }
  }

  func path(in r: CGRect) -> Path {
    var p = Path()
    let t = topRadius, b = min(bottomRadius, r.height / 2)
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addQuadCurve(
      to: CGPoint(x: r.minX + t, y: r.minY + t),
      control: CGPoint(x: r.minX + t, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
    p.addQuadCurve(
      to: CGPoint(x: r.minX + t + b, y: r.maxY),
      control: CGPoint(x: r.minX + t, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
    p.addQuadCurve(
      to: CGPoint(x: r.maxX - t, y: r.maxY - b),
      control: CGPoint(x: r.maxX - t, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
    p.addQuadCurve(
      to: CGPoint(x: r.maxX, y: r.minY),
      control: CGPoint(x: r.maxX - t, y: r.minY))
    p.closeSubpath()
    return p
  }
}

struct NotchView: View {
  @ObservedObject var model: NotchModel

  private var open: Bool { model.open }
  private var visible: Bool { model.visible }
  private var size: CGSize { model.shapeSize }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        NotchShape(bottomRadius: open ? 26 : 10)
          .fill(Color.black)
          .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 18, y: 6)
        if visible {
          if open { expanded.transition(.opacity) } else { collapsed.transition(.opacity) }
        }
      }
      .frame(width: size.width, height: size.height)
      .contentShape(NotchShape(bottomRadius: 10))
      .animation(.spring(response: 0.42, dampingFraction: 0.78), value: size)
      .animation(.easeInOut(duration: 0.2), value: open)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var cover: some View {
    Group {
      if let img = model.artwork {
        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
      } else {
        LinearGradient(
          colors: [model.accent, model.accent.opacity(0.4)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    }
  }

  private var collapsed: some View {
    HStack {
      cover
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      Spacer()
      Bars(playing: model.playing, color: model.accent)
        .frame(width: 20, height: 14)
    }
    .padding(.horizontal, 14)
    .frame(height: model.notchHeight)
  }

  private var expanded: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: model.notchHeight)
      HStack(spacing: 14) {
        cover
          .frame(width: 62, height: 62)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: model.accent.opacity(0.45), radius: 10)
        VStack(alignment: .leading, spacing: 3) {
          Text(model.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
          Text(model.artist)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .lineLimit(1)
          TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            GeometryReader { g in
              ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(model.accent)
                  .frame(width: g.size.width * model.progress(at: ctx.date))
              }
            }
            .frame(height: 4)
          }
          .padding(.top, 6)
        }
        HStack(spacing: 4) {
          button("backward.fill", "prev", size: 15)
          button(model.playing ? "pause.fill" : "play.fill", "toggle", size: 22)
          button("forward.fill", "next", size: 15)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
  }

  private func button(_ symbol: String, _ op: String, size: CGFloat) -> some View {
    Button(action: { model.command(op) }) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Little dancing bars in the cover's colour (calm and low when paused).
struct Bars: View {
  var playing: Bool
  var color: Color

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
      let t = ctx.date.timeIntervalSinceReferenceDate
      HStack(alignment: .bottom, spacing: 2.5) {
        ForEach(0..<4) { i in
          let phase = Double(i) * 1.7
          let h = playing
            ? 0.3 + 0.7 * abs(sin(t * (3.2 + Double(i) * 0.9) + phase))
            : 0.18
          Capsule()
            .fill(color)
            .frame(width: 3, height: max(2.5, 14 * h))
        }
      }
      .frame(maxHeight: .infinity, alignment: .center)
    }
  }
}
