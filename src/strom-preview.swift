import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Charts
import UserNotifications

final class StromNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor final class DownloadStatusIndicator {
    private var item: NSStatusItem?
    func update(_ downloads: [TorrentItem], records: [Int32: SavedTorrent]) {
        let active = downloads.filter { !$0.complete && !$0.paused && $0.error.isEmpty && !(records[$0.id]?.paused ?? false) && !(records[$0.id]?.stopped ?? false) }
        guard !active.isEmpty else {
            if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
            return
        }
        if item == nil { item = NSStatusBar.system.statusItem(withLength: 26) }
        let known = active.allSatisfy { $0.size > 0 }
        let total = active.reduce(0.0) { $0 + Double(max(0, $1.size)) }
        let completed = active.reduce(0.0) { $0 + Double(max(0, min($1.done, $1.size))) }
        let fraction = known && total > 0 ? min(1, completed / total) : nil
        let label = fraction.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? "–"
        item?.button?.image = makeImage(fraction: fraction, label: label)
        item?.button?.toolTip = "STRÖM · \(label)"
        item?.button?.setAccessibilityLabel("STRÖM · \(label)")
    }
    private func makeImage(fraction: Double?, label: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 26, height: 22))
        image.lockFocus()
        let center = NSPoint(x: 13, y: 11)
        let track = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 1.5, width: 19, height: 19))
        track.lineWidth = 1.6
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()
        if let fraction, fraction > 0 {
            let progress = NSBezierPath()
            progress.lineWidth = 2.1
            progress.lineCapStyle = .round
            progress.appendArc(withCenter: center, radius: 9.5, startAngle: 90, endAngle: 90 - CGFloat(fraction) * 360, clockwise: true)
            NSColor.black.setStroke()
            progress.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: label.count > 3 ? 6 : 7, weight: .medium), .foregroundColor: NSColor.black]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

@MainActor final class StromAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let downloadStatusIndicator = DownloadStatusIndicator()
    @Published var pendingFiles: [URL] = []
    func application(_ application: NSApplication, open urls: [URL]) { pendingFiles.append(contentsOf: urls.filter(\.isFileURL)) }
}

struct ClearWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isOpaque = false
            view.window?.backgroundColor = .clear
            view.window?.hasShadow = false
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

struct RedAccentMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.178, y: rect.height * 0.765))
        path.addCurve(to: CGPoint(x: rect.width * 0.253, y: rect.height * 0.648), control1: CGPoint(x: rect.width * 0.19, y: rect.height * 0.66), control2: CGPoint(x: rect.width * 0.21, y: rect.height * 0.648))
        path.addCurve(to: CGPoint(x: rect.width * 0.231, y: rect.height * 0.765), control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.715), control2: CGPoint(x: rect.width * 0.245, y: rect.height * 0.765))
        path.closeSubpath()
        return path
    }
}
struct PlotPoint: Identifiable { let id: Int; let speed: Double }
struct GenieEffect: AnimatableModifier {
    var progress: CGFloat
    let x: CGFloat
    let y: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.scaleEffect(x: 1 - progress * 0.9, y: 1 - progress * 0.8, anchor: .bottomLeading)
            .rotation3DEffect(.degrees(Double(progress) * 35), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .offset(x: x * progress, y: y * progress).opacity(1 - Double(progress))
    }
}
final class TitleClickView: NSView {
    var openDetails: () -> Void = {}
    var reveal: () -> Void = {}
    private var pending: DispatchWorkItem?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { pending?.cancel(); pending = nil; reveal(); return }
        pending?.cancel()
        let action = DispatchWorkItem { [weak self] in self?.openDetails() }
        pending = action
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.25, NSEvent.doubleClickInterval), execute: action)
    }
    deinit { pending?.cancel() }
}
struct TitleClickSurface: NSViewRepresentable {
    var openDetails: () -> Void
    var reveal: () -> Void
    func makeNSView(context: Context) -> TitleClickView { TitleClickView() }
    func updateNSView(_ view: TitleClickView, context: Context) { view.openDetails = openDetails; view.reveal = reveal }
}
final class OutsideClickView: NSView {
    var dismiss: () -> Void = {}
    override func mouseDown(with event: NSEvent) { dismiss() }
}
struct OutsideClickSurface: NSViewRepresentable {
    var dismiss: () -> Void
    func makeNSView(context: Context) -> OutsideClickView { OutsideClickView() }
    func updateNSView(_ view: OutsideClickView, context: Context) { view.dismiss = dismiss }
}


// Keep the same engine and window while changing only its presentation and dimensions.
struct WindowSizeController: NSViewRepresentable {
    let compact: Bool
    let count: Int
    final class Coordinator {
        var wasCompact = false
        var previousFrame: NSRect?
        var previousMinSize: NSSize?
        var lastWidth: CGFloat = 0
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let width = CGFloat(max(1, min(4, count))) * 150
            if compact {
                if !coordinator.wasCompact {
                    coordinator.previousFrame = window.frame
                    coordinator.previousMinSize = window.contentMinSize
                    window.contentMinSize = NSSize(width: 150, height: 150)
                    window.isMovableByWindowBackground = true
                    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(kind)?.isHidden = true }
                }
                if !coordinator.wasCompact || coordinator.lastWidth != width {
                    let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                    window.setContentSize(NSSize(width: width, height: 150))
                    window.setFrameTopLeftPoint(topLeft)
                    coordinator.lastWidth = width
                }
            } else if coordinator.wasCompact {
                window.contentMinSize = coordinator.previousMinSize ?? NSSize(width: 780, height: 500)
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(kind)?.isHidden = false }
                if let frame = coordinator.previousFrame { window.setFrame(frame, display: true, animate: true) }
            }
            coordinator.wasCompact = compact
        }
    }
}

