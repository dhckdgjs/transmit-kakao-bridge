import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private let dragThresholdSquared: CGFloat = 100
private let kakaoInputBottomRatio: CGFloat = 0.30
private let kakaoMainWindowLeftGuardWidth: CGFloat = 260

private let pathAcceptedTypes: [NSPasteboard.PasteboardType] = [
    .URL,
    .string,
    .init("public.url"),
    .init("public.utf8-plain-text"),
    .init("public.plain-text"),
    .init("public.text"),
    .init("NSStringPboardType"),
    .init("NSURLPboardType"),
]

private let fileImageAcceptedTypes: [NSPasteboard.PasteboardType] = [
    .fileURL,
    .init("public.file-url"),
    .init("NSFilenamesPboardType"),
    .init("public.image"),
    .init("public.png"),
    .init("public.jpeg"),
    .init("public.tiff"),
]

private let transmitPromiseAcceptedTypes: [NSPasteboard.PasteboardType] = [
    .init("com.apple.NSFilePromiseItemMetaData"),
    .init("com.apple.pasteboard.promised-file-name"),
    .init("com.apple.pasteboard.promised-suggested-file-name"),
    .init("com.apple.pasteboard.promised-file-content-type"),
    .init("Apple files promise pasteboard type"),
    .init("com.apple.pasteboard.NSFilePromiseID"),
    .init("com.apple.pasteboard.promised-file-url"),
    .init("NSPromiseContentsPboardType"),
    .init("com.panic.FTPKit.nodeRepresentation"),
    .init("com.panic.FTPKit.safeCachedNodes"),
    .init("com.panic.FTPKit.PromiseUserInfo"),
    .init("com.panic.FTPKit.NodeUTI"),
]

@MainActor
private final class BridgeState {
    var startPoint: NSPoint?
    var sourceIsTransmit = false
    var overlaysShown = false
    var handledDrop = false

    func reset() {
        startPoint = nil
        sourceIsTransmit = false
        overlaysShown = false
        handledDrop = false
    }
}

@MainActor
private final class BridgeSettings {
    private enum Key {
        static let handleFileImageDrops = "handleFileImageDrops"
    }

    var handleFileImageDrops: Bool {
        get {
            UserDefaults.standard.bool(forKey: Key.handleFileImageDrops)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.handleFileImageDrops)
        }
    }

    var acceptedTypes: [NSPasteboard.PasteboardType] {
        let defaultTypes = pathAcceptedTypes + transmitPromiseAcceptedTypes
        return handleFileImageDrops ? defaultTypes + fileImageAcceptedTypes : defaultTypes
    }
}

@MainActor
private final class BridgeLog {
    let url: URL

    init() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TransmitKakaoBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.url = root.appendingPathComponent("TransmitKakaoBridge.log")
        append("TransmitKakaoBridge started.")
    }

    func append(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "===== \(timestamp) =====\n\(text)\n\n"

        guard let data = entry.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private enum AccessibilityPermission {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private enum ScreenSpace {
    static var maxY: CGFloat {
        NSScreen.screens.map { $0.frame.maxY }.max() ?? NSScreen.main?.frame.maxY ?? 0
    }

    static func appKitPointToQuartz(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: maxY - point.y)
    }

    static func quartzBoundsToAppKitRect(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.origin.x, y: maxY - rect.origin.y - rect.height, width: rect.width, height: rect.height)
    }
}

private struct CGWindowSnapshot {
    let ownerName: String
    let name: String
    let boundsQuartz: CGRect
    let boundsAppKit: NSRect

    func containsAppKitPoint(_ point: NSPoint) -> Bool {
        boundsQuartz.contains(ScreenSpace.appKitPointToQuartz(point))
    }
}

private enum WindowFinder {
    static func orderedWindows() -> [CGWindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { info in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { return nil }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            guard !ownerName.isEmpty else { return nil }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return nil
            }

            guard bounds.width > 80, bounds.height > 80 else { return nil }

            let name = info[kCGWindowName as String] as? String ?? ""
            return CGWindowSnapshot(
                ownerName: ownerName,
                name: name,
                boundsQuartz: bounds,
                boundsAppKit: ScreenSpace.quartzBoundsToAppKitRect(bounds)
            )
        }
    }

    static func ownerName(at point: NSPoint) -> String? {
        for window in orderedWindows() where window.containsAppKitPoint(point) {
            return window.ownerName
        }

        return nil
    }

    static func kakaoWindows() -> [CGWindowSnapshot] {
        orderedWindows().filter { window in
            isKakao(ownerName: window.ownerName)
                && window.boundsAppKit.width > 300
                && window.boundsAppKit.height > 300
        }
    }

    static func isTransmit(ownerName: String?) -> Bool {
        ownerName == "Transmit"
    }

    static func isKakao(ownerName: String) -> Bool {
        ownerName == "KakaoTalk" || ownerName == "카카오톡"
    }
}

