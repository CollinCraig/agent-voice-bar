import AppKit
import AVFoundation
import CoreServices
import Foundation
import UserNotifications

enum Theme {
    static let background = NSColor(red: 0.040, green: 0.050, blue: 0.060, alpha: 1)
    static let panel = NSColor(red: 0.068, green: 0.082, blue: 0.096, alpha: 1)
    static let elevated = NSColor(red: 0.090, green: 0.112, blue: 0.128, alpha: 1)
    static let bubble = NSColor(red: 0.100, green: 0.128, blue: 0.148, alpha: 1)
    static let border = NSColor(red: 0.170, green: 0.245, blue: 0.278, alpha: 1)
    static let cyan = NSColor(red: 0.225, green: 0.820, blue: 0.980, alpha: 1)
    static let green = NSColor(red: 0.470, green: 0.920, blue: 0.680, alpha: 1)
    static let amber = NSColor(red: 1.000, green: 0.710, blue: 0.360, alpha: 1)
    static let playing = NSColor(red: 0.360, green: 0.730, blue: 1.000, alpha: 1)
    static let text = NSColor(red: 0.925, green: 0.955, blue: 0.970, alpha: 1)
    static let muted = NSColor(red: 0.595, green: 0.655, blue: 0.690, alpha: 1)
}

struct VoiceConfig: Codable {
    var mode: String = "autoplay"
    var speed: String = "1.35"
    var replay_speed: String = "1.00"
    var temperature: String = "0.45"
    var top_p: String = "0.85"
    var voice: String = "Chelsie"
    var max_chars: Int = 1200

    init() {}

    enum CodingKeys: String, CodingKey {
        case mode
        case speed
        case replay_speed
        case temperature
        case top_p
        case voice
        case max_chars
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(String.self, forKey: .mode) ?? "autoplay"
        speed = try values.decodeIfPresent(String.self, forKey: .speed) ?? "1.35"
        replay_speed = try values.decodeIfPresent(String.self, forKey: .replay_speed) ?? "1.00"
        temperature = try values.decodeIfPresent(String.self, forKey: .temperature) ?? "0.45"
        top_p = try values.decodeIfPresent(String.self, forKey: .top_p) ?? "0.85"
        voice = try values.decodeIfPresent(String.self, forKey: .voice) ?? "Chelsie"
        max_chars = try values.decodeIfPresent(Int.self, forKey: .max_chars) ?? 1200
    }
}

struct VoiceItem: Codable {
    var id: String?
    var created_at: String?
    var ready_at: String?
    var source: String?
    var title: String?
    var priority: String?
    var mode: String?
    var status: String?
    var voice: String?
    var speed: String?
    var temperature: String?
    var top_p: String?
    var text: String?
    var speech_text: String?
    var file: String?
    var error: String?

    var stableKey: String {
        id ?? file ?? created_at ?? UUID().uuidString
    }

    var displayText: String {
        if status == "failed", let error {
            return "Failed to render audio: \(error)"
        }
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text ?? "(empty)"
        return trimmedTitle.isEmpty ? body : "\(trimmedTitle)\n\(body)"
    }

    var displayTitle: String {
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        return String((text ?? "Voice message").prefix(72))
    }
}

struct VoiceState: Codable {
    var last: VoiceItem?
    var updated_at: String?
    var config: VoiceConfig?
}

struct VoiceCommand: Codable {
    var command: String
    var text: String?
}

final class VoiceStore {
    let appDir: URL
    let configURL: URL
    let stateURL: URL
    let pronunciationsURL: URL
    let queueURL: URL
    let commandURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDir = support.appendingPathComponent("AgentVoiceBar", isDirectory: true)
        configURL = appDir.appendingPathComponent("config.json")
        stateURL = appDir.appendingPathComponent("state.json")
        pronunciationsURL = appDir.appendingPathComponent("pronunciations.json")
        queueURL = appDir.appendingPathComponent("queue.jsonl")
        commandURL = appDir.appendingPathComponent("command.json")
    }

    func readConfig() -> VoiceConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(VoiceConfig.self, from: data) else {
            return VoiceConfig()
        }
        return decoded
    }

    func writeConfig(_ config: VoiceConfig) {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func readState() -> VoiceState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(VoiceState.self, from: data)
    }

    func storageSignature() -> String {
        let urls = [configURL, stateURL, queueURL, commandURL]
        return urls.map { url in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
            return "\(url.lastPathComponent):\(modified)"
        }.joined(separator: "|")
    }

    func recentItems(limit: Int = 300) -> [VoiceItem] {
        guard let content = try? String(contentsOf: queueURL, encoding: .utf8) else { return [] }
        var order: [String] = []
        var byID: [String: VoiceItem] = [:]
        for line in content.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let item = try? JSONDecoder().decode(VoiceItem.self, from: data) else {
                continue
            }
            let key = item.id ?? UUID().uuidString
            if byID[key] == nil {
                order.append(key)
            }
            byID[key] = item
        }
        let selectedOrder = limit > 0 ? Array(order.suffix(limit)) : order
        return selectedOrder.compactMap { byID[$0] }.reversed()
    }

    func clearInbox() {
        try? "".write(to: queueURL, atomically: true, encoding: .utf8)
        let state = VoiceState(last: nil, updated_at: ISO8601DateFormatter().string(from: Date()), config: readConfig())
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    func archiveItem(matching key: String?) {
        guard let key, !key.isEmpty,
              let content = try? String(contentsOf: queueURL, encoding: .utf8) else { return }
        var remainingLines: [String] = []
        var lastItem: VoiceItem?
        for line in content.split(separator: "\n") {
            let text = String(line)
            guard let data = text.data(using: .utf8),
                  let item = try? JSONDecoder().decode(VoiceItem.self, from: data) else {
                remainingLines.append(text)
                continue
            }
            let itemKey = item.stableKey
            if itemKey == key { continue }
            remainingLines.append(text)
            lastItem = item
        }
        try? (remainingLines.joined(separator: "\n") + (remainingLines.isEmpty ? "" : "\n")).write(to: queueURL, atomically: true, encoding: .utf8)
        let state = VoiceState(last: lastItem, updated_at: ISO8601DateFormatter().string(from: Date()), config: readConfig())
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    func consumeCommand() -> VoiceCommand? {
        guard let data = try? Data(contentsOf: commandURL),
              let command = try? JSONDecoder().decode(VoiceCommand.self, from: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: commandURL)
        return command
    }

    func appendManualItem(_ item: VoiceItem) {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(item),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: queueURL.path),
           let handle = try? FileHandle(forWritingTo: queueURL) {
            handle.seekToEndOfFile()
            if let bytes = "\(line)\n".data(using: .utf8) {
                handle.write(bytes)
            }
            try? handle.close()
        } else {
            try? "\(line)\n".write(to: queueURL, atomically: true, encoding: .utf8)
        }
        let state = VoiceState(last: item, updated_at: item.ready_at ?? item.created_at, config: readConfig())
        if let stateData = try? JSONEncoder().encode(state) {
            try? stateData.write(to: stateURL, options: .atomic)
        }
    }
}

final class ReplayBubbleButton: NSButton {
    var filePath: String?
    var itemID: String?
}

final class InboxDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class BubbleRow: NSView {
    let item: VoiceItem