struct MiniDisk: View {
    let item: TorrentItem?
    let language: String
    let light: Bool
    let expand: () -> Void
    let formatBytes: (Int64) -> String
    let formatDuration: (Int64) -> String
    @State private var hovering = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.13), lineWidth: 7)
                Circle().trim(from: 0, to: min(1, max(0, item?.progress ?? 0)))
                    .stroke(light ? Color.black : Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let item {
                    VStack(spacing: 3) {
                        Text("\(Int(max(0, min(1, item.progress)) * 100))%")
                            .font(.custom("Helvetica-Bold", size: 23)).monospacedDigit()
                        Text(item.rate > 0 && item.size > item.done ? "~" + formatDuration((item.size-item.done)/item.rate) : "—")
                            .font(.custom("Helvetica-Light", size: 11)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("↓ " + formatBytes(item.rate) + "/s")
                            .font(.custom("Helvetica-Light", size: 11)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                } else {
                    Image(systemName: "arrow.down").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(.secondary)
                }
            }.frame(width: 112, height: 112).frame(width: 150, height: 150)
                .help(item?.name.isEmpty == false ? item!.name : tr("Здесь пока пусто", language))
            Button(action: expand) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26).background(.regularMaterial, in: Circle()) }
                .buttonStyle(.plain).opacity(hovering ? 1 : 0.5).help(tr("Развернуть окно", language)).accessibilityLabel(tr("Развернуть окно", language)).padding(5)
        }.frame(width: 150, height: 150).contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

@MainActor final class DownloadSleepGuard: ObservableObject {
    private var activity: NSObjectProtocol?
    func update(enabled: Bool, hasDownloads: Bool) {
        let needed = enabled && hasDownloads
        if needed && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "STRÖM: active downloads")
        } else if !needed, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }
    isolated deinit {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}

struct QuickHint: ViewModifier {
    let label: String
    @State private var hovered = false
    @State private var showHint = false
    @State private var pending: DispatchWorkItem?
    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovered = inside
                pending?.cancel()
                if inside {
                    let work = DispatchWorkItem { if hovered { withAnimation(.easeOut(duration: 0.12)) { showHint = true } } }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
                } else { showHint = false }
            }
            .overlay(alignment: .top) {
                if showHint {
                    Text(label).font(.custom("Helvetica", size: 11)).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.16)))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .offset(y: -30).allowsHitTesting(false).zIndex(10)
                }
            }.accessibilityHint(Text(label))
            .onDisappear { pending?.cancel(); showHint = false }
    }
}

@MainActor final class LidSleepGuard: ObservableObject {
    @Published var failure: String = ""
    private var process: Process?
    private var input: Pipe?
    private var stopping = false
    private var shouldRun = false
    func update(enabled: Bool, hasDownloads: Bool) {
        shouldRun = enabled && hasDownloads
        if shouldRun { start() } else { stop() }
    }
    private func recover() {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "StromSleepWatchdog") else { return }
        let task = Process(); task.executableURL = executable; task.arguments = ["--recover"]
        try? task.run()
    }
    private func start() {
        guard process == nil else { return }
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "StromSleepWatchdog") else { failure = "Не удалось включить работу с закрытой крышкой."; return }
        let task = Process(); let stdin = Pipe(); let stdout = Pipe()
        task.executableURL = executable; task.arguments = ["--watch"]; task.standardInput = stdin; task.standardOutput = stdout; task.standardError = Pipe()
        task.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.process === process else { return }
                self.process = nil; self.input = nil
                let wasStopping = self.stopping; self.stopping = false
                if process.terminationStatus != 0 {
                    self.recover()
                    self.failure = "Не удалось включить работу с закрытой крышкой."
                } else if wasStopping && self.shouldRun { self.start() }
            }
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains("ERROR:restore") {
                Task { @MainActor [weak self] in self?.failure = "Не удалось восстановить обычный режим сна." }
            } else if output.contains("ERROR:") {
                Task { @MainActor [weak self] in self?.failure = "Не удалось включить работу с закрытой крышкой." }
            }
        }
        do { try task.run(); process = task; input = stdin; stopping = false }
        catch { stdout.fileHandleForReading.readabilityHandler = nil; failure = "Не удалось включить работу с закрытой крышкой." }
    }
    func stop() {
        guard let task = process else { return }
        stopping = true
        try? input?.fileHandleForWriting.close(); input = nil
        // Keep the Process alive until its watchdog has restored power settings.
        if !task.isRunning { process = nil; stopping = false }
    }
    isolated deinit { try? input?.fileHandleForWriting.close() }
}