private final class DropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DropView: NSView {
    private let settings: BridgeSettings
    var onDrop: (([String], NSPoint) -> Void)?

    init(frame frameRect: NSRect, settings: BridgeSettings) {
        self.settings = settings
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        self.settings = BridgeSettings()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes(settings.acceptedTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = PasteboardPathExtractor.paths(
            from: sender.draggingPasteboard,
            includeFileImageFallback: settings.handleFileImageDrops
        )
        let windowPoint = sender.draggingLocation
        let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? NSEvent.mouseLocation

        onDrop?(paths, screenPoint)
        return !paths.isEmpty
    }
}

private enum PasteboardPathExtractor {
    static func paths(from pasteboard: NSPasteboard, includeFileImageFallback: Bool) -> [String] {
        var values: [String] = []

        for item in pasteboard.pasteboardItems ?? [] {
            if let text = string(from: item, type: .init("public.utf8-plain-text")) {
                appendText(text, to: &values)
                continue
            }

            if let text = string(from: item, type: .string) {
                appendText(text, to: &values)
                continue
            }

            if let text = string(from: item, type: .init("NSStringPboardType")) {
                appendText(text, to: &values)
                continue
            }

            if let urlText = string(from: item, type: .init("public.url")) {
                appendText(urlText, to: &values)
                continue
            }

            if includeFileImageFallback {
                if let fileURLText = string(from: item, type: .fileURL) {
                    appendText(fileURLText, to: &values)
                    continue
                }

                if let fileURLText = string(from: item, type: .init("public.file-url")) {
                    appendText(fileURLText, to: &values)
                }
            }
        }

        if values.isEmpty {
            if let text = pasteboard.string(forType: .init("public.utf8-plain-text")) {
                appendText(text, to: &values)
            } else if let text = pasteboard.string(forType: .string) {
                appendText(text, to: &values)
            } else if let text = pasteboard.string(forType: .init("public.url")) {
                appendText(text, to: &values)
            }
        }

        if includeFileImageFallback,
           values.isEmpty,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            values.append(contentsOf: urls.map(pathString(from:)))
        }

        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.contains("/") else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }

        return output
    }

    private static func string(from item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> String? {
        guard item.types.contains(type), let string = item.string(forType: type), !string.isEmpty else {
            return nil
        }

        return string
    }

    private static func appendText(_ text: String, to values: inout [String]) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let url = URL(string: line), url.scheme != nil {
                values.append(pathString(from: url))
            } else {
                values.append(line.removingPercentEncoding ?? line)
            }
        }
    }

    private static func pathString(from url: URL) -> String {
        if #available(macOS 13.0, *) {
            return url.path(percentEncoded: false)
        }

        return url.path.removingPercentEncoding ?? url.path
    }
}

private struct TextPasteboardSnapshot {
    let string: String?

    init(_ pasteboard: NSPasteboard) {
        self.string = pasteboard.string(forType: .string)
    }

    func restore(to pasteboard: NSPasteboard, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else {
            return
        }

        guard let string else {
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

@MainActor
private final class OverlayController {
    private var panels: [NSPanel] = []
    private let settings: BridgeSettings
    private let log: BridgeLog
    private let onDrop: ([String], NSPoint) -> Void

    init(settings: BridgeSettings, log: BridgeLog, onDrop: @escaping ([String], NSPoint) -> Void) {
        self.settings = settings
        self.log = log
        self.onDrop = onDrop
    }

    func show() {
        guard panels.isEmpty else { return }

        let kakaoWindows = WindowFinder.kakaoWindows()
        log.append("Showing overlays for \(kakaoWindows.count) Kakao window(s).")

        for window in kakaoWindows {
            let frame = inputFrame(for: window.boundsAppKit)
            guard frame.width > 20, frame.height > 20 else { continue }

            let panel = DropPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
            panel.backgroundColor = NSColor.clear
            panel.isOpaque = false
            panel.alphaValue = 0.04
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false

            let view = DropView(frame: NSRect(origin: .zero, size: frame.size), settings: settings)
            view.onDrop = onDrop
            panel.contentView = view
            panel.orderFrontRegardless()

            panels.append(panel)
        }
    }

    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func inputFrame(for kakaoFrame: NSRect) -> NSRect {
        let leftGuard: CGFloat = kakaoFrame.width >= 700 ? kakaoMainWindowLeftGuardWidth : 0
        let height = kakaoFrame.height * kakaoInputBottomRatio

        return NSRect(
            x: kakaoFrame.minX + leftGuard,
            y: kakaoFrame.minY,
            width: max(0, kakaoFrame.width - leftGuard),
            height: height
        )
    }
}

@MainActor
private final class PasteController {
    private let log: BridgeLog

    init(log: BridgeLog) {
        self.log = log
    }

    func paste(paths: [String], at screenPoint: NSPoint) {
        guard !paths.isEmpty else {
            log.append("Drop received, but no path candidates were found.")
            return
        }

        guard AccessibilityPermission.isTrusted(prompt: true) else {
            log.append("Accessibility permission is missing; paste was skipped.")
            return
        }

        let text = paths.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        let previousPasteboard = TextPasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let pathPasteboardChangeCount = pasteboard.changeCount

        log.append("Pasting \(paths.count) path(s), \(text.count) characters.")

        activateKakao()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            self.leftClick(at: screenPoint)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                self.commandV()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    previousPasteboard.restore(to: pasteboard, expectedChangeCount: pathPasteboardChangeCount)
                }
            }
        }
    }

