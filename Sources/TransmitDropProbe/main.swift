import AppKit
import Foundation

private let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
private let legacyURLType = NSPasteboard.PasteboardType("NSURLPboardType")
private let legacyStringType = NSPasteboard.PasteboardType("NSStringPboardType")

private let extraDraggedTypes: [NSPasteboard.PasteboardType] = [
    .fileURL,
    .URL,
    .string,
    .init("public.file-url"),
    .init("public.url"),
    .init("public.utf8-plain-text"),
    .init("public.plain-text"),
    .init("public.text"),
    .init("public.data"),
    .init("com.apple.pasteboard.promised-file-content-type"),
    .init("com.apple.pasteboard.promised-file-url"),
    .init("com.apple.NSFilePromiseItemMetaData"),
    legacyFilenamesType,
    legacyURLType,
    legacyStringType,
]

@MainActor
private final class LogStore {
    let logURL: URL
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.logURL = root.appendingPathComponent("TransmitDropProbe.log")
    }

    func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\n===== \(timestamp) =====\n\(message)\n"

        if let textView {
            textView.textStorage?.append(NSAttributedString(string: entry))
            textView.scrollToEndOfDocument(nil)
        }

        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}

private final class DropProbeView: NSView {
    private let label = NSTextField(labelWithString: "Transmit 파일/폴더를 여기에 드롭")
    private let detailLabel = NSTextField(labelWithString: "")
    private var logStore: LogStore?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func attach(logStore: LogStore) {
        self.logStore = logStore
        detailLabel.stringValue = "로그: \(logStore.logURL.path)"
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.separatorColor.cgColor

        registerForDraggedTypes(extraDraggedTypes)

        label.font = .boldSystemFont(ofSize: 22)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.systemBlue.cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor.systemGreen.cgColor

        let report = DragReport(pasteboard: sender.draggingPasteboard)
        logStore?.append(report.render())

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.normalizedPaths.joined(separator: "\n\n"), forType: .string)

        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

private struct DragReport {
    let pasteboard: NSPasteboard
    let normalizedPaths: [String]

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        self.normalizedPaths = DragReport.extractNormalizedPaths(from: pasteboard)
    }

    func render() -> String {
        var lines: [String] = []

        lines.append("Pasteboard name: \(pasteboard.name.rawValue)")
        lines.append("Pasteboard changeCount: \(pasteboard.changeCount)")
        lines.append("")
        lines.append("Top-level types:")
        if pasteboard.types?.isEmpty == false {
            for type in pasteboard.types ?? [] {
                lines.append("- \(type.rawValue)")
            }
        } else {
            lines.append("- <none>")
        }

        lines.append("")
        lines.append("Normalized path candidates:")
        if normalizedPaths.isEmpty {
            lines.append("- <none>")
        } else {
            for path in normalizedPaths {
                lines.append("- \(path)")
            }
        }

        lines.append("")
        lines.append("readObjects(URL):")
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if urls.isEmpty {
            lines.append("- <none>")
        } else {
            for url in urls {
                lines.append("- absoluteString: \(url.absoluteString)")
                lines.append("  path: \(decodedPath(from: url))")
            }
        }

        lines.append("")
        lines.append("Legacy filenames property list:")
        if let values = pasteboard.propertyList(forType: legacyFilenamesType) {
            lines.append(previewPropertyList(values, indent: "- "))
        } else {
            lines.append("- <none>")
        }

        lines.append("")
        lines.append("Pasteboard items:")
        let items = pasteboard.pasteboardItems ?? []
        if items.isEmpty {
            lines.append("- <none>")
        } else {
            for (index, item) in items.enumerated() {
                lines.append("- item[\(index)]")
                for type in item.types {
                    lines.append("  type: \(type.rawValue)")
                    if let string = item.string(forType: type), !string.isEmpty {
                        lines.append("  string: \(preview(string))")
                    } else if let data = item.data(forType: type) {
                        lines.append("  data: \(data.count) bytes \(hexPreview(data))")
                    } else {
                        lines.append("  value: <unreadable>")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func extractNormalizedPaths(from pasteboard: NSPasteboard) -> [String] {
        var candidates: [String] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                appendURL(url, to: &candidates)
            }
        }

        if let legacyPaths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] {
            candidates.append(contentsOf: legacyPaths)
        }

        let directTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .URL,
            .string,
            legacyURLType,
            legacyStringType,
            .init("public.file-url"),
            .init("public.url"),
            .init("public.utf8-plain-text"),
            .init("public.plain-text"),
            .init("public.text"),
        ]

        for type in directTypes {
            if let string = pasteboard.string(forType: type), !string.isEmpty {
                appendStringCandidates(string, to: &candidates)
            }
        }

        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let string = item.string(forType: type), !string.isEmpty {
                    appendStringCandidates(string, to: &candidates)
                }
            }
        }

        var seen = Set<String>()
        var output: [String] = []

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.contains("/") else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }

        return output
    }

    private static func appendURL(_ url: URL, to candidates: inout [String]) {
        if url.isFileURL {
            candidates.append(url.path.removingPercentEncoding ?? url.path)
        } else {
            candidates.append(decodedPath(from: url))
        }
    }

    private static func appendStringCandidates(_ value: String, to candidates: inout [String]) {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let url = URL(string: text), url.scheme != nil {
                appendURL(url, to: &candidates)
            } else {
                candidates.append(text.removingPercentEncoding ?? text)
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transmit Drop Probe"
        window.center()
        window.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let probe = DropProbeView()
        probe.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = "TransmitDropProbe ready.\n\n1. Transmit 파일/폴더를 위 영역에 드롭하세요.\n2. 드롭 payload type과 normalized path 후보가 여기에 표시됩니다.\n3. normalized path는 일반 클립보드에도 복사됩니다.\n"
        scrollView.documentView = textView

        let logStore = LogStore(textView: textView)
        probe.attach(logStore: logStore)

        root.addArrangedSubview(probe)
        root.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            probe.heightAnchor.constraint(equalToConstant: 170),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private func decodedPath(from url: URL) -> String {
    if #available(macOS 13.0, *) {
        return url.path(percentEncoded: false)
    }

    return url.path.removingPercentEncoding ?? url.path
}

private func preview(_ value: String, limit: Int = 1200) -> String {
    let singleLine = value.replacingOccurrences(of: "\n", with: "\\n")
    if singleLine.count <= limit {
        return singleLine
    }

    let index = singleLine.index(singleLine.startIndex, offsetBy: limit)
    return String(singleLine[..<index]) + "... <truncated>"
}

private func previewPropertyList(_ value: Any, indent: String) -> String {
    if let array = value as? [Any] {
        if array.isEmpty {
            return "\(indent)<empty array>"
        }
        return array.map { "\(indent)\($0)" }.joined(separator: "\n")
    }

    return "\(indent)\(value)"
}

private func hexPreview(_ data: Data, limit: Int = 48) -> String {
    data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