struct PreviewWindow: View {
    @StateObject private var engine = StromEngine()
    @StateObject private var license = StromLicense()
    @StateObject private var extras = ExtraAccess()
    @State private var notificationDelegate = StromNotificationDelegate()
    @AppStorage("downloadNotificationsEnabled") private var downloadNotificationsEnabled = false
    @State private var notificationPermissionDenied = false
    @State private var showLicense = false
    @State private var licenseInput = ""
    @StateObject private var sleepGuard = DownloadSleepGuard()
    @StateObject private var lidSleepGuard = LidSleepGuard()
    @AppStorage("preventSleepWithLidClosed") private var preventSleepWithLidClosed = false
    @AppStorage("preventSleepDuringDownloads") private var preventSleepDuringDownloads = true
    @ObservedObject var appDelegate: StromAppDelegate
    @State private var selection = 0
    @State private var showNotice = false
    @State private var compact = false
    @State private var showSettings = false
    @State private var showMagnet = false
    @State private var magnet = ""
    @State private var selected: TorrentItem?
    @State private var deleteCandidate: TorrentItem?
    @State private var sortOption = 0
    @State private var sortAscending = false
    @State private var showSort = false
    @State private var sortCloseWork: DispatchWorkItem?
    @AppStorage("interfaceOpacity") private var interfaceOpacity = 0.15
    @AppStorage("language") private var language = "en"
    @AppStorage("theme") private var theme = "auto"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plusAngle = 0.0
    @AppStorage("allowSharing") private var allowSharing = false
    @AppStorage("removeDownloadedFiles") private var removeDownloadedFiles = false
    @AppStorage("removeTorrentAfterCompletion") private var removeTorrentAfterCompletion = false
    @AppStorage("downloadDirectory") private var downloadDirectory = ""
    @AppStorage("torrentDirectory") private var torrentDirectory = ""
    let sections = ["Загружаются", "Завершённые", "Приостановленные"]
    private var activeDownloadIDs: [Int32] {
        engine.items.filter { !$0.complete && $0.error.isEmpty && !(engine.records[$0.id]?.paused ?? false) && !(engine.records[$0.id]?.stopped ?? false) }.map(\.id).sorted()
    }
    private var premiumAccess: Bool { license.featureAccess || ExtraAccess.grantsPlus }
    private func refreshEnginePlusAccess() {
        engine.plusAllowed = { [weak license] in
            license?.featureAccess == true || ExtraAccess.grantsPlus
        }
    }
    private func updateSleepGuard() {
        let active = !activeDownloadIDs.isEmpty
        sleepGuard.update(enabled: premiumAccess && preventSleepDuringDownloads, hasDownloads: active)
        lidSleepGuard.update(enabled: premiumAccess && preventSleepWithLidClosed, hasDownloads: active)
    }
    private var isLight: Bool { theme == "light" || (theme == "auto" && colorScheme == .light) }
    private var sidebarSurface: Color { isLight ? Color(white: controlActiveState == .inactive ? 0.90 : 0.955) : Color(white: controlActiveState == .inactive ? 0.06 : 0.10) }
    private var contentSurface: Color { isLight ? Color(white: controlActiveState == .inactive ? 0.925 : 0.975) : Color(white: controlActiveState == .inactive ? 0.08 : 0.13) }
    var body: some View {
        ZStack {
          (isLight ? Color.white : Color.black).opacity(interfaceOpacity).ignoresSafeArea()
          ClearWindow().frame(width: 0, height: 0)
          WindowSizeController(compact: compact, count: min(4, items(for: 0).count)).frame(width: 0, height: 0)
          if extras.panelVisible {
              ExtraPanel(extras: extras, light: isLight, opacity: interfaceOpacity, surface: contentSurface)
          } else if compact {
              HStack(spacing: 0) {
                  let active = Array(items(for: 0).prefix(4))
                  if active.isEmpty {
                      MiniDisk(item: nil, language: language, light: isLight, expand: { compact = false }, formatBytes: speed, formatDuration: duration)
                  } else {
                      ForEach(active) { item in
                          MiniDisk(item: item, language: language, light: isLight, expand: { compact = false }, formatBytes: speed, formatDuration: duration)
                      }
                  }
              }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).ignoresSafeArea()
          } else {
          HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if let url = Bundle.main.url(forResource: "StromLogo", withExtension: "png"), let logo = NSImage(contentsOf: url) {
                    ZStack {
                        if isLight { Image(nsImage: logo).resizable().scaledToFit() }
                        else {
                            Image(nsImage: logo).resizable().scaledToFit().colorInvert()
                            Image(nsImage: logo).resizable().scaledToFit().mask { RedAccentMask() }
                        }
                    }.frame(width: 225, height: 75).padding(.bottom, 18)
                }
                ForEach(0..<3, id: \.self) { index in
                    Button { selection = index } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ["arrow.down.circle", "checkmark.circle", "pause.circle"][index]).frame(width: 20)
                            Text(t(sections[index])).font(.custom("Helvetica-Light", size: 12)).lineLimit(1).minimumScaleFactor(0.8); Spacer(); Text("\(items(for: index).count)").foregroundStyle(.secondary)
                        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()).background(selection == index ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                Spacer()
                if !premiumAccess {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("Поддержать STRÖM")).font(.custom("Helvetica-Bold", size: 12))
                        Text(t("Все возможности за $7 — один раз.")).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary)
                        Button(t("Открыть Plus")) { licenseInput = ""; showLicense = true }.buttonStyle(.plain).font(.custom("Helvetica", size: 11)).padding(.top, 3)
                    }.padding(.bottom, 12)
                }
                HStack(spacing: 8) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 38, height: 38) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).help(t("Настройки")).accessibilityLabel(t("Настройки"))
                    Button { compact = true } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 16)).frame(width: 38, height: 38) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).help(t("Миниатюра")).accessibilityLabel(t("Миниатюра"))
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: plusBinding($preventSleepDuringDownloads)) { Image(systemName: "moon.zzz").font(.system(size: 11)).frame(width: 15) }
                            .toggleStyle(.switch).controlSize(.mini).frame(height: 18).help(t("Не переводить Mac в сон во время загрузок")).accessibilityLabel(t("Не переводить Mac в сон во время загрузок"))
                        Toggle(isOn: plusBinding($preventSleepWithLidClosed)) { Image(systemName: "laptopcomputer").font(.system(size: 11)).frame(width: 15) }
                            .toggleStyle(.switch).controlSize(.mini).frame(height: 18).help(t("Не засыпать с закрытой крышкой во время загрузок")).accessibilityLabel(t("Не засыпать с закрытой крышкой во время загрузок"))
                    }.frame(height: 38)
                }
            }.frame(width: 225).padding(22).background(sidebarSurface.opacity(interfaceOpacity), in: RoundedRectangle(cornerRadius: 24)).glassEffect(.regular, in: .rect(cornerRadius: 24))
            .mask {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 24).fill(.white)
                    if premiumAccess {
                        ZStack {
                            Rectangle().frame(width: 66, height: 21)
                            Rectangle().frame(width: 21, height: 66)
                        }.foregroundStyle(.black).rotationEffect(.degrees(-12)).offset(x: 8, y: -8).blendMode(.destinationOut).accessibilityLabel("Plus")
                    }
                }.compositingGroup()
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t(sections[selection])).font(.custom("HelveticaNeue-Light", size: 22))
                    }
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: 8) {
                            Button { showSort.toggle() } label: { Image(systemName: "line.3.horizontal.decrease").font(.system(size: 16)).frame(width: 36, height: 36) }
                                .buttonStyle(.plain).modifier(QuickHint(label: t("Сортировка"))).accessibilityLabel(t("Сортировка"))
                                .onHover { sortPointerChanged($0) }
                            Menu { Button(t("Торрент-файл…")) { chooseTorrent() }; Button(t("Magnet-ссылка…")) { magnet = ""; showMagnet = true } } label: { Image(systemName: "plus").font(.system(size: 18)).rotationEffect(.degrees(plusAngle)).frame(width: 36, height: 36) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().modifier(QuickHint(label: t("Добавить новый торрент"))).accessibilityLabel(t("Добавить новый торрент"))
                        }
                        if showSort { sortPicker.offset(x: -92, y: 0).zIndex(10) }
                    }.zIndex(5)
                }.padding(30)
                Divider().opacity(0.4)
                ZStack {
                    if items(for: selection).isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: ["arrow.down.circle", "checkmark.circle", "pause.circle"][selection]).font(.system(size: 43, weight: .ultraLight)).foregroundStyle(.secondary)
                            Text(t("Здесь пока пусто")).font(.custom("Helvetica", size: 19))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
                    }
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(items(for: selection)) { item in
                                Group { if selection == 1 { completedRow(item) } else { torrentRow(item) } }
                                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .modifier(active: GenieEffect(progress: 1, x: 0, y: -80), identity: GenieEffect(progress: 0, x: 0, y: -80)), removal: .modifier(active: GenieEffect(progress: 1, x: -260, y: 80), identity: GenieEffect(progress: 0, x: -260, y: 80))))
                            }
                        }.padding(24)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).animation(reduceMotion ? nil : .easeInOut(duration: 1.0), value: items(for: selection).map(\.id))
                HStack { Circle().fill(allowSharing ? .green : .red).frame(width: 7, height: 7); Text(t(allowSharing ? "Экспорт включён" : "Экспорт отключён")); Spacer() }.font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 15)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(contentSurface.opacity(interfaceOpacity), in: RoundedRectangle(cornerRadius: 24)).glassEffect(.regular, in: .rect(cornerRadius: 24))
          }.padding(18)
          }
        }.frame(minWidth: compact ? 0 : 780, minHeight: compact ? 0 : 500)
        .font(.custom("Helvetica-Light", size: 13))
        .tracking(0.15)
        .preferredColorScheme(theme == "auto" ? nil : theme == "light" ? .light : .dark)
        .containerBackground(.clear, for: .window)
        .overlay {
          if showSettings {
           ZStack {
            OutsideClickSurface { showSettings = false }.frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(t("Настройки")).font(.custom("Helvetica-Bold", size: 22))
                    Spacer()
                    Button(t("Готово")) { showSettings = false }.keyboardShortcut(.defaultAction)
                }
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Раздача по умолчанию")).font(.custom("Helvetica", size: 14))
                        Text(t(allowSharing ? "Включена в настройках" : "Выключена в настройках")).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(t("Раздача по умолчанию"), isOn: $allowSharing).labelsHidden().toggleStyle(.switch).fixedSize()
                }
                Text(t("После выключения раздачи уже отправленные данные могут передаваться ещё некоторое время.")).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                folderRow("Скачанные файлы", path: $downloadDirectory)
                folderRow("Торрент-файлы", path: $torrentDirectory)
                Divider()
                settingsSwitch("Удалять загрузку вместе со скачанными файлами", isOn: $removeDownloadedFiles)
                settingsSwitch("Удалять торрент-файл после загрузки", isOn: plusBinding($removeTorrentAfterCompletion))
                Text(t("Файлы перемещаются в Корзину. Исходный торрент-файл вне STRÖM не затрагивается.")).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                settingsSwitch("Уведомления о загрузках", isOn: $downloadNotificationsEnabled)
                if notificationPermissionDenied {
                    Text(t("Разрешите уведомления для STRÖM в настройках macOS.")).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text(t("Язык")); Spacer(minLength: 12)
                    Picker(t("Язык"), selection: $language) { ForEach(StromLanguage.allCases) { l in Text(l.name).tag(l.rawValue) } }.labelsHidden().fixedSize()
                }
                HStack { Text(t("Непрозрачность основания")); Slider(value: $interfaceOpacity, in: 0...1); Text("\(Int(interfaceOpacity * 100))% ").monospacedDigit().frame(width: 46) }
                HStack {
                    Text(t("Тема")); Spacer(minLength: 12)
                    Picker(t("Тема"), selection: $theme) {
                        Text(t("Автоматическая")).tag("auto"); Text(t("Дневная")).tag("light"); Text(t("Ночная")).tag("dark")
                    }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 340)
                }
                Divider()
                HStack {
                    Text(t("Лицензия")); Spacer()
                    Button(t(license.active ? "Отозвать активацию" : "Ввести ключ")) { licenseInput = ""; showLicense = true }
                }
                DisclosureGroup(t("О программе")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(t("Создавая "))
                            ExtraTitle(extras: extras)
                            Text(t(", мы прежде всего думали о дизайне, лёгкости и простоте интерфейса, а также о возможности отключить раздачу файлов другим участникам торрент-сети."))
                        }.fixedSize(horizontal: false, vertical: true)
                        Text(t("STRÖM — условно бесплатная программа: основные возможности доступны бесплатно и без ограничений по времени. Дополнительные функции для удобства доступны в Plus за один бессрочный платёж.")).fixedSize(horizontal: false, vertical: true)
                        Text(t("Стоимость символическая: после комиссий платёжных сервисов создателям остаётся лишь небольшая сумма на развитие проекта.")).fixedSize(horizontal: false, vertical: true)
                        Text(t("Благодарим каждого, кто поддерживает STRÖM. Желаем приятного пользования! Если у вас возникнут вопросы, напишите нам по адресу, указанному ниже.")).fixedSize(horizontal: false, vertical: true)
                    }.font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary).padding(.top, 10)
                }
                Divider()
                HStack(alignment: .top) {
                    Text(t("Поддержка")); Spacer()
                    Link("info@oskarreus.ch", destination: URL(string: "mailto:info@oskarreus.ch")!).textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }.font(.custom("Helvetica-Light", size: 13)).padding(26)
            }.frame(width: 500).frame(maxHeight: 560).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).glassEffect(.regular, in: .rect(cornerRadius: 24)).shadow(radius: 20)
                .transition(reduceMotion ? .opacity : .modifier(active: GenieEffect(progress: 1, x: -180, y: 220), identity: GenieEffect(progress: 0, x: -180, y: 220)))
           }
          }
        }
        .onAppear {
            refreshEnginePlusAccess()
            UNUserNotificationCenter.current().delegate = notificationDelegate
            engine.onDownloadEvent = { event, name in
                guard UserDefaults.standard.bool(forKey: "downloadNotificationsEnabled") else { return }
                let language = UserDefaults.standard.string(forKey: "language") ?? "en"
                let title: String
                switch event {
                case .started: title = "Загрузка началась"
                case .completed: title = "Загрузка завершена"
                case .failed: title = "Проблема с загрузкой"
                }
                let content = UNMutableNotificationContent()
                content.title = tr(title, language)
                content.body = name
                content.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
            updateSleepGuard()
        }
        .onChange(of: downloadNotificationsEnabled) { _, enabled in
            guard enabled else { notificationPermissionDenied = false; return }
            Task {
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                if !granted { downloadNotificationsEnabled = false; notificationPermissionDenied = true }
            }
        }
        .onChange(of: license.active) { _, _ in updateSleepGuard() }
        .onChange(of: extras.revision) { _, _ in refreshEnginePlusAccess(); updateSleepGuard() }
        .onChange(of: preventSleepDuringDownloads) { _, _ in updateSleepGuard() }
        .onChange(of: preventSleepWithLidClosed) { _, _ in updateSleepGuard() }
        .onChange(of: lidSleepGuard.failure) { _, message in
            guard !message.isEmpty else { return }
            preventSleepWithLidClosed = false
            engine.report(message)
            lidSleepGuard.failure = ""
        }
        .onReceive(engine.$items) { items in appDelegate.downloadStatusIndicator.update(items, records: engine.records) }
        .onChange(of: activeDownloadIDs) { _, _ in updateSleepGuard() }
        .onChange(of: allowSharing) { _, value in engine.setSharing(value) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: showSettings)
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5)) { plusAngle = 45 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeInOut(duration: 0.5)) { plusAngle = 0 } }
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            Task { await license.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in lidSleepGuard.stop(); engine.flush() }
        .onReceive(appDelegate.$pendingFiles) { urls in
            guard !urls.isEmpty else { return }
            DispatchQueue.main.async {
                let pending = appDelegate.pendingFiles
                appDelegate.pendingFiles.removeAll()
                pending.forEach { addTorrentURL($0) }
            }
        }
        .overlay {
            if let original = selected {
                ZStack {
                    OutsideClickSurface { selected = nil }.frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
                    details(engine.items.first(where: { $0.id == original.id }) ?? original)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24)).shadow(radius: 20)
                        .transition(reduceMotion ? .opacity : .modifier(active: GenieEffect(progress: 1, x: -100, y: 100), identity: GenieEffect(progress: 0, x: -100, y: 100)))
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.55), value: selected?.id)
        .overlay {
            if showLicense {
                ZStack {
                    OutsideClickSurface { showLicense = false }.frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
                    licensePanel.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).glassEffect(.regular, in: .rect(cornerRadius: 24)).shadow(radius: 20)
                }.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLicense)
        .overlay { ExtraOverlay(extras: extras) }
        .onExitCommand { if extras.handleExit() {} else if showLicense { showLicense = false } else if compact { compact = false } else { selected = nil; showSettings = false } }
        .alert(t("Magnet-ссылка"), isPresented: $showMagnet) {
            TextField("magnet:…", text: $magnet)
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Добавить")) { addMagnet() }
        }
        .alert("STRÖM", isPresented: $engine.showError) { Button(t("Понятно"), role: .cancel) {} } message: { Text(t(engine.errorMessage) + (engine.errorDetail.isEmpty ? "" : "\n" + engine.errorDetail)) }
        .alert(t("Удалить из списка?"), isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button(t("Отмена"), role: .cancel) { deleteCandidate = nil }
            Button(t("Удалить"), role: .destructive) { if let item = deleteCandidate { let removed = engine.remove(item, includingData: removeDownloadedFiles); if removed { selected = nil }; deleteCandidate = nil } }
        } message: { Text(t(removeDownloadedFiles ? "Скачанные файлы будут перемещены в Корзину." : "Скачанные файлы останутся на диске.")) }
    }

    private func plusBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { premiumAccess && binding.wrappedValue }, set: { value in
            if value && !premiumAccess { licenseInput = ""; showLicense = true }
            else { binding.wrappedValue = value }
        })
    }
    private var licensePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("STRÖM Plus").font(.custom("Helvetica-Bold", size: 20)); Spacer(); Button(t("Готово")) { showLicense = false } }
            if license.active {
                Text(t("Лицензия активна на этом устройстве.")).foregroundStyle(.secondary)
                Text(t("Для переноса отзовите активацию при подключении к интернету.")).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary)
                Button(t("Отозвать активацию")) { Task { await license.deactivate() } }.disabled(license.busy)
            } else {
                Text(t("Один раз — $7. Одно устройство, бессрочно.")).foregroundStyle(.secondary)
                Text(t("После активации Plus работает без интернета.")).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary)
                if let checkout = license.checkoutURL { Button(t("Купить Plus")) { NSWorkspace.shared.open(checkout) } }
                else { Text(t("Продажи и активация пока не настроены.")).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary) }
                Divider()
                SecureField(t("Ключ лицензии"), text: $licenseInput).textFieldStyle(.roundedBorder)
                if let recovery=license.recoveryURL(language: language) { Button(t("Получить ключ по почте")) { NSWorkspace.shared.open(recovery) } }
                Button(t("Активировать или восстановить")) { Task {
                    if await extras.intercept(licenseInput) { licenseInput = ""; showLicense = false; showSettings = false }
                    else { await license.activate(licenseInput); if license.active { licenseInput = "" } }
                } }.disabled(license.busy || extras.busy || licenseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !license.error.isEmpty { Text(t(license.error)).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if !extras.notice.isEmpty { Text(extras.notice).font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(26).frame(width: 440)
    }
    private func t(_ key: String) -> String { tr(key, language) }
    private var sortPicker: some View {
        VStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                let labels = ["Дата добавления", "Скорость", "Объём", "Приоритет"]
                let icons = ["calendar", "speedometer", "arrow.down.to.line", "arrow.up.arrow.down"]
                Button { chooseSort(index) } label: {
                    Image(systemName: icons[index]).font(.system(size: 13)).frame(width: 30, height: 30)
                        .background(sortOption == index ? Color.primary.opacity(0.12) : .clear, in: Circle())
                        .overlay(alignment: .bottomTrailing) {
                            if sortOption == index { Image(systemName: sortAscending ? "arrow.up" : "arrow.down").font(.system(size: 7, weight: .bold)).padding(2) }
                        }.contentShape(Circle())
                }.buttonStyle(.plain).contentShape(Circle()).modifier(QuickHint(label: t(labels[index])))
            }
        }.padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.16))).shadow(color: .black.opacity(0.16), radius: 8, y: 4).onHover { sortPointerChanged($0) }
    }
    private func chooseSort(_ option: Int) {
        if sortOption == option { sortAscending.toggle() }
        else { sortOption = option; sortAscending = false }
    }
    private func sortPointerChanged(_ inside: Bool) {
        sortCloseWork?.cancel()
        guard !inside, showSort else { return }
        let work = DispatchWorkItem { showSort = false }
        sortCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }
    private func items(for index: Int) -> [TorrentItem] {
        engine.items.filter { item in let manualPause = engine.records[item.id]?.paused ?? false; return index == 0 ? !item.complete && !manualPause : index == 1 ? item.complete : manualPause && !item.complete }.sorted { a, b in
            let aDate = engine.records[a.id]?.added ?? .distantPast
            let bDate = engine.records[b.id]?.added ?? .distantPast
            func ordered<T: Comparable>(_ left: T, _ right: T) -> Bool {
                if left == right { return aDate == bDate ? a.id < b.id : (sortAscending ? aDate < bDate : aDate > bDate) }
                return sortAscending ? left < right : left > right
            }
            switch sortOption {
            case 1:
                let aSpeed = index == 1 ? average(a) : a.rate, bSpeed = index == 1 ? average(b) : b.rate
                return ordered(aSpeed, bSpeed)
            case 2:
                let aBytes = max(a.done, a.size), bBytes = max(b.done, b.size)
                return ordered(aBytes, bBytes)
            case 3:
                let ap = engine.records[a.id]?.priority ?? 3, bp = engine.records[b.id]?.priority ?? 3
                return ordered(ap, bp)
            default: return ordered(aDate, bDate)
            }
        }
    }
    private func average(_ item: TorrentItem) -> Int64 {
        guard let record = engine.records[item.id], record.speedSamples > 0 else { return 0 }
        return record.speedTotal / record.speedSamples
    }
    private func completedRow(_ item: TorrentItem) -> some View {
        HStack(spacing: 16) {
            Button { reveal(item) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless).help(t("Показать в Finder")).accessibilityLabel(t("Показать в Finder"))
            Button { selected = item } label: {
                HStack(spacing: 16) {
                    Text(item.name.isEmpty ? t("Поиск информации…") : item.name)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(bytes(item.size)).frame(width: 90, alignment: .trailing)
                    Text((engine.records[item.id]?.speedTotal ?? 0) > 0 ? "Ø \(speed(average(item)))/s" : "Ø —").frame(width: 130, alignment: .trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel(item.name.isEmpty ? t("Поиск информации…") : item.name).accessibilityHint(t("Статистика"))
            if !engine.sharingAllowed(item) { sharingLock }
            Button { deleteCandidate = item } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(t("Удалить"))
        }.font(.custom("Helvetica-Light", size: 12)).padding(14).background((isLight ? Color.black : Color.white).opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func torrentRow(_ item: TorrentItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                titleView(item).font(.custom("Helvetica-Bold", size: 15))
                Spacer()
                Text("\(Int(item.progress * 100))%").monospacedDigit()
                if !engine.sharingAllowed(item) { sharingLock }
                Button { engine.pause(item) } label: { Image(systemName: (engine.records[item.id]?.paused ?? false) ? "play.fill" : "pause.fill") }.buttonStyle(.borderless).help(t((engine.records[item.id]?.paused ?? false) ? "Продолжить" : "Приостановить"))
                if engine.records[item.id]?.stopped == true { Button { deleteCandidate = item } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(t("Удалить")) }
                else { Button { engine.stop(item) } label: { Image(systemName: "stop.fill") }.buttonStyle(.borderless).help(t("Остановить")) }
            }
            progressBar(item)
            HStack {
                Text("\(bytes(item.done)) \(t("из")) \(bytes(item.size))")
                Button {
                    let current = engine.records[item.id]?.priority ?? 3
                    engine.setPriority(current % 5 + 1, for: item)
                } label: {
                    Text("\(engine.records[item.id]?.priority ?? 3)").font(.custom("Helvetica-Light", size: 10)).frame(width: 15, height: 15).background(Circle().strokeBorder(.primary.opacity(0.5), lineWidth: 1))
                }.buttonStyle(.plain).modifier(QuickHint(label: t("Приоритет"))).accessibilityLabel(t("Приоритет"))
                HStack(spacing: 2) { Image(systemName: "person.2"); Text("\(item.seeds)") }.font(.custom("Helvetica-Light", size: 10)).padding(.horizontal, 3).frame(height: 15).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.4), lineWidth: 1)).contentShape(Rectangle()).modifier(QuickHint(label: t("Подключённые раздающие")))
                Spacer()
                Text((engine.records[item.id]?.paused ?? false) ? t("Пауза") : item.checking ? t("Проверка файла") : item.complete ? t("Завершено") : "↓ \(speed(item.rate))/s  ·  Ø \(engine.sessionAverage(for: item).map { speed($0) + "/s" } ?? "—")")
                    .help(t("Текущая и средняя скорость за сеанс"))
            }.font(.custom("Helvetica-Light", size: 12)).foregroundStyle(.secondary)
            if !item.error.isEmpty { Text(item.error).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.red) }
        }.padding(.horizontal, 16).padding(.vertical, 12).background((isLight ? Color.black : Color.white).opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
    private func progressBar(_ item: TorrentItem) -> some View {
        let progress = min(1, max(0, item.progress))
        let elapsed = "\(t("Прошло")): \(duration(engine.records[item.id]?.downloadSeconds ?? 0))"
        let remaining = item.rate > 0 && item.size > item.done ? "~" + duration((item.size-item.done)/item.rate) : "—"
        let right = "\(t("Осталось")): \(remaining)"
        let label = elapsed + ", " + right
        return GeometryReader { geometry in
            let labels = HStack(spacing: 4) {
                Text(elapsed).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                Text(right).lineLimit(1).minimumScaleFactor(0.6)
            }.font(.custom("Helvetica-Light", size: 10)).padding(.horizontal, 10)
            ZStack(alignment: .leading) {
                Capsule().fill((isLight ? Color.black : Color.white).opacity(0.12))
                Capsule().fill(isLight ? Color.black : Color.white).frame(width: geometry.size.width * progress)
                labels.foregroundStyle(isLight ? Color.black : Color.white).frame(width: geometry.size.width)
                labels.foregroundStyle(isLight ? Color.white : Color.black).frame(width: geometry.size.width)
                    .mask(alignment: .leading) { Rectangle().frame(width: geometry.size.width * progress) }
            }.clipShape(Capsule())
        }.frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label + ", \(Int(progress * 100))%"))
    }
    private func titleView(_ item: TorrentItem) -> some View {
        Text(item.name.isEmpty ? t("Поиск информации…") : item.name)
            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .overlay { TitleClickSurface(openDetails: { selected = item }, reveal: { reveal(item) }).accessibilityHidden(true) }
            .accessibilityAddTraits(.isButton).accessibilityAction { selected = item }
    }
    private func reveal(_ item: TorrentItem) {
        guard let folder = engine.records[item.id]?.directory else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        let target = directory.appendingPathComponent(item.name)
        if !item.name.isEmpty && FileManager.default.fileExists(atPath: target.path) { NSWorkspace.shared.activateFileViewerSelecting([target]) }
        else { NSWorkspace.shared.open(directory) }
    }
    private func details(_ item: TorrentItem) -> some View {
        let points = (engine.records[item.id]?.speedByPercent ?? []).enumerated().compactMap { index, speed in speed >= 0 ? PlotPoint(id: index, speed: speed) : nil }
        let maximum = max(1, Double(engine.records[item.id]?.peak ?? 0))
        return VStack(alignment: .leading, spacing: 18) {
            HStack { Text(item.name).font(.custom("Helvetica-Bold", size: 19)).lineLimit(2); Spacer(); Button(t("Готово")) { selected = nil } }
            Text(t("Скорость загрузки")).font(.custom("Helvetica", size: 13))
            VStack(spacing: 2) {
                Chart(points) { p in LineMark(x: .value("%", p.id), y: .value("speed", p.speed)).foregroundStyle(.blue) }
                    .chartXScale(domain: 0...100).chartYScale(domain: 0...maximum)
                    .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { _ in AxisGridLine() } }
                    .chartYAxis { AxisMarks(position: .leading, values: [0.0, maximum]) { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Double.self) { Text("\(speed(Int64(n)))/s") } } } }
                    .overlay { if points.isEmpty { Text(t("Нет данных для графика")).foregroundStyle(.secondary) } }
                    .frame(height: 130)
                HStack { Text("0%"); Spacer(); Text("25%"); Spacer(); Text("50%"); Spacer(); Text("75%"); Spacer(); Text("100%") }
                    .font(.custom("Helvetica-Light", size: 10)).foregroundStyle(.secondary).padding(.leading, 55)
            }
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
                GridRow { Text(t("Размер")); Text(bytes(item.size)); Text(t("Загружено")); Text(bytes(item.done)) }
                GridRow { Text(t("Скорость")); Text("\(speed(item.rate))/s"); Text(t("Пиковая скорость")); Text((engine.records[item.id]?.peak ?? 0) > 0 ? "\(speed(engine.records[item.id]?.peak ?? 0))/s" : "—") }
                GridRow { Text(t("Средняя скорость")); Text((engine.records[item.id]?.speedTotal ?? 0) > 0 ? "\(speed(average(item)))/s" : "—"); Text(t("Прошло")); Text((engine.records[item.id]?.uploadBaselineKnown ?? false) ? duration(engine.records[item.id]?.downloadSeconds ?? 0) : "—") }
                GridRow { Text(t((engine.records[item.id]?.uploadBaselineKnown ?? false) ? "Отдано" : "Отдано с обновления")); Text(bytes(engine.records[item.id]?.uploaded ?? 0)); if !engine.sharingAllowed(item) { sharingLock; Text(t("Раздача выключена")) } }
                GridRow { Text(t("Дата добавления")); Text(addedDate(item)) }
            }.font(.custom("Helvetica-Light", size: 12))
            HStack {
                Button((engine.records[item.id]?.paused ?? false) ? "▶" : "Ⅱ") { engine.pause(item) }.help(t((engine.records[item.id]?.paused ?? false) ? "Продолжить" : "Приостановить"))
                Toggle(t("Раздача файлов"), isOn: Binding(get: { engine.sharingAllowed(item) }, set: { engine.setSharing($0, for: item) })).toggleStyle(.switch).controlSize(.small)
                if item.complete || engine.records[item.id]?.stopped == true { Button(t("Удалить")) { selected = nil; deleteCandidate = item } }
                else { Button(t("Остановить")) { engine.stop(item) } }
                Spacer()
            }
        }.font(.custom("Helvetica-Light", size: 13)).padding(28).frame(width: 620)
    }
    private var sharingLock: some View {
        HStack(spacing: 1) { Image(systemName: "arrow.up.right"); Image(systemName: "lock.fill").font(.system(size: 8)) }.foregroundStyle(.secondary).help(t("Раздача выключена"))
    }
    private func speed(_ n: Int64) -> String {
        let units: [String] = language == "ru" ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : language == "fr" ? ["o", "Ko", "Mo", "Go", "To"] : ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(0, n)); var index = 0
        while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        value = (value * 2).rounded() / 2
        if value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        let f = NumberFormatter(); f.locale = Locale(identifier: language == "de" ? "de_CH" : language)
        f.minimumFractionDigits = 1; f.maximumFractionDigits = 1; f.usesGroupingSeparator = false
        return "\(f.string(from: NSNumber(value: value)) ?? "0.0") \(units[index])"
    }
    private func bytes(_ n: Int64) -> String {
        let units: [String] = language == "ru" ? ["Б", "КБ", "МБ", "ГБ", "ТБ"] : language == "fr" ? ["o", "Ko", "Mo", "Go", "To"] : ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(0, n)); var index = 0
        while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        let f = NumberFormatter(); f.locale = Locale(identifier: language == "de" ? "de_CH" : language); f.maximumFractionDigits = index == 0 ? 0 : 2; f.minimumFractionDigits = 0; f.usesGroupingSeparator = false
        return "\(f.string(from: NSNumber(value: value)) ?? "0") \(units[index])"
    }
    private func addedDate(_ item: TorrentItem) -> String {
        guard let record = engine.records[item.id], record.uploadBaselineKnown, record.added != .distantPast else { return t("Неизвестно") }
        let date = record.added
        let f = DateFormatter(); f.locale = Locale(identifier: language); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
    }
    private func duration(_ seconds: Int64) -> String {
        let s = max(0, seconds); let hour = language == "ru" ? "ч" : "h"; let minute = language == "ru" ? "мин" : "min"; let second = language == "ru" ? "с" : "s"
        return s >= 3600 ? "\(s/3600) \(hour) \((s%3600)/60) \(minute)" : "\(s/60) \(minute) \(s%60) \(second)"
    }
    private var destination: String { downloadDirectory.isEmpty ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path : downloadDirectory }
    private func addMagnet() {
        let value = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("magnet:") else { engine.report("Введите корректную magnet-ссылку."); return }
        engine.add(value, directory: destination)
    }
    private func chooseTorrent() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addTorrentURL(url)
    }
    private func addTorrentURL(_ url: URL) {
        do {
            guard url.pathExtension.lowercased() == "torrent" else { engine.report("Не удалось добавить торрент."); return }
            let base = torrentDirectory.isEmpty ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("STRÖM/Torrents", isDirectory: true) : URL(fileURLWithPath: torrentDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let stem = url.deletingPathExtension().lastPathComponent
            var copy = base.appendingPathComponent(url.lastPathComponent)
            var suffix = 1
            while FileManager.default.fileExists(atPath: copy.path) { copy = base.appendingPathComponent("\(stem) (\(suffix)).torrent"); suffix += 1 }
            try FileManager.default.copyItem(at: url, to: copy)
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) {
                _ = NSWorkspace.shared.setIcon(icon, forFile: copy.path, options: [])
            }
            engine.add(copy.path, directory: destination, ownedTorrentCopy: true)
        } catch { engine.report("Не удалось добавить торрент.", detail: error.localizedDescription) }
    }

    private func settingsSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(t(title)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Toggle(t(title), isOn: isOn).labelsHidden().toggleStyle(.switch).fixedSize()
        }
    }

    private func folderRow(_ title: String, path: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(title)).font(.custom("Helvetica", size: 13))
                Text(path.wrappedValue.isEmpty ? t("Папка не выбрана") : path.wrappedValue).font(.custom("Helvetica-Light", size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(t("Выбрать…")) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
        }
    }
}

@main struct StromApp: App {
    @NSApplicationDelegateAdaptor(StromAppDelegate.self) private var appDelegate
    var body: some Scene { Window("STRÖM", id: "main") { PreviewWindow(appDelegate: appDelegate) }.windowStyle(.hiddenTitleBar) }
}
