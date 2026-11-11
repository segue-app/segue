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
  @Published var liked = false

  /// Line of lyrics being sung now ("" when none).
  @Published var lyric = ""

  /// Set when the music plays on another device ("на iPhone").
  @Published var device = ""

  /// 0…1, and whether the volume HUD shows (while scrolling).
  @Published var volume: Double = 1
  @Published var showVolume = false

  /// -1 / +1 while a two-finger swipe skips, for a nudge animation.
  @Published var swipe: CGFloat = 0

  var open: Bool { expanded || hovering }
  var visible: Bool { enabled && hasTrack }

  /// Size of the black shape right now.
  var shapeSize: CGSize {
    if !visible { return CGSize(width: notchWidth, height: notchHeight) }
    if open {
      return CGSize(width: 440, height: notchHeight + (lyric.isEmpty ? 142 : 170))
    }
    // Collapsed: a little wider than the notch, cover left, bars right.
    return CGSize(width: notchWidth + 84, height: notchHeight)
  }

  /// Position at `positionAt`, moving on while playing.
  @Published var position: Double = 0
  @Published var duration: Double = 0
  @Published var positionAt = Date()

  var notchWidth: CGFloat = 190
  var notchHeight: CGFloat = 32

  func seconds(at now: Date) -> Double {
    let p = position + (playing ? now.timeIntervalSince(positionAt) : 0)
    return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
  }

  func progress(at now: Date) -> Double {
    guard duration > 0 else { return 0 }
    return seconds(at: now) / duration
  }

  /// Sends an action back to the app: toggle, next, prev, like, open,
  /// seek (seconds), volume (0…1).
  var command: (String, Double?) -> Void = { _, _ in }
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
    model.command = { [weak self] op, value in
      if op == "open" {
        // Bring Segue forward; Flutter then opens the full player.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0 is MainFlutterWindow }?.makeKeyAndOrderFront(nil)
      }
      var args: [String: Any] = ["op": op]
      if let v = value { args["value"] = v }
      self?.channel.invokeMethod("command", arguments: args)
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
    host.onScroll = { [weak self] e in self?.scrolled(e) }
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
      model.liked = a["liked"] as? Bool ?? false
      model.device = a["device"] as? String ?? ""
      if !model.showVolume, let v = a["volume"] as? Double { model.volume = v }
      loadArtwork(a["artwork"] as? String ?? "")
      if !currentOpen { place() }
      // A new song once it actually plays: open for a moment to show it.
      if !title.isEmpty && model.playing && title != lastTitle {
        lastTitle = title
        peek()
      }
    case "expand":
      // Keeps the island open (screenshots, tests).
      peekWork?.cancel()
      withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
        model.expanded = a["value"] as? Bool ?? false
      }
    case "lyric":
      withAnimation(.easeOut(duration: 0.3)) {
        model.lyric = a["line"] as? String ?? ""
      }
      if currentOpen { place() }
    default:
      break
    }
  }

  // Scroll up/down over the notch: volume. Two-finger swipe sideways:
  // next / previous track.
  private var swipeAccum: CGFloat = 0
  private var swipeDone = false
  private var volumeWork: DispatchWorkItem?

  private func scrolled(_ e: NSEvent) {
    let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
    if e.phase == .began { swipeAccum = 0; swipeDone = false }
    if abs(dx) > abs(dy) {
      guard e.hasPreciseScrollingDeltas, !swipeDone else { return }
      swipeAccum += dx
      if abs(swipeAccum) > 70 {
        swipeDone = true
        let next = swipeAccum < 0
        model.command(next ? "next" : "prev", nil)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
          model.swipe = next ? -1 : 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self?.model.swipe = 0
          }
        }
      }
      return
    }
    let step = e.hasPreciseScrollingDeltas ? dy / 400 : dy / 25
    let v = min(max(model.volume + Double(step), 0), 1)
    model.volume = v
    model.showVolume = true
    model.command("volume", v)
    volumeWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      withAnimation(.easeOut(duration: 0.3)) { self?.model.showVolume = false }
    }
    volumeWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
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
  var onScroll: (NSEvent) -> Void = { _ in }
  private var area: NSTrackingArea?

  override func scrollWheel(with event: NSEvent) { onScroll(event) }

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
        .offset(x: model.swipe * 6)
      Spacer()
      if model.showVolume {
        // Volume while scrolling over the notch.
        HStack(spacing: 5) {
          Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule().fill(model.accent).frame(width: 30 * model.volume)
          }
          .frame(width: 30, height: 4)
        }
        .transition(.opacity)
      } else {
        Bars(playing: model.playing, color: model.accent)
          .frame(width: 20, height: 14)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 14)
    .frame(height: model.notchHeight)
  }

  private var expanded: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: model.notchHeight + 6)
      HStack(spacing: 14) {
        Button(action: { model.command("open", nil) }) {
          cover
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: model.accent.opacity(0.45), radius: 10)
        }
        .buttonStyle(.plain)
        .help("Открыть Segue")
        .offset(x: model.swipe * 14)
        VStack(alignment: .leading, spacing: 3) {
          Text(model.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
          HStack(spacing: 5) {
            Text(model.artist)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.white.opacity(0.6))
              .lineLimit(1)
            if !model.device.isEmpty {
              // Playing on another of your devices.
              HStack(spacing: 3) {
                Image(systemName: "iphone").font(.system(size: 9, weight: .bold))
                Text("на \(model.device)").font(.system(size: 10, weight: .bold))
              }
              .foregroundColor(model.accent)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(Capsule().fill(model.accent.opacity(0.18)))
            }
          }
        }
        Spacer(minLength: 0)
        Button(action: { model.command("like", nil) }) {
          Image(systemName: model.liked ? "heart.fill" : "heart")
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(model.liked ? Color(red: 1, green: 0.42, blue: 0.5) : .white.opacity(0.75))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      Seeker(model: model).padding(.top, 10)
      if !model.lyric.isEmpty {
        Text(model.lyric)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(model.accent)
          .lineLimit(1)
          .frame(maxWidth: .infinity)
          .padding(.top, 8)
          .id(model.lyric)
          .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity))
      }
      HStack(spacing: 18) {
        button("backward.fill", "prev", size: 16)
        button(model.playing ? "pause.fill" : "play.fill", "toggle", size: 24)
        button("forward.fill", "next", size: 16)
      }
      .padding(.top, 4)
    }
    .padding(.horizontal, 22)
    .padding(.bottom, 10)
  }

  private func button(_ symbol: String, _ op: String, size: CGFloat) -> some View {
    Button(action: { model.command(op, nil) }) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 38, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Progress you can click or drag to seek, with the times on both sides.
struct Seeker: View {
  @ObservedObject var model: NotchModel
  @State private var drag: Double?

  private func time(_ s: Double) -> String {
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
      let f = drag ?? model.progress(at: ctx.date)
      HStack(spacing: 8) {
        Text(time(drag.map { $0 * model.duration } ?? model.seconds(at: ctx.date)))
          .frame(width: 34, alignment: .trailing)
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.15))
            Capsule().fill(model.accent).frame(width: g.size.width * f)
          }
          .frame(height: drag == nil ? 4 : 6)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { v in drag = min(max(v.location.x / g.size.width, 0), 1) }
              .onEnded { v in
                let x = min(max(v.location.x / g.size.width, 0), 1)
                model.command("seek", x * model.duration)
                model.position = x * model.duration
                model.positionAt = Date()
                drag = nil
              })
        }
        .frame(height: 14)
        Text(time(model.duration)).frame(width: 34, alignment: .leading)
      }
      .font(.system(size: 10, weight: .medium).monospacedDigit())
      .foregroundColor(.white.opacity(0.55))
    }
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