    init(item: VoiceItem, isPlaying: Bool, isExpanded: Bool, bubbleWidth: CGFloat, target: AnyObject, action: Selector) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = Theme.panel.cgColor
        layer?.borderColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(0.56).cgColor
        layer?.borderWidth = 1

        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 9
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        root.translatesAutoresizingMaskIntoConstraints = false

        let avatar = NSView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 14
        avatar.layer?.backgroundColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(0.24).cgColor
        avatar.layer?.borderColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(0.72).cgColor
        avatar.layer?.borderWidth = 1
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
        ])

        let glyph = NSTextField(labelWithString: glyphText(for: item, isPlaying: isPlaying))
        glyph.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        glyph.textColor = color(for: item.status, isPlaying: isPlaying)
        glyph.alignment = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
        ])

        let bubble = NSStackView()
        bubble.orientation = .vertical
        bubble.spacing = 6
        bubble.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 9
        bubble.layer?.backgroundColor = Theme.bubble.cgColor

        let header = NSTextField(labelWithString: metaText(for: item, isPlaying: isPlaying))
        header.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        header.textColor = color(for: item.status, isPlaying: isPlaying)

        let body = NSTextField(wrappingLabelWithString: item.displayText)
        body.font = .systemFont(ofSize: 12.8, weight: .regular)
        body.textColor = Theme.text
        body.maximumNumberOfLines = isExpanded ? 0 : 2
        body.lineBreakMode = isExpanded ? .byWordWrapping : .byTruncatingTail

        let footer = NSTextField(labelWithString: footerText(for: item, isPlaying: isPlaying, isExpanded: isExpanded))
        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = isPlaying ? Theme.playing : Theme.muted

        let overlay = ReplayBubbleButton(title: "", target: target, action: action)
        overlay.isBordered = false
        overlay.filePath = item.file
        overlay.itemID = item.stableKey
        overlay.isEnabled = true
        overlay.toolTip = item.file == nil ? "Show full message" : (isPlaying ? "Stop playback" : "Replay and expand")
        overlay.translatesAutoresizingMaskIntoConstraints = false

        addSubview(root)
        addSubview(overlay)
        root.addArrangedSubview(avatar)
        root.addArrangedSubview(bubble)
        bubble.addArrangedSubview(header)
        bubble.addArrangedSubview(body)
        bubble.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.widthAnchor.constraint(equalToConstant: bubbleWidth),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func metaText(for item: VoiceItem, isPlaying: Bool) -> String {
        let source = (item.source ?? "agent").uppercased()
        let mode = item.mode?.capitalized ?? "Message"
        let status = isPlaying ? "Playing" : (item.status?.capitalized ?? "Queued")
        let priority = (item.priority ?? "normal").uppercased()
        return priority == "NORMAL" ? "\(source) / \(mode) / \(status)" : "\(priority) / \(source) / \(status)"
    }

    private func bodyText(for item: VoiceItem) -> String {
        return item.displayText
    }

    private func glyphText(for item: VoiceItem, isPlaying: Bool) -> String {
        if isPlaying { return "||" }
        if item.status == "queued" { return ".." }
        return item.status == "ready" ? ">" : "..."
    }

    private func footerText(for item: VoiceItem, isPlaying: Bool, isExpanded: Bool) -> String {
        if isPlaying { return "Playing now - click to stop" }
        if isExpanded && item.file != nil { return "Full prompt shown - click to replay" }
        if isExpanded { return "Full prompt shown" }
        if item.source == "app" && item.file == nil { return "Notification only" }
        return item.file == nil ? "Click to expand" : "Click to replay"
    }

    private func color(for status: String?, isPlaying: Bool) -> NSColor {
        if isPlaying { return Theme.playing }
        switch status {
        case "ready": return Theme.green
        case "queued": return Theme.amber
        case "generating": return .systemOrange
        case "failed": return .systemRed
        default: return Theme.muted
        }
    }
}

final class DashboardViewController: NSViewController {
    let store: VoiceStore
    var onReplayFile: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onArchiveItem: ((String?) -> Void)?
    var onClearInbox: (() -> Void)?

    private var playingFile: String?
    private var selectedItemKey: String?
    private let listScrollView = NSScrollView()
    private let listDocument = InboxDocumentView()
    private let detailTitle = NSTextField(labelWithString: "Select a message")
    private let detailMeta = NSTextField(labelWithString: "Agent inbox")
    private let detailText = NSTextView()
    private let replayButton = NSButton(title: "Replay", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let archiveButton = NSButton(title: "Archive", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    init(store: VoiceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 680))
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.background.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        let title = NSTextField(labelWithString: "Agent Voice Bar")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.textColor = Theme.text
        let subtitle = NSTextField(labelWithString: "Agent inbox, local speech rendering, replay history")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = Theme.muted
        titleStack.addArrangedSubview(title)
        titleStack.addArrangedSubview(subtitle)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for button in [replayButton, stopButton, archiveButton, clearButton, refreshButton] {
            button.bezelStyle = .rounded
        }
        replayButton.target = self
        replayButton.action = #selector(replayTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        archiveButton.target = self
        archiveButton.action = #selector(archiveTapped)
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer)
        for button in [replayButton, stopButton, archiveButton, clearButton, refreshButton] {
            header.addArrangedSubview(button)
        }
        root.addArrangedSubview(header)

        let body = NSStackView()
        body.orientation = .horizontal
        body.spacing = 14
        body.alignment = .top
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(body)

        listDocument.wantsLayer = true
        listDocument.layer?.backgroundColor = NSColor.clear.cgColor
        listScrollView.documentView = listDocument
        listScrollView.hasVerticalScroller = true
        listScrollView.drawsBackground = false
        listScrollView.borderType = .noBorder
        let listPanel = panel(listScrollView)
        listPanel.widthAnchor.constraint(equalToConstant: 510).isActive = true
        body.addArrangedSubview(listPanel)