    private func activateKakao() {
        for app in NSWorkspace.shared.runningApplications {
            guard WindowFinder.isKakao(ownerName: app.localizedName ?? "") else { continue }
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
    }

    private func leftClick(at appKitPoint: NSPoint) {
        let point = ScreenSpace.appKitPointToQuartz(appKitPoint)
        let source = CGEventSource(stateID: .hidSystemState)

        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func commandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeV: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = BridgeState()
    private let settings = BridgeSettings()
    private let log = BridgeLog()
    private var overlayController: OverlayController?
    private var pasteController: PasteController?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var statusItem: NSStatusItem?
    private var fileImageDropsItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let pasteController = PasteController(log: log)
        self.pasteController = pasteController

        let overlayController = OverlayController(settings: settings, log: log) { [weak self] paths, point in
            guard let self else { return }
            self.state.handledDrop = true
            self.overlayController?.hide()
            self.pasteController?.paste(paths: paths, at: point)
            self.state.reset()
        }
        self.overlayController = overlayController

        setupStatusItem()
        requestAccessibilityIfNeeded()
        setupEventMonitors()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "TK"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Log: \(log.url.path)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let accessibilityItem = NSMenuItem(
            title: "Accessibility 권한 열기",
            action: #selector(openAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        self.accessibilityItem = accessibilityItem

        let fileImageDropsItem = NSMenuItem(
            title: "파일/이미지 드롭도 TK로 처리",
            action: #selector(toggleFileImageDrops),
            keyEquivalent: ""
        )
        fileImageDropsItem.target = self
        menu.addItem(fileImageDropsItem)
        self.fileImageDropsItem = fileImageDropsItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
        updateMenuState()
    }

    private func setupEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func requestAccessibilityIfNeeded() {
        if AccessibilityPermission.isTrusted(prompt: false) {
            log.append("Accessibility permission is trusted.")
            updateMenuState()
            return
        }

        log.append("Accessibility permission is missing; requesting permission prompt.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            _ = AccessibilityPermission.isTrusted(prompt: true)
            self.updateMenuState()
        }
    }

    private func handle(_ event: NSEvent) {
        let point = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            let ownerName = WindowFinder.ownerName(at: point)
            state.reset()
            state.sourceIsTransmit = WindowFinder.isTransmit(ownerName: ownerName)
            state.startPoint = point

        case .leftMouseDragged:
            guard state.sourceIsTransmit, let startPoint = state.startPoint else { return }

            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y

            guard dx * dx + dy * dy > dragThresholdSquared else { return }
            guard !state.overlaysShown else { return }

            state.overlaysShown = true
            overlayController?.show()

        case .leftMouseUp:
            guard state.sourceIsTransmit else { return }

            if state.overlaysShown && !state.handledDrop {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.overlayController?.hide()
                    self?.state.reset()
                }
            } else {
                overlayController?.hide()
                state.reset()
            }

        default:
            break
        }
    }

    @objc
    private func toggleFileImageDrops() {
        settings.handleFileImageDrops.toggle()
        updateMenuState()

        let stateText = settings.handleFileImageDrops ? "enabled" : "disabled"
        log.append("File/image fallback drops \(stateText).")
    }

    @objc
    private func openAccessibilityPermission() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        updateMenuState()
    }

    private func updateMenuState() {
        fileImageDropsItem?.state = settings.handleFileImageDrops ? .on : .off
        accessibilityItem?.state = AccessibilityPermission.isTrusted(prompt: false) ? .on : .off
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