        let detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.spacing = 10
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        detailTitle.textColor = Theme.text
        detailTitle.maximumNumberOfLines = 2
        detailMeta.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        detailMeta.textColor = Theme.cyan
        detailText.isEditable = false
        detailText.drawsBackground = false
        detailText.textColor = Theme.text
        detailText.font = .systemFont(ofSize: 14, weight: .regular)
        detailText.textContainerInset = NSSize(width: 4, height: 6)
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailText
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detailScroll.borderType = .noBorder
        detailStack.addArrangedSubview(detailTitle)
        detailStack.addArrangedSubview(detailMeta)
        detailStack.addArrangedSubview(detailScroll)
        let detailPanel = panel(detailStack)
        detailPanel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(detailPanel)
    }

    private func panel(_ content: NSView) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.backgroundColor = Theme.panel.cgColor
        box.layer?.borderColor = Theme.border.cgColor
        box.layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return box
    }

    func setPlayingFile(_ file: String?) {
        playingFile = file
        if let file,
           let item = store.recentItems(limit: 0).first(where: { $0.file == file }) {
            selectedItemKey = item.stableKey
        }
        rebuildList()
        updateDetail()
    }

    func reload() {
        let items = store.recentItems(limit: 0)
        if selectedItemKey == nil {
            selectedItemKey = items.first?.stableKey
        }
        rebuildList()
        updateDetail()
    }

    private func rebuildList() {
        for subview in listDocument.subviews {
            subview.removeFromSuperview()
        }
        let items = store.recentItems(limit: 0)
        let width: CGFloat = max(480, listScrollView.contentSize.width)
        if items.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No agent messages yet. Incoming MCP speech requests will appear here.")
            empty.textColor = Theme.muted
            empty.font = .systemFont(ofSize: 13)
            empty.frame = NSRect(x: 12, y: 16, width: width - 24, height: 54)
            listDocument.addSubview(empty)
            listDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(560, listScrollView.contentSize.height))
            return
        }
        var y: CGFloat = 0
        for item in items {
            let isExpanded = item.stableKey == selectedItemKey
            let bubbleWidth = min(420, max(300, width - 74))
            let rowHeight = height(for: item, width: width, isExpanded: isExpanded)
            let row = BubbleRow(item: item, isPlaying: item.file == playingFile, isExpanded: isExpanded, bubbleWidth: bubbleWidth, target: self, action: #selector(messageTapped(_:)))
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
            listDocument.addSubview(row)
            y += rowHeight + 8
        }
        listDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(560, y))
    }

    private func height(for item: VoiceItem, width: CGFloat, isExpanded: Bool) -> CGFloat {
        if !isExpanded { return 92 }
        let bubbleWidth = min(420, max(300, width - 74))
        let bodyHeight = item.displayText.boundingRect(
            with: NSSize(width: bubbleWidth - 22, height: 1600),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 12.8, weight: .regular)]
        ).height
        return min(360, max(124, ceil(bodyHeight) + 74))
    }

    private func updateDetail() {
        let item = store.recentItems(limit: 0).first { $0.stableKey == selectedItemKey }
        guard let item else {
            detailTitle.stringValue = "Select a message"
            detailMeta.stringValue = "Agent inbox"
            detailText.string = ""
            replayButton.isEnabled = false
            archiveButton.isEnabled = false
            return
        }
        detailTitle.stringValue = item.displayTitle
        let source = (item.source ?? "agent").uppercased()
        let status = (item.status ?? "queued").uppercased()
        let mode = (item.mode ?? "message").uppercased()
        let created = item.created_at ?? "unknown time"
        detailMeta.stringValue = "\(source) / \(mode) / \(status) / \(created)"
        detailText.string = item.displayText
        replayButton.isEnabled = item.file != nil
        archiveButton.isEnabled = true
    }

    @objc private func messageTapped(_ sender: ReplayBubbleButton) {
        selectedItemKey = sender.itemID ?? sender.filePath
        rebuildList()
        updateDetail()
        if let file = sender.filePath {
            onReplayFile?(file)
        }
    }

    @objc private func replayTapped() {
        guard let item = store.recentItems(limit: 0).first(where: { $0.stableKey == selectedItemKey }),
              let file = item.file else { return }
        onReplayFile?(file)
    }

    @objc private func stopTapped() { onStop?() }
    @objc private func archiveTapped() { onArchiveItem?(selectedItemKey) }
    @objc private func clearTapped() { onClearInbox?() }
    @objc private func refreshTapped() { reload() }
}

final class VoicePopoverController: NSViewController, NSTextFieldDelegate {
    let store: VoiceStore
    var onReplayLast: (() -> Void)?
    var onReplayFile: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onSpeakTest: (() -> Void)?
    var onRequestNotifications: (() -> Void)?
    var onTestNotification: (() -> Void)?
    var onOpenNotificationSettings: (() -> Void)?
    var onOpenPronunciations: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onRunDoctor: (() -> Void)?
    var onArchiveItem: ((String?) -> Void)?
    var onClearInbox: (() -> Void)?
    var onQuit: (() -> Void)?
    var onConfigChanged: (() -> Void)?
    var onReplayRateChanged: ((Float) -> Void)?
    private var playingFile: String?
    private var expandedItemID: String?
    private var tuningVisible = false
    private var controlsPanel: NSView?

    private let modeControl = NSSegmentedControl(labels: ["Speak", "Notify", "DND"], trackingMode: .selectOne, target: nil, action: nil)
    private let filterControl = NSSegmentedControl(labels: ["All", "Ready", "Active"], trackingMode: .selectOne, target: nil, action: nil)
    private let voiceField = NSTextField(string: "Chelsie")
    private let speedSlider = NSSlider(value: 1.35, minValue: 1.00, maxValue: 1.65, target: nil, action: nil)
    private let speedValueLabel = NSTextField(labelWithString: "1.35x")
    private let replaySpeedSlider = NSSlider(value: 1.00, minValue: 0.70, maxValue: 1.80, target: nil, action: nil)
    private let replaySpeedValueLabel = NSTextField(labelWithString: "1.00x")
    private let temperatureSlider = NSSlider(value: 0.45, minValue: 0.20, maxValue: 0.80, target: nil, action: nil)
    private let temperatureValueLabel = NSTextField(labelWithString: "0.45")
    private let topPSlider = NSSlider(value: 0.85, minValue: 0.65, maxValue: 0.98, target: nil, action: nil)
    private let topPValueLabel = NSTextField(labelWithString: "0.85")
    private let statusLabel = NSTextField(labelWithString: "Waiting for messages")
    private let notificationLabel = NSTextField(labelWithString: "Notifications: checking")
    private let controlsTitle = NSTextField(labelWithString: "Voice Tuning")
    private let inboxCountLabel = NSTextField(labelWithString: "0 messages")
    private let notificationTitleLabel = NSTextField(labelWithString: "System")
    private let inboxScrollView = NSScrollView()
    private let inboxDocument = InboxDocumentView()
    private let replayButton = NSButton(title: "Replay Last", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let speakTestButton = NSButton(title: "Speak Test", target: nil, action: nil)
    private let requestNotificationsButton = NSButton(title: "Request", target: nil, action: nil)
    private let testNotificationButton = NSButton(title: "Test", target: nil, action: nil)
    private let doctorButton = NSButton(title: "Doctor", target: nil, action: nil)
    private let tuneButton = NSButton(title: "Tune", target: nil, action: nil)
    private let dashboardButton = NSButton(title: "Dashboard", target: nil, action: nil)
    private let archiveButton = NSButton(title: "Archive", target: nil, action: nil)
    private let clearInboxButton = NSButton(title: "Clear", target: nil, action: nil)

    init(store: VoiceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 760))
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.background.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reload()
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
        root.detachesHiddenViews = true
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let icon = NSImageView()
        icon.image = NSImage(named: "AgentVoiceBarIcon")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
        ])

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 2
        let title = NSTextField(labelWithString: "Agent Voice Bar")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.textColor = Theme.text
        let subtitle = NSTextField(labelWithString: "Local agent speech inbox")
        subtitle.textColor = Theme.muted
        subtitle.font = .systemFont(ofSize: 12)
        titleStack.addArrangedSubview(title)
        titleStack.addArrangedSubview(subtitle)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(statusDot())
        root.addArrangedSubview(header)

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.textColor = Theme.muted

        let deliveryLabel = NSTextField(labelWithString: "Delivery")
        deliveryLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        deliveryLabel.textColor = Theme.muted
        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.widthAnchor.constraint(equalToConstant: 208).isActive = true

        let voiceSummary = NSStackView()
        voiceSummary.orientation = .horizontal
        voiceSummary.alignment = .centerY
        voiceSummary.spacing = 7
        voiceSummary.addArrangedSubview(deliveryLabel)
        voiceSummary.addArrangedSubview(modeControl)
        let voiceSummarySpacer = NSView()
        voiceSummarySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tuneButton.bezelStyle = .rounded
        tuneButton.target = self
        tuneButton.action = #selector(toggleTuningTapped)
        speakTestButton.bezelStyle = .rounded
        speakTestButton.title = "Test"
        speakTestButton.target = self
        speakTestButton.action = #selector(speakTestTapped)
        voiceSummary.addArrangedSubview(voiceSummarySpacer)
        voiceSummary.addArrangedSubview(tuneButton)
        voiceSummary.addArrangedSubview(speakTestButton)
        root.addArrangedSubview(panel(voiceSummary, fill: false, padding: 8))

        let inboxSectionHeader = NSStackView()
        inboxSectionHeader.orientation = .vertical
        inboxSectionHeader.spacing = 7

        let inboxHeader = NSStackView()
        inboxHeader.orientation = .horizontal
        inboxHeader.alignment = .centerY
        let inboxTitleStack = NSStackView()
        inboxTitleStack.orientation = .vertical
        inboxTitleStack.spacing = 1
        let inboxTitle = NSTextField(labelWithString: "Inbox")
        inboxTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        inboxTitle.textColor = Theme.text
        inboxCountLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        inboxCountLabel.textColor = Theme.muted
        inboxTitleStack.addArrangedSubview(inboxTitle)
        inboxTitleStack.addArrangedSubview(inboxCountLabel)
        let inboxSpacer = NSView()
        inboxSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dashboardButton.bezelStyle = .rounded
        dashboardButton.target = self
        dashboardButton.action = #selector(openDashboardTapped)
        inboxHeader.addArrangedSubview(inboxTitleStack)
        inboxHeader.addArrangedSubview(inboxSpacer)
        inboxHeader.addArrangedSubview(dashboardButton)
        inboxSectionHeader.addArrangedSubview(inboxHeader)

        let inboxActions = NSStackView()
        inboxActions.orientation = .horizontal
        inboxActions.alignment = .centerY
        inboxActions.spacing = 8
        filterControl.selectedSegment = 0
        filterControl.controlSize = .small
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        replayButton.bezelStyle = .rounded
        replayButton.title = "Replay"
        replayButton.target = self
        replayButton.action = #selector(replayTapped)
        stopButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        archiveButton.bezelStyle = .rounded
        archiveButton.target = self
        archiveButton.action = #selector(archiveTapped)
        clearInboxButton.bezelStyle = .rounded
        clearInboxButton.target = self
        clearInboxButton.action = #selector(clearInboxTapped)
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inboxActions.addArrangedSubview(filterControl)
        inboxActions.addArrangedSubview(actionSpacer)
        inboxActions.addArrangedSubview(replayButton)
        inboxActions.addArrangedSubview(stopButton)
        inboxActions.addArrangedSubview(archiveButton)
        inboxActions.addArrangedSubview(clearInboxButton)
        inboxSectionHeader.addArrangedSubview(inboxActions)
        root.addArrangedSubview(inboxSectionHeader)

        inboxDocument.wantsLayer = true
        inboxDocument.layer?.backgroundColor = NSColor.clear.cgColor
        inboxDocument.frame = NSRect(x: 0, y: 0, width: 440, height: 396)
        inboxScrollView.documentView = inboxDocument
        inboxScrollView.hasVerticalScroller = true
        inboxScrollView.drawsBackground = false
        inboxScrollView.borderType = .noBorder
        inboxScrollView.translatesAutoresizingMaskIntoConstraints = false
        let inboxPanel = NSView()
        inboxPanel.translatesAutoresizingMaskIntoConstraints = false
        inboxPanel.wantsLayer = true
        inboxPanel.layer?.backgroundColor = Theme.panel.cgColor
        inboxPanel.layer?.cornerRadius = 8
        inboxPanel.layer?.borderColor = Theme.border.cgColor
        inboxPanel.layer?.borderWidth = 1
        inboxPanel.addSubview(inboxScrollView)
        NSLayoutConstraint.activate([
            inboxPanel.heightAnchor.constraint(equalToConstant: 390),
            inboxScrollView.leadingAnchor.constraint(equalTo: inboxPanel.leadingAnchor, constant: 10),
            inboxScrollView.trailingAnchor.constraint(equalTo: inboxPanel.trailingAnchor, constant: -10),
            inboxScrollView.topAnchor.constraint(equalTo: inboxPanel.topAnchor, constant: 10),
            inboxScrollView.bottomAnchor.constraint(equalTo: inboxPanel.bottomAnchor, constant: -10),
        ])
        root.addArrangedSubview(inboxPanel)

        let controlsShell = NSStackView()
        controlsShell.orientation = .vertical
        controlsShell.spacing = 8
        let controlsHeader = NSStackView()
        controlsHeader.orientation = .horizontal
        controlsHeader.alignment = .centerY
        controlsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        controlsTitle.textColor = Theme.muted
        let controlsSpacer = NSView()
        controlsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlsHeader.addArrangedSubview(controlsTitle)
        controlsHeader.addArrangedSubview(controlsSpacer)
        controlsShell.addArrangedSubview(controlsHeader)

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.spacing = 7
        controls.addArrangedSubview(labeledRow("Voice", voiceField, labelWidth: 62))
        controls.addArrangedSubview(sliderRow("Talk", replaySpeedSlider, replaySpeedValueLabel, labelWidth: 62))
        controls.addArrangedSubview(sliderRow("Render", speedSlider, speedValueLabel, labelWidth: 62))
        controls.addArrangedSubview(sliderRow("Energy", temperatureSlider, temperatureValueLabel, labelWidth: 62))
        controls.addArrangedSubview(sliderRow("Variety", topPSlider, topPValueLabel, labelWidth: 62))
        controlsShell.addArrangedSubview(controls)
        let tuningPanel = panel(controlsShell, fill: false)
        tuningPanel.setContentHuggingPriority(.required, for: .vertical)
        tuningPanel.isHidden = !tuningVisible
        controlsPanel = tuningPanel
        root.addArrangedSubview(tuningPanel)
        voiceField.delegate = self
        voiceField.target = self
        voiceField.action = #selector(voiceChanged)
        voiceField.bezelStyle = .roundedBezel
        voiceField.font = .systemFont(ofSize: 12.5, weight: .medium)
        voiceField.textColor = Theme.text
        voiceField.backgroundColor = Theme.elevated
        for slider in [speedSlider, replaySpeedSlider, temperatureSlider, topPSlider] {
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
        }
        speedSlider.action = #selector(speedSliderChanged)
        replaySpeedSlider.action = #selector(replaySpeedSliderChanged)
        temperatureSlider.action = #selector(temperatureSliderChanged)
        topPSlider.action = #selector(topPSliderChanged)

        let notifyRow = NSStackView()
        notifyRow.orientation = .horizontal
        notifyRow.alignment = .centerY
        notifyRow.spacing = 8
        notificationTitleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        notificationTitleLabel.textColor = Theme.muted
        notificationLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        notificationLabel.textColor = Theme.muted
        let notifySpacer = NSView()
        notifySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        notifyRow.addArrangedSubview(notificationTitleLabel)
        notifyRow.addArrangedSubview(statusLabel)
        notifyRow.addArrangedSubview(notificationLabel)
        notifyRow.addArrangedSubview(notifySpacer)
        for button in [requestNotificationsButton, testNotificationButton, doctorButton] {
            button.bezelStyle = .rounded
            notifyRow.addArrangedSubview(button)
        }
        requestNotificationsButton.target = self
        requestNotificationsButton.action = #selector(requestNotificationsTapped)
        testNotificationButton.target = self
        testNotificationButton.action = #selector(testNotificationTapped)
        doctorButton.target = self
        doctorButton.action = #selector(doctorTapped)
        root.addArrangedSubview(panel(notifyRow, fill: false))

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8
        for (label, action) in [
            ("Notify Settings", #selector(openNotificationSettingsTapped)),
            ("Pronunciations", #selector(openPronunciationsTapped)),
            ("Folder", #selector(openFolderTapped)),
            ("Quit", #selector(quitTapped)),
        ] {
            let button = NSButton(title: label, target: self, action: action)
            button.bezelStyle = .rounded
            bottom.addArrangedSubview(button)
        }
        root.addArrangedSubview(bottom)

        let footer = NSTextField(labelWithString: "Open-source ready: local-first, MCP-friendly, no cloud account required.")
        footer.font = .systemFont(ofSize: 10.5, weight: .medium)
        footer.textColor = Theme.muted
        root.addArrangedSubview(footer)
    }

    private func statusDot() -> NSView {
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.cyan.cgColor
        dot.layer?.cornerRadius = 6
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
        ])
        return dot
    }

    private func panel(_ content: NSView, fill: Bool, padding: CGFloat = 10) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.backgroundColor = Theme.panel.cgColor
        box.layer?.borderColor = Theme.border.cgColor
        box.layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding),
        ])
        if fill {
            box.setContentHuggingPriority(.defaultLow, for: .vertical)
        }
        return box
    }

    private func labeledRow(_ label: String, _ control: NSView, labelWidth: CGFloat = 70) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .secondaryLabelColor
        text.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        row.addArrangedSubview(text)
        row.addArrangedSubview(control)
        return row
    }

    private func sliderRow(_ label: String, _ slider: NSSlider, _ value: NSTextField, labelWidth: CGFloat = 70) -> NSView {
        let row = labeledRow(label, slider, labelWidth: labelWidth) as! NSStackView
        value.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        value.textColor = Theme.muted
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(value)
        return row
    }

    func setPlayingFile(_ file: String?) {
        playingFile = file
        if let file,
           let item = store.recentItems(limit: 80).first(where: { $0.file == file }) {
            expandedItemID = item.stableKey
        }
        rebuildInbox()
    }

    func reload() {
        let config = store.readConfig()
        let state = store.readState()
        let item = state?.last

        refreshNotificationStatus()

        switch config.mode {
        case "notify": modeControl.selectedSegment = 1
        case "silent": modeControl.selectedSegment = 2
        default: modeControl.selectedSegment = 0
        }

        if voiceField.currentEditor() == nil {
            voiceField.stringValue = config.voice
        }
        speedSlider.doubleValue = clampedDouble(config.speed, fallback: 1.35, min: 1.00, max: 1.65)
        replaySpeedSlider.doubleValue = clampedDouble(config.replay_speed, fallback: 1.00, min: 0.70, max: 1.80)
        temperatureSlider.doubleValue = clampedDouble(config.temperature, fallback: 0.45, min: 0.20, max: 0.80)
        topPSlider.doubleValue = clampedDouble(config.top_p, fallback: 0.85, min: 0.65, max: 0.98)
        updateControlLabels()

        let items = store.recentItems(limit: 0)
        let filteredCount = filtered(items).count
        let messageWord = items.count == 1 ? "message" : "messages"
        if filterControl.selectedSegment > 0 {
            inboxCountLabel.stringValue = "\(filteredCount) shown / \(items.count) \(messageWord)"
        } else {
            inboxCountLabel.stringValue = "\(items.count) \(messageWord)"
        }

        let modeText = displayModeName(config.mode)
        let updated = state?.updated_at ?? "never"
        statusLabel.stringValue = "\(modeText) / updated \(shortTimestamp(updated))"
        tuneButton.title = tuningVisible ? "Hide" : "Tune"
        controlsPanel?.isHidden = !tuningVisible

        if let item {
            replayButton.isEnabled = item.file != nil
        } else {
            replayButton.isEnabled = false
        }

        rebuildInbox()
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    if settings.alertSetting == .disabled {
                        self?.setNotificationStatus("Notifications: alerts off", color: .systemOrange)
                    } else {
                        self?.setNotificationStatus("Notifications: ready", color: Theme.cyan)
                    }
                case .denied:
                    self?.setNotificationStatus("Notifications: denied", color: .systemRed)
                case .notDetermined:
                    self?.setNotificationStatus("Notifications: needs permission", color: .systemOrange)
                @unknown default:
                    self?.setNotificationStatus("Notifications: unknown", color: .secondaryLabelColor)
                }
            }
        }
    }

    func setNotificationStatus(_ text: String, color: NSColor) {
        notificationLabel.stringValue = text
        notificationLabel.textColor = color
    }

    private func rebuildInbox() {
        for subview in inboxDocument.subviews {
            subview.removeFromSuperview()
        }
        let items = filtered(store.recentItems(limit: 80))
        let width: CGFloat = max(420, inboxScrollView.contentSize.width)
        if items.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: emptyInboxText())
            empty.textColor = Theme.muted
            empty.font = .systemFont(ofSize: 12.5)
            empty.frame = NSRect(x: 12, y: 14, width: width - 24, height: 44)
            inboxDocument.addSubview(empty)
            inboxDocument.frame = NSRect(x: 0, y: 0, width: width, height: 396)
            return
        }
        var y: CGFloat = 0
        for item in items {
            let itemKey = item.stableKey
            let isExpanded = itemKey == expandedItemID
            let bubbleWidth = max(300, width - 74)
            let rowHeight = height(for: item, width: width, isExpanded: isExpanded)
            let row = BubbleRow(item: item, isPlaying: item.file == playingFile, isExpanded: isExpanded, bubbleWidth: bubbleWidth, target: self, action: #selector(replayBubble(_:)))
            row.translatesAutoresizingMaskIntoConstraints = true
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
            inboxDocument.addSubview(row)
            y += rowHeight + 8
        }
        inboxDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(396, y))
        inboxDocument.needsLayout = true
        inboxDocument.needsDisplay = true
    }

    private func filtered(_ items: [VoiceItem]) -> [VoiceItem] {
        switch filterControl.selectedSegment {
        case 1:
            return items.filter { $0.status == "ready" }
        case 2:
            return items.filter { item in
                guard let status = item.status else { return false }
                return status != "ready"
            }
        default:
            return items
        }
    }

    private func emptyInboxText() -> String {
        switch filterControl.selectedSegment {
        case 1:
            return "No ready messages in this filter yet."
        case 2:
            return "No active renders or failures right now."
        default:
            return "No messages yet. Notify and DND modes still save incoming agent speech here."
        }
    }

    private func displayModeName(_ mode: String) -> String {
        switch mode {
        case "notify": return "Notify"
        case "silent": return "DND"
        default: return "Speak"
        }
    }

    private func shortTimestamp(_ value: String) -> String {
        if value == "never" { return value }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func height(for item: VoiceItem, width: CGFloat, isExpanded: Bool) -> CGFloat {
        if !isExpanded { return 92 }
        let text = item.displayText
        let bubbleWidth = max(300, width - 74)
        let bodyWidth = bubbleWidth - 22
        let bodyHeight = text.boundingRect(
            with: NSSize(width: bodyWidth, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 12.8, weight: .regular)]
        ).height
        return min(280, max(124, ceil(bodyHeight) + 68))
    }

    @objc private func replayBubble(_ sender: ReplayBubbleButton) {
        expandedItemID = sender.itemID ?? sender.filePath
        rebuildInbox()
        if let file = sender.filePath {
            onReplayFile?(file)
        }
    }

    @objc private func filterChanged() {
        rebuildInbox()
        reload()
    }

    @objc private func toggleTuningTapped() {
        tuningVisible.toggle()
        controlsPanel?.isHidden = !tuningVisible
        tuneButton.title = tuningVisible ? "Hide" : "Tune"
        view.window?.setContentSize(NSSize(width: 500, height: tuningVisible ? 860 : 760))
    }

    @objc private func modeChanged() {
        let modes = ["autoplay", "notify", "silent"]
        var config = store.readConfig()
        config.mode = modes[max(0, modeControl.selectedSegment)]
        store.writeConfig(config)
        reload()
        onConfigChanged?()
    }

    @objc private func voiceChanged() {
        var config = store.readConfig()
        config.voice = voiceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Chelsie" : voiceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        store.writeConfig(config)
        onConfigChanged?()
    }

    @objc private func speedSliderChanged() {
        writeSliderConfig { config in
            config.speed = format(speedSlider.doubleValue, digits: 2)
        }
    }

    @objc private func replaySpeedSliderChanged() {
        writeSliderConfig { config in
            config.replay_speed = format(replaySpeedSlider.doubleValue, digits: 2)
        }
        onReplayRateChanged?(Float(replaySpeedSlider.doubleValue))
    }

    @objc private func temperatureSliderChanged() {
        writeSliderConfig { config in
            config.temperature = format(temperatureSlider.doubleValue, digits: 2)
        }
    }

    @objc private func topPSliderChanged() {
        writeSliderConfig { config in
            config.top_p = format(topPSlider.doubleValue, digits: 2)
        }
    }

    private func writeSliderConfig(_ update: (inout VoiceConfig) -> Void) {
        var config = store.readConfig()
        update(&config)
        store.writeConfig(config)
        updateControlLabels()
        onConfigChanged?()
    }

    private func updateControlLabels() {
        speedValueLabel.stringValue = "\(format(speedSlider.doubleValue, digits: 2))x"
        replaySpeedValueLabel.stringValue = "\(format(replaySpeedSlider.doubleValue, digits: 2))x"
        temperatureValueLabel.stringValue = format(temperatureSlider.doubleValue, digits: 2)
        topPValueLabel.stringValue = format(topPSlider.doubleValue, digits: 2)
    }

    private func clampedDouble(_ value: String, fallback: Double, min: Double, max: Double) -> Double {
        let parsed = Double(value) ?? fallback
        return Swift.max(min, Swift.min(max, parsed))
    }

    private func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        voiceChanged()
    }

    @objc private func replayTapped() {
        if let item = store.readState()?.last {
            expandedItemID = item.stableKey
            rebuildInbox()
        }
        onReplayLast?()
    }
    @objc private func stopTapped() { onStop?() }
    @objc private func speakTestTapped() { onSpeakTest?() }
    @objc private func requestNotificationsTapped() { onRequestNotifications?() }
    @objc private func testNotificationTapped() { onTestNotification?() }
    @objc private func doctorTapped() { onRunDoctor?() }
    @objc private func openNotificationSettingsTapped() { onOpenNotificationSettings?() }
    @objc private func openPronunciationsTapped() { onOpenPronunciations?() }
    @objc private func openFolderTapped() { onOpenFolder?() }
    @objc private func openDashboardTapped() { onOpenDashboard?() }
    @objc private func archiveTapped() { onArchiveItem?(expandedItemID ?? store.readState()?.last?.id) }
    @objc private func clearInboxTapped() { onClearInbox?() }
    @objc private func quitTapped() { onQuit?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
    private let store = VoiceStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: NSPanel!
    private var popoverController: VoicePopoverController!
    private var dashboardWindow: NSWindow?
    private var dashboardController: DashboardViewController?
    private var timer: Timer?
    private var lastSeenStateKey: String?
    private var lastStorageSignature: String?
    private var audioPlayer: AVAudioPlayer?
    private var playingFile: String?
    private var playbackWatchdog: Timer?
    private var unreadCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        registerBundleWithLaunchServices()
        configureNotifications(requestPermission: true)
        configurePopover()
        configureStatusItem()
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh(initial: false)
        }
    }

    private func registerBundleWithLaunchServices() {
        let url = Bundle.main.bundleURL as CFURL
        _ = LSRegisterURL(url, true)
    }

    private func configureNotifications(requestPermission: Bool) {
        let replay = UNNotificationAction(identifier: "REPLAY_LAST", title: "Replay", options: [])
        let category = UNNotificationCategory(identifier: "VOICE_MESSAGE", actions: [replay], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        if requestPermission {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    NSLog("Agent Voice Bar notification auth error: \(error.localizedDescription)")
                }
                NSLog("Agent Voice Bar notifications granted: \(granted)")
            }
        }
    }

    private func configurePopover() {
        popoverController = VoicePopoverController(store: store)
        popoverController.onReplayLast = { [weak self] in self?.replayLast() }
        popoverController.onReplayFile = { [weak self] file in self?.replay(file: file) }
        popoverController.onStop = { [weak self] in self?.stopPlayback() }
        popoverController.onSpeakTest = { [weak self] in self?.speakTestLine() }
        popoverController.onRequestNotifications = { [weak self] in self?.requestNotifications() }
        popoverController.onTestNotification = { [weak self] in self?.deliverTestNotification() }
        popoverController.onOpenNotificationSettings = { [weak self] in self?.openNotificationSettings() }
        popoverController.onOpenPronunciations = { [weak self] in self?.openPronunciations() }
        popoverController.onOpenFolder = { [weak self] in self?.openFolder() }
        popoverController.onOpenDashboard = { [weak self] in self?.showDashboard() }
        popoverController.onRunDoctor = { [weak self] in self?.runDoctor() }
        popoverController.onArchiveItem = { [weak self] key in self?.archiveItem(key) }
        popoverController.onClearInbox = { [weak self] in self?.clearInbox() }
        popoverController.onQuit = { NSApp.terminate(nil) }
        popoverController.onConfigChanged = { [weak self] in self?.updateIcon() }
        popoverController.onReplayRateChanged = { [weak self] rate in self?.setReplayRate(rate) }
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Agent Voice Bar"
        panel.titlebarAppearsTransparent = false
        panel.backgroundColor = Theme.background
        panel.isOpaque = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentViewController = popoverController
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
    }

    private func refresh(initial: Bool) {
        let signature = store.storageSignature()
        let shouldReload = initial || signature != lastStorageSignature
        lastStorageSignature = signature

        if let command = store.consumeCommand() {
            handle(command: command)
            popoverController.reload()
            return
        }

        if shouldReload {
            updateIcon()
            popoverController.reload()
            dashboardController?.reload()
        }
        guard let item = store.readState()?.last, let id = item.id else { return }
        let key = "\(id):\(item.status ?? "")"
        if initial {
            lastSeenStateKey = key
            return
        }
        if key != lastSeenStateKey {
            lastSeenStateKey = key
            if item.status == "ready" {
                if !panel.isVisible {
                    unreadCount += 1
                    updateIcon()
                }
                switch item.mode {
                case "autoplay":
                    if let file = item.file, file != playingFile {
                        replay(file: file)
                    }
                case "notify":
                    deliverNotification(for: item)
                default:
                    break
                }
            } else if item.status == "failed" {
                deliverNotification(for: item)
            }
        }
    }

    private func handle(command: VoiceCommand) {
        NSLog("Agent Voice Bar command received: \(command.command)")
        switch command.command {
        case "test_notification":
            deliverManualNotification(text: command.text ?? "Agent Voice Bar debug notification.")
        case "refresh":
            popoverController.reload()
        case "show_panel":
            popoverController.reload()
            showPanel()
        case "replay_last":
            replayLast()
        case "doctor":
            runDoctor(showPanelWhenDone: true)
        default:
            NSLog("Agent Voice Bar unknown command: \(command.command)")
        }
    }

    private func updateIcon() {
        let config = store.readConfig()
        let symbol: String
        let modeName: String
        switch config.mode {
        case "notify":
            symbol = "bell.badge.circle.fill"
            modeName = "Notify"
        case "silent":
            symbol = "speaker.slash.circle.fill"
            modeName = "DND"
        default:
            symbol = "waveform.circle.fill"
            modeName = "Speak"
        }
        if let button = statusItem.button,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Agent Voice") {
            image.isTemplate = true
            button.image = image
            button.title = unreadCount > 0 ? " \(min(unreadCount, 99))" : ""
            button.toolTip = "Agent Voice Bar: \(modeName)"
        }
    }

    @objc private func togglePopover() {
        if panel.isVisible && panel.isKeyWindow {
            panel.orderOut(nil)
        } else {
            popoverController.reload()
            showPanel()
        }
    }

    private func showPanel() {
        NSApp.setActivationPolicy(.regular)
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        positionPanelNearStatusItem()
        unreadCount = 0
        updateIcon()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showDashboard() {
        if dashboardWindow == nil {
            let controller = DashboardViewController(store: store)
            controller.onReplayFile = { [weak self] file in self?.replay(file: file) }
            controller.onStop = { [weak self] in self?.stopPlayback() }
            controller.onArchiveItem = { [weak self] key in self?.archiveItem(key) }
            controller.onClearInbox = { [weak self] in self?.clearInbox() }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Agent Voice Bar Dashboard"
            window.minSize = NSSize(width: 760, height: 520)
            window.backgroundColor = Theme.background
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            dashboardController = controller
            dashboardWindow = window
        }
        dashboardController?.reload()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.center()
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    private func positionPanelNearStatusItem() {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(buttonFrame)
        let panelSize = panel.frame.size
        let visible = screen.visibleFrame
        var x = screenFrame.midX - panelSize.width / 2
        x = max(visible.minX + 12, min(x, visible.maxX - panelSize.width - 12))
        let y = min(visible.maxY - panelSize.height - 10, screenFrame.minY - panelSize.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 12, y)))
    }

    private func deliverNotification(for item: VoiceItem) {
        NSLog("Agent Voice Bar delivering notification for item \(item.id ?? "no-id")")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                if settings.alertSetting == .disabled {
                    NSLog("Agent Voice Bar native notification alerts disabled; using fallback")
                    DispatchQueue.main.async {
                        self.popoverController.setNotificationStatus("Notifications: alerts off - fallback", color: .systemOrange)
                    }
                    _ = self.deliverTerminalNotification(for: item)
                    return
                }
                self.deliverNativeNotification(for: item)
            case .notDetermined:
                self.configureNotifications(requestPermission: true)
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: permission requested", color: .systemOrange)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.deliverNotification(for: item)
                }
            case .denied:
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: denied - fallback", color: .systemRed)
                }
                _ = self.deliverTerminalNotification(for: item)
            @unknown default:
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: unknown - fallback", color: .systemOrange)
                }
                _ = self.deliverTerminalNotification(for: item)
            }
        }
    }

    private func deliverNativeNotification(for item: VoiceItem) {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: item)
        content.subtitle = item.source ?? "Agent Voice Bar"
        content.body = item.text ?? "A new voice message is ready."
        content.sound = .default
        content.categoryIdentifier = "VOICE_MESSAGE"
        content.userInfo = ["file": item.file ?? ""]
        content.threadIdentifier = item.source ?? "Agent Voice Bar"
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .active
        }
        let request = UNNotificationRequest(identifier: item.id ?? UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Agent Voice Bar notification error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: native failed - fallback", color: .systemOrange)
                }
                _ = self.deliverTerminalNotification(for: item)
            } else {
                NSLog("Agent Voice Bar UN notification accepted")
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: sent", color: Theme.green)
                }
            }
        }
    }

    private func deliverTestNotification() {
        deliverManualNotification(text: "Agent Voice Bar notifications are working.")
    }

    private func deliverManualNotification(text: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let item = VoiceItem(
            id: UUID().uuidString,
            created_at: now,
            ready_at: now,
            source: "app",
            title: "Notification test",
            priority: "normal",
            mode: "notify",
            status: "ready",
            voice: "Chelsie",
            speed: nil,
            temperature: nil,
            top_p: nil,
            text: text,
            speech_text: nil,
            file: nil
        )
        store.appendManualItem(item)
        popoverController.reload()
        deliverNotification(for: item)
    }

    private func appendAppMessage(title: String, text: String, priority: String = "normal") {
        let now = ISO8601DateFormatter().string(from: Date())
        let item = VoiceItem(
            id: UUID().uuidString,
            created_at: now,
            ready_at: now,
            source: "app",
            title: title,
            priority: priority,
            mode: "silent",
            status: "ready",
            voice: store.readConfig().voice,
            speed: nil,
            temperature: nil,
            top_p: nil,
            text: text,
            speech_text: nil,
            file: nil
        )
        store.appendManualItem(item)
        lastSeenStateKey = "\(item.id ?? ""):\(item.status ?? "")"
        lastStorageSignature = nil
        popoverController.reload()
        dashboardController?.reload()
    }

    private func runDoctor(showPanelWhenDone: Bool = false) {
        popoverController.setNotificationStatus("Doctor: checking", color: Theme.cyan)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let notificationLine: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationLine = settings.alertSetting == .disabled
                    ? "Native notifications are authorized, but alert banners are off. Fallback notifications will be used."
                    : "Native macOS notifications are authorized and alert banners are enabled."
            case .denied:
                notificationLine = "Native notifications are denied in System Settings. Open Notify Settings or rely on fallback notifications."
            case .notDetermined:
                notificationLine = "Native notification permission has not been granted yet. Use Request in the mini app."
            @unknown default:
                notificationLine = "Native notification status is unknown."
            }
            let terminalNotifierLine = self.terminalNotifierPath() == nil
                ? "terminal-notifier fallback is not installed."
                : "terminal-notifier fallback is installed."
            self.checkBackend { backendLine in
                DispatchQueue.main.async {
                    let config = self.store.readConfig()
                    let mode = self.displayModeName(config.mode)
                    let text = [
                        "Delivery: \(mode)",
                        "Voice: \(config.voice)",
                        "Render speed: \(config.speed)x",
                        "Talk speed: \(config.replay_speed)x",
                        notificationLine,
                        terminalNotifierLine,
                        backendLine,
                        "Bundle id: \(Bundle.main.bundleIdentifier ?? "unknown")",
                    ].joined(separator: "\n")
                    self.appendAppMessage(title: "Setup Doctor", text: text, priority: "high")
                    self.popoverController.setNotificationStatus("Doctor: report in inbox", color: Theme.green)
                    if showPanelWhenDone {
                        self.showPanel()
                    }
                }
            }
        }
    }

    private func checkBackend(completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:51090")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion("Qwen speech backend is not reachable on 127.0.0.1:51090: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion("Qwen speech backend responded with HTTP \(http.statusCode).")
                return
            }
            if let data,
               let text = String(data: data, encoding: .utf8),
               text.contains("speak_text") {
                completion("Qwen speech backend is reachable and exposes speak_text.")
            } else {
                completion("Qwen speech backend responded, but speak_text was not confirmed.")
            }
        }.resume()
    }

    private func deliverTerminalNotification(for item: VoiceItem) -> Bool {
        guard let executable = terminalNotifierPath() else {
            NSLog("Agent Voice Bar terminal-notifier not installed")
            return false
        }
        NSLog("Agent Voice Bar delivering terminal-notifier notification")
        let process = Process()
        process.launchPath = executable
        process.arguments = [
            "-title", "Agent Voice Bar",
            "-subtitle", notificationTitle(for: item),
            "-message", String((item.text ?? "A new voice message is ready.").prefix(240)),
            "-sound", "Glass",
            "-group", item.id ?? "codex-voice-bar",
            "-sender", "com.collincraig.agentvoicebar",
            "-activate", "com.collincraig.agentvoicebar",
        ]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    self.popoverController.setNotificationStatus("Notifications: fallback sent", color: Theme.green)
                }
                return true
            }
            NSLog("Agent Voice Bar terminal-notifier exited with status \(process.terminationStatus)")
            DispatchQueue.main.async {
                self.popoverController.setNotificationStatus("Notifications: fallback failed", color: .systemRed)
            }
            return false
        } catch {
            NSLog("Agent Voice Bar terminal-notifier error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.popoverController.setNotificationStatus("Notifications: fallback failed", color: .systemRed)
            }
            return false
        }
    }

    private func terminalNotifierPath() -> String? {
        [
            "/opt/homebrew/bin/terminal-notifier",
            "/usr/local/bin/terminal-notifier",
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func notificationTitle(for item: VoiceItem) -> String {
        let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if item.status == "failed" { return "Message failed" }
        return "Voice message ready"
    }

    private func requestNotifications() {
        configureNotifications(requestPermission: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.popoverController.reload()
        }
    }

    private func replayLast() {
        guard let file = store.readState()?.last?.file else { return }
        replay(file: file)
    }

    private func replay(file: String) {
        if playingFile == file {
            stopPlayback()
            return
        }
        stopPlayback()

        guard FileManager.default.fileExists(atPath: file) else {
            clearPlaybackState()
            popoverController.setNotificationStatus("Playback: missing file", color: .systemRed)
            appendAppMessage(title: "Playback failed", text: "Audio file was missing:\n\(file)", priority: "high")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: file))
            player.enableRate = true
            player.rate = currentReplayRate()
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            guard player.play() else {
                clearPlaybackState()
                popoverController.setNotificationStatus("Playback: could not start", color: .systemRed)
                return
            }
            playingFile = file
            popoverController.setPlayingFile(file)
            dashboardController?.setPlayingFile(file)
            popoverController.setNotificationStatus("Playback: playing", color: Theme.playing)
            schedulePlaybackWatchdog(for: file, player: player)
        } catch {
            clearPlaybackState()
            popoverController.setNotificationStatus("Playback: \(error.localizedDescription)", color: .systemRed)
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        clearPlaybackState()
        popoverController.setNotificationStatus("Playback: stopped", color: Theme.muted)
    }

    private func setReplayRate(_ rate: Float) {
        if let player = audioPlayer, let file = playingFile {
            player.rate = max(0.5, min(2.0, rate))
            schedulePlaybackWatchdog(for: file, player: player)
        }
    }

    private func currentReplayRate() -> Float {
        let parsed = Float(store.readConfig().replay_speed) ?? 1.0
        return max(0.5, min(2.0, parsed))
    }

    private func displayModeName(_ mode: String) -> String {
        switch mode {
        case "notify": return "Notify"
        case "silent": return "DND"
        default: return "Speak"
        }
    }

    private func schedulePlaybackWatchdog(for file: String, player: AVAudioPlayer) {
        playbackWatchdog?.invalidate()
        let remaining = max(0.5, player.duration - player.currentTime)
        let rate = Double(max(0.5, min(2.0, player.rate)))
        let delay = min(600.0, remaining / rate + 1.25)
        playbackWatchdog = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak player] _ in
            guard let self,
                  let player,
                  self.audioPlayer === player,
                  self.playingFile == file else { return }
            if !player.isPlaying {
                self.clearPlaybackState()
                self.popoverController.setNotificationStatus("Playback: finished", color: Theme.green)
            } else {
                self.schedulePlaybackWatchdog(for: file, player: player)
            }
        }
    }

    private func clearPlaybackState() {
        playbackWatchdog?.invalidate()
        playbackWatchdog = nil
        audioPlayer = nil
        playingFile = nil
        popoverController.setPlayingFile(nil)
        dashboardController?.setPlayingFile(nil)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard audioPlayer === player else { return }
        clearPlaybackState()
        popoverController.setNotificationStatus(flag ? "Playback: finished" : "Playback: stopped", color: flag ? Theme.green : Theme.muted)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else { return }
        clearPlaybackState()
        popoverController.setNotificationStatus("Playback: decode failed", color: .systemRed)
    }

    private func openPronunciations() {
        if !FileManager.default.fileExists(atPath: store.pronunciationsURL.path) {
            try? "{}\n".write(to: store.pronunciationsURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(store.pronunciationsURL)
    }

    private func openFolder() {
        NSWorkspace.shared.open(store.appDir)
    }

    private func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.collincraig.agentvoicebar",
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func clearInbox() {
        stopPlayback()
        store.clearInbox()
        lastSeenStateKey = nil
        lastStorageSignature = nil
        popoverController.reload()
        dashboardController?.reload()
    }

    private func archiveItem(_ key: String?) {
        stopPlayback()
        store.archiveItem(matching: key)
        lastSeenStateKey = nil
        lastStorageSignature = nil
        popoverController.reload()
        dashboardController?.reload()
    }

    private func speakTestLine() {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 99,
            "method": "tools/call",
            "params": [
                "name": "speak_text",
                "arguments": [
                    "source": "Agent Voice Bar",
                    "title": "Local test message",
                    "priority": "normal",
                    "text": "Agent Voice Bar is online. The inbox, clickable replay bubbles, notification mode, and speed controls are ready."
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:51090")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == "REPLAY_LAST" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let file = response.notification.request.content.userInfo["file"] as? String
            await MainActor.run {
                if let file, !file.isEmpty {
                    self.replay(file: file)
                } else {
                    self.replayLast()
                }
                if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                    self.togglePopover()
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
