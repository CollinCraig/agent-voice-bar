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

struct VoiceRules: Codable {
    var sources: [String: String] = [:]

    init() {}

    enum CodingKeys: String, CodingKey {
        case sources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sources = try values.decodeIfPresent([String: String].self, forKey: .sources) ?? [:]
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

    var displayBodyText: String {
        if status == "failed", let error {
            return "Failed to render audio: \(error)"
        }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No message body." : trimmed
    }
}

struct VoiceState: Codable {
    var last: VoiceItem?
    var updated_at: String?
    var config: VoiceConfig?
}

struct PlaybackEvent: Codable {
    var at: String
    var event: String
    var file: String?
    var source: String?
    var title: String?
    var detail: String?
    var duration: Double?
    var rate: Float?
}

func shortPlaybackTime(_ value: String) -> String {
    let parser = ISO8601DateFormatter()
    guard let date = parser.date(from: value) else { return value }
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func displayPlaybackEvent(_ event: String) -> String {
    switch event {
    case "started": return "Started"
    case "queued_autoplay": return "Queued"
    case "finished", "watchdog_finished": return "Played"
    case "stopped": return "Stopped"
    case "skipped": return "Skipped"
    case "missing_file": return "Missing audio"
    case "failed_load": return "Load failed"
    case "failed_start": return "Start failed"
    case "decode_failed": return "Decode failed"
    default: return event.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func playbackFooterText(_ event: PlaybackEvent?) -> String? {
    guard let event else { return nil }
    let label = displayPlaybackEvent(event.event)
    let time = shortPlaybackTime(event.at)
    if let rate = event.rate, ["started", "finished", "watchdog_finished"].contains(event.event) {
        return "\(label) \(time) at \(String(format: "%.2f", rate))x"
    }
    if let detail = event.detail, !detail.isEmpty {
        return "\(label) \(time) - \(detail)"
    }
    return "\(label) \(time)"
}

func playbackFooterText(_ event: PlaybackEvent?, isPlaying: Bool) -> String? {
    guard let event else { return nil }
    if event.event == "started" && !isPlaying {
        return nil
    }
    return playbackFooterText(event)
}

func playbackDetailText(_ event: PlaybackEvent?) -> String? {
    guard let event else { return nil }
    var parts = [
        "\(displayPlaybackEvent(event.event)) at \(shortPlaybackTime(event.at))",
    ]
    if let rate = event.rate {
        parts.append("Rate: \(String(format: "%.2f", rate))x")
    }
    if let duration = event.duration {
        parts.append("Duration: \(String(format: "%.2f", duration))s")
    }
    if let detail = event.detail, !detail.isEmpty {
        parts.append("Detail: \(detail)")
    }
    if let file = event.file, !file.isEmpty {
        parts.append("File: \(file)")
    }
    return parts.joined(separator: "\n")
}

struct VoiceCommand: Codable {
    var command: String
    var text: String?
}

final class VoiceStore {
    let appDir: URL
    let configURL: URL
    let rulesURL: URL
    let stateURL: URL
    let pronunciationsURL: URL
    let queueURL: URL
    let playbackURL: URL
    let commandURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDir = support.appendingPathComponent("AgentVoiceBar", isDirectory: true)
        configURL = appDir.appendingPathComponent("config.json")
        rulesURL = appDir.appendingPathComponent("rules.json")
        stateURL = appDir.appendingPathComponent("state.json")
        pronunciationsURL = appDir.appendingPathComponent("pronunciations.json")
        queueURL = appDir.appendingPathComponent("queue.jsonl")
        playbackURL = appDir.appendingPathComponent("playback.jsonl")
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

    func readRules() -> VoiceRules {
        guard let data = try? Data(contentsOf: rulesURL),
              let decoded = try? JSONDecoder().decode(VoiceRules.self, from: data) else {
            return VoiceRules()
        }
        return decoded
    }

    func writeRules(_ rules: VoiceRules) {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: rulesURL, options: .atomic)
    }

    func ruleMode(for source: String) -> String? {
        let key = sourceKey(source)
        return readRules().sources[key]
    }

    func setRuleMode(_ mode: String?, for source: String) {
        let key = sourceKey(source)
        guard !key.isEmpty else { return }
        var rules = readRules()
        if let mode, ["autoplay", "notify", "silent"].contains(mode) {
            rules.sources[key] = mode
        } else {
            rules.sources.removeValue(forKey: key)
        }
        writeRules(rules)
    }

    func sourceKey(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func readState() -> VoiceState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(VoiceState.self, from: data)
    }

    func storageSignature() -> String {
        let urls = [configURL, rulesURL, stateURL, queueURL, playbackURL, commandURL]
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

    func appendPlaybackEvent(_ event: PlaybackEvent) {
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(event),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        if FileManager.default.fileExists(atPath: playbackURL.path),
           let handle = try? FileHandle(forWritingTo: playbackURL) {
            handle.seekToEndOfFile()
            if let bytes = "\(line)\n".data(using: .utf8) {
                handle.write(bytes)
            }
            try? handle.close()
        } else {
            try? "\(line)\n".write(to: playbackURL, atomically: true, encoding: .utf8)
        }
    }

    func recentPlaybackEvents(limit: Int = 20) -> [PlaybackEvent] {
        guard let content = try? String(contentsOf: playbackURL, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n")
        let selected = limit > 0 ? Array(lines.suffix(limit)) : lines
        return selected.compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(PlaybackEvent.self, from: data)
        }.reversed()
    }

    func latestPlaybackEvent(for item: VoiceItem) -> PlaybackEvent? {
        guard let file = item.file else { return nil }
        return latestPlaybackEventsByFile()[file]
    }

    func latestPlaybackEventsByFile() -> [String: PlaybackEvent] {
        var events: [String: PlaybackEvent] = [:]
        for event in recentPlaybackEvents(limit: 0) {
            guard let file = event.file, events[file] == nil else { continue }
            events[file] = event
        }
        return events
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

final class EmptyStateView: NSView {
    init(symbolName: String, title: String, message: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 156))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = Theme.muted
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.alignment = .center

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 12.2, weight: .medium)
        messageLabel.textColor = Theme.muted
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: max(220, width - 72)).isActive = true

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BubbleRow: NSView {
    let item: VoiceItem

    init(item: VoiceItem, isPlaying: Bool, isExpanded: Bool, bubbleWidth: CGFloat, playbackSummary: String?, playsOnClick: Bool, target: AnyObject, action: Selector) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = rowBackground(isPlaying: isPlaying, isSelected: isExpanded).cgColor
        layer?.borderColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(isPlaying || isExpanded ? 0.76 : 0.34).cgColor
        layer?.borderWidth = 1

        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 11, left: 11, bottom: 11, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false

        let avatar = NSView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 13
        avatar.layer?.backgroundColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(0.16).cgColor
        avatar.layer?.borderColor = color(for: item.status, isPlaying: isPlaying).withAlphaComponent(0.62).cgColor
        avatar.layer?.borderWidth = 1
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 26),
            avatar.heightAnchor.constraint(equalToConstant: 26),
        ])

        let glyph = NSImageView(image: glyphImage(for: item, isPlaying: isPlaying))
        glyph.contentTintColor = color(for: item.status, isPlaying: isPlaying)
        glyph.imageScaling = .scaleProportionallyDown
        glyph.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 12),
            glyph.heightAnchor.constraint(equalToConstant: 12),
        ])

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(wrappingLabelWithString: titleText(for: item))
        title.font = .systemFont(ofSize: 13.2, weight: .semibold)
        title.textColor = Theme.text
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingTail

        let body = NSTextField(wrappingLabelWithString: bodyText(for: item))
        body.font = .systemFont(ofSize: 12.2, weight: .regular)
        body.textColor = Theme.text
        body.alphaValue = 0.88
        body.maximumNumberOfLines = 2
        body.lineBreakMode = .byTruncatingTail

        let footer = NSTextField(labelWithString: footerText(for: item, isPlaying: isPlaying, isExpanded: isExpanded, playbackSummary: playbackSummary, playsOnClick: playsOnClick))
        footer.font = .systemFont(ofSize: 10.8, weight: .medium)
        footer.textColor = isPlaying ? Theme.playing : Theme.muted
        footer.maximumNumberOfLines = 1
        footer.lineBreakMode = .byTruncatingTail

        let overlay = ReplayBubbleButton(title: "", target: target, action: action)
        overlay.isBordered = false
        overlay.filePath = item.file
        overlay.itemID = item.stableKey
        overlay.isEnabled = true
        overlay.toolTip = item.file == nil ? "Select message" : (isPlaying ? "Stop playback" : (playsOnClick ? "Replay message" : "Select message"))
        overlay.translatesAutoresizingMaskIntoConstraints = false

        addSubview(root)
        addSubview(overlay)
        root.addArrangedSubview(avatar)
        root.addArrangedSubview(content)
        content.addArrangedSubview(title)
        content.addArrangedSubview(body)
        content.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: bubbleWidth),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func titleText(for item: VoiceItem) -> String {
        item.displayTitle
    }

    private func bodyText(for item: VoiceItem) -> String {
        item.displayBodyText
    }

    private func glyphImage(for item: VoiceItem, isPlaying: Bool) -> NSImage {
        let name: String
        if isPlaying {
            name = "speaker.wave.2.fill"
        } else {
            switch item.status {
            case "queued", "generating": name = "clock.fill"
            case "failed": name = "exclamationmark.triangle.fill"
            default: name = item.file == nil ? "text.bubble.fill" : "play.fill"
            }
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    private func footerText(for item: VoiceItem, isPlaying: Bool, isExpanded: Bool, playbackSummary: String?, playsOnClick: Bool) -> String {
        if isPlaying { return "Playing now - click to stop" }
        let source = (item.source ?? "agent").trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = displayMode(item.mode)
        let priority = (item.priority ?? "normal").lowercased() == "normal" ? nil : item.priority?.uppercased()
        let status = playbackSummary ?? statusText(for: item)
        let replayAction = playsOnClick ? "click to replay" : "click to select"
        let action = item.file == nil ? (isExpanded ? "selected" : "click to select") : (isExpanded ? "selected" : replayAction)
        return [priority, source.isEmpty ? "agent" : source, mode, status, action]
            .compactMap { $0 }
            .joined(separator: "  •  ")
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

    private func rowBackground(isPlaying: Bool, isSelected: Bool) -> NSColor {
        if isPlaying {
            return NSColor(red: 0.075, green: 0.105, blue: 0.125, alpha: 1)
        }
        if isSelected {
            return NSColor(red: 0.074, green: 0.092, blue: 0.104, alpha: 1)
        }
        return NSColor(red: 0.062, green: 0.076, blue: 0.088, alpha: 1)
    }

    private func displayMode(_ mode: String?) -> String {
        switch mode {
        case "autoplay": return "Speak"
        case "notify": return "Notify"
        case "silent": return "DND"
        default: return "Message"
        }
    }

    private func statusText(for item: VoiceItem) -> String {
        switch item.status {
        case "ready": return item.file == nil ? "Saved" : "Ready"
        case "queued": return "Queued"
        case "generating": return "Rendering"
        case "failed": return "Failed"
        default: return item.status?.capitalized ?? "Saved"
        }
    }
}

final class DashboardViewController: NSViewController, NSTextFieldDelegate, NSSearchFieldDelegate {
    let store: VoiceStore
    var onReplayFile: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onSkip: (() -> Void)?
    var onArchiveItem: ((String?) -> Void)?
    var onClearInbox: (() -> Void)?

    private var playingFile: String?
    private var selectedItemKey: String?
    private let listScrollView = NSScrollView()
    private let listDocument = InboxDocumentView()
    private let searchField = NSSearchField()
    private let sourcePopup = NSPopUpButton()
    private let sourceRuleControl = NSSegmentedControl(labels: ["Follow", "Speak", "Notify", "DND"], trackingMode: .selectOne, target: nil, action: nil)
    private let resultCountLabel = NSTextField(labelWithString: "0 messages")
    private let playbackStatusLabel = NSTextField(labelWithString: "Playback idle")
    private let detailTitle = NSTextField(labelWithString: "Select a message")
    private let detailMeta = NSTextField(labelWithString: "Agent inbox")
    private let detailPlayback = NSTextField(labelWithString: "Playback details appear here.")
    private let detailText = NSTextView()
    private let replayButton = NSButton(title: "Replay", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip", target: nil, action: nil)
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
        let subtitle = NSTextField(labelWithString: "Inbox for agent updates and local readouts")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = Theme.muted
        playbackStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        playbackStatusLabel.textColor = Theme.muted
        titleStack.addArrangedSubview(title)
        titleStack.addArrangedSubview(subtitle)
        titleStack.addArrangedSubview(playbackStatusLabel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for button in [replayButton, skipButton, stopButton, archiveButton, clearButton, refreshButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        replayButton.target = self
        replayButton.action = #selector(replayTapped)
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
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
        for button in [skipButton, stopButton] {
            header.addArrangedSubview(button)
        }
        root.addArrangedSubview(header)

        let filterRow = NSStackView()
        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.spacing = 10
        searchField.placeholderString = "Search messages"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        sourcePopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let ruleLabel = NSTextField(labelWithString: "Rule")
        ruleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        ruleLabel.textColor = Theme.muted
        sourceRuleControl.controlSize = .small
        sourceRuleControl.target = self
        sourceRuleControl.action = #selector(sourceRuleChanged)
        sourceRuleControl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        resultCountLabel.font = .systemFont(ofSize: 12, weight: .medium)
        resultCountLabel.textColor = Theme.muted
        let filterSpacer = NSView()
        filterSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterRow.addArrangedSubview(searchField)
        filterRow.addArrangedSubview(sourcePopup)
        filterRow.addArrangedSubview(ruleLabel)
        filterRow.addArrangedSubview(sourceRuleControl)
        filterRow.addArrangedSubview(filterSpacer)
        filterRow.addArrangedSubview(resultCountLabel)
        filterRow.addArrangedSubview(refreshButton)
        filterRow.addArrangedSubview(clearButton)
        root.addArrangedSubview(panel(filterRow))

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
        listPanel.widthAnchor.constraint(equalToConstant: 460).isActive = true
        body.addArrangedSubview(listPanel)

        let detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.spacing = 10
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        detailTitle.textColor = Theme.text
        detailTitle.maximumNumberOfLines = 2
        detailMeta.font = .systemFont(ofSize: 11.5, weight: .medium)
        detailMeta.textColor = Theme.muted
        detailPlayback.font = .systemFont(ofSize: 11.5, weight: .medium)
        detailPlayback.textColor = Theme.muted
        detailPlayback.maximumNumberOfLines = 2
        detailPlayback.lineBreakMode = .byTruncatingTail
        detailText.isEditable = false
        detailText.drawsBackground = false
        detailText.textColor = Theme.text
        detailText.font = .systemFont(ofSize: 14, weight: .regular)
        detailText.textContainerInset = NSSize(width: 0, height: 6)
        detailText.textContainer?.lineFragmentPadding = 0
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailText
        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detailScroll.borderType = .noBorder
        let detailHeader = NSStackView()
        detailHeader.orientation = .horizontal
        detailHeader.alignment = .centerY
        detailHeader.spacing = 10
        let detailTitleStack = NSStackView()
        detailTitleStack.orientation = .vertical
        detailTitleStack.spacing = 2
        detailTitleStack.addArrangedSubview(detailTitle)
        detailTitleStack.addArrangedSubview(detailMeta)
        let detailSpacer = NSView()
        detailSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailHeader.addArrangedSubview(detailTitleStack)
        detailHeader.addArrangedSubview(detailSpacer)
        detailHeader.addArrangedSubview(replayButton)
        detailHeader.addArrangedSubview(archiveButton)
        detailStack.addArrangedSubview(detailHeader)
        detailStack.addArrangedSubview(detailPlayback)
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

    func setPlaybackSummary(_ text: String, color: NSColor, isPlaying: Bool, hasQueue: Bool) {
        playbackStatusLabel.stringValue = text
        playbackStatusLabel.textColor = color
        skipButton.isEnabled = isPlaying
        stopButton.isEnabled = isPlaying || hasQueue
    }

    func reload() {
        updateSourcePopup()
        let items = filteredItems(store.recentItems(limit: 0))
        if selectedItemKey == nil {
            selectedItemKey = items.first?.stableKey
        }
        if let selectedItemKey, !items.contains(where: { $0.stableKey == selectedItemKey }) {
            self.selectedItemKey = items.first?.stableKey
        }
        rebuildList()
        updateDetail()
    }

    private func rebuildList() {
        for subview in listDocument.subviews {
            subview.removeFromSuperview()
        }
        let allItems = store.recentItems(limit: 0)
        let items = filteredItems(allItems)
        let playbackByFile = store.latestPlaybackEventsByFile()
        resultCountLabel.stringValue = countText(shown: items.count, total: allItems.count)
        let width: CGFloat = max(480, listScrollView.contentSize.width)
        if items.isEmpty {
            let empty = EmptyStateView(
                symbolName: emptyDashboardSymbol(),
                title: emptyDashboardTitle(),
                message: emptyDashboardText(),
                width: width
            )
            empty.frame = NSRect(x: 0, y: max(24, (listScrollView.contentSize.height - 156) / 2), width: width, height: 156)
            listDocument.addSubview(empty)
            listDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(560, listScrollView.contentSize.height))
            return
        }
        var y: CGFloat = 0
        for item in items {
            let isExpanded = item.stableKey == selectedItemKey
            let bubbleWidth = min(420, max(300, width - 74))
            let rowHeight = height(for: item, width: width, isExpanded: isExpanded)
            let row = BubbleRow(
                item: item,
                isPlaying: isPlaying(item),
                isExpanded: isExpanded,
                bubbleWidth: bubbleWidth,
                playbackSummary: playbackFooterText(item.file.flatMap { playbackByFile[$0] }, isPlaying: isPlaying(item)),
                playsOnClick: false,
                target: self,
                action: #selector(messageTapped(_:))
            )
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
            listDocument.addSubview(row)
            y += rowHeight + 8
        }
        listDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(560, y))
    }

    private func height(for item: VoiceItem, width: CGFloat, isExpanded: Bool) -> CGFloat {
        isExpanded ? 96 : 86
    }

    private func isPlaying(_ item: VoiceItem) -> Bool {
        guard let file = item.file, !file.isEmpty else { return false }
        return file == playingFile
    }

    private func updateDetail() {
        let item = filteredItems(store.recentItems(limit: 0)).first { $0.stableKey == selectedItemKey }
        guard let item else {
            detailTitle.stringValue = "Select a message"
            detailMeta.stringValue = "Message detail"
            detailPlayback.stringValue = "Playback: no message selected"
            detailPlayback.toolTip = nil
            detailText.string = "Choose a message from the inbox to read the full text, inspect playback history, or replay the local audio."
            replayButton.isEnabled = false
            archiveButton.isEnabled = false
            return
        }
        detailTitle.stringValue = item.displayTitle
        let source = sourceName(item)
        let status = (item.status ?? "queued").capitalized
        let mode = displayModeName(item.mode ?? "message")
        let created = item.created_at ?? "unknown time"
        detailMeta.stringValue = "\(source)  •  \(mode)  •  \(status)  •  \(created)"
        if let event = store.latestPlaybackEvent(for: item) {
            detailPlayback.stringValue = "Playback: \(playbackFooterText(event) ?? displayPlaybackEvent(event.event))"
            detailPlayback.toolTip = playbackDetailText(event)
        } else {
            detailPlayback.stringValue = item.file == nil ? "Playback: notification-only message" : "Playback: no local playback recorded"
            detailPlayback.toolTip = nil
        }
        detailText.string = item.displayBodyText
        replayButton.isEnabled = item.file != nil
        archiveButton.isEnabled = true
    }

    @objc private func messageTapped(_ sender: ReplayBubbleButton) {
        selectedItemKey = sender.itemID ?? sender.filePath
        rebuildList()
        updateDetail()
    }

    @objc private func replayTapped() {
        guard let item = filteredItems(store.recentItems(limit: 0)).first(where: { $0.stableKey == selectedItemKey }),
              let file = item.file else { return }
        onReplayFile?(file)
    }

    private func updateSourcePopup() {
        let selected = sourcePopup.selectedItem?.title ?? "All Sources"
        let sources = Array(Set(store.recentItems(limit: 0).map { sourceName($0) })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        sourcePopup.removeAllItems()
        sourcePopup.addItem(withTitle: "All Sources")
        for source in sources {
            sourcePopup.addItem(withTitle: source)
        }
        if sources.contains(selected) {
            sourcePopup.selectItem(withTitle: selected)
        } else {
            sourcePopup.selectItem(withTitle: "All Sources")
        }
        updateSourceRuleControl()
    }

    private func filteredItems(_ items: [VoiceItem]) -> [VoiceItem] {
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if source != "All Sources" && sourceName(item) != source {
                return false
            }
            if query.isEmpty { return true }
            let haystack = [
                item.title,
                item.source,
                item.priority,
                item.mode,
                item.status,
                item.text,
                item.speech_text,
                item.error,
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private func sourceName(_ item: VoiceItem) -> String {
        let value = (item.source ?? "agent").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "agent" : value
    }

    private func displayModeName(_ mode: String) -> String {
        switch mode {
        case "autoplay": return "Speak"
        case "notify": return "Notify"
        case "silent": return "DND"
        default: return "Message"
        }
    }

    private func countText(shown: Int, total: Int) -> String {
        let word = total == 1 ? "message" : "messages"
        return shown == total ? "\(total) \(word)" : "\(shown) shown / \(total) \(word)"
    }

    private func emptyDashboardSymbol() -> String {
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }
        if (sourcePopup.selectedItem?.title ?? "All Sources") != "All Sources" {
            return "tray"
        }
        return "waveform.and.bubble.left"
    }

    private func emptyDashboardTitle() -> String {
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matching Messages"
        }
        if (sourcePopup.selectedItem?.title ?? "All Sources") != "All Sources" {
            return "No Messages From This Source"
        }
        return "Inbox Is Ready"
    }

    private func emptyDashboardText() -> String {
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search or clear the field to return to the full inbox."
        }
        if (sourcePopup.selectedItem?.title ?? "All Sources") != "All Sources" {
            return "When this source sends an agent update, it will appear here."
        }
        return "Incoming MCP speech requests will appear here with replay, archive, and local readout history."
    }

    private func updateSourceRuleControl() {
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        sourceRuleControl.isEnabled = source != "All Sources"
        guard source != "All Sources" else {
            sourceRuleControl.selectedSegment = 0
            return
        }
        switch store.ruleMode(for: source) {
        case "autoplay": sourceRuleControl.selectedSegment = 1
        case "notify": sourceRuleControl.selectedSegment = 2
        case "silent": sourceRuleControl.selectedSegment = 3
        default: sourceRuleControl.selectedSegment = 0
        }
    }

    private func modeForRuleSegment() -> String? {
        switch sourceRuleControl.selectedSegment {
        case 1: return "autoplay"
        case 2: return "notify"
        case 3: return "silent"
        default: return nil
        }
    }

    @objc private func searchChanged() { reload() }
    @objc private func sourceChanged() {
        updateSourceRuleControl()
        reload()
    }
    @objc private func sourceRuleChanged() {
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        guard source != "All Sources" else { return }
        store.setRuleMode(modeForRuleSegment(), for: source)
        reload()
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            reload()
        }
    }
    @objc private func skipTapped() { onSkip?() }
    @objc private func stopTapped() { onStop?() }
    @objc private func archiveTapped() { onArchiveItem?(selectedItemKey) }
    @objc private func clearTapped() { onClearInbox?() }
    @objc private func refreshTapped() { reload() }
}

final class VoicePopoverController: NSViewController, NSTextFieldDelegate, NSSearchFieldDelegate {
    let store: VoiceStore
    var onReplayLast: (() -> Void)?
    var onReplayFile: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onSkip: (() -> Void)?
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
    private var messageDetailPanel: NSView?

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
    private let playbackStatusLabel = NSTextField(labelWithString: "Playback idle")
    private let notificationTitleLabel = NSTextField(labelWithString: "System")
    private let selectedTitleLabel = NSTextField(labelWithString: "Select a message")
    private let selectedMetaLabel = NSTextField(labelWithString: "Click a row to inspect or replay it.")
    private let selectedTextView = NSTextView()
    private let searchField = NSSearchField()
    private let sourcePopup = NSPopUpButton()
    private let sourceRuleControl = NSSegmentedControl(labels: ["Follow", "Speak", "Notify", "DND"], trackingMode: .selectOne, target: nil, action: nil)
    private let inboxScrollView = NSScrollView()
    private let inboxDocument = InboxDocumentView()
    private let replayButton = NSButton(title: "Replay Last", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip", target: nil, action: nil)
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
        view.layer?.cornerRadius = 14
        view.layer?.borderColor = Theme.border.cgColor
        view.layer?.borderWidth = 1
        view.layer?.masksToBounds = true
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

        let deliveryLabel = NSTextField(labelWithString: "Mode")
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
        playbackStatusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        playbackStatusLabel.textColor = Theme.muted
        inboxTitleStack.addArrangedSubview(inboxTitle)
        inboxTitleStack.addArrangedSubview(inboxCountLabel)
        inboxTitleStack.addArrangedSubview(playbackStatusLabel)
        let inboxSpacer = NSView()
        inboxSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dashboardButton.bezelStyle = .rounded
        dashboardButton.target = self
        dashboardButton.action = #selector(openDashboardTapped)
        inboxHeader.addArrangedSubview(inboxTitleStack)
        inboxHeader.addArrangedSubview(inboxSpacer)
        inboxHeader.addArrangedSubview(dashboardButton)
        inboxSectionHeader.addArrangedSubview(inboxHeader)

        let searchRow = NSStackView()
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 8
        searchField.placeholderString = "Search inbox"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        sourcePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        searchRow.addArrangedSubview(searchField)
        searchRow.addArrangedSubview(sourcePopup)
        inboxSectionHeader.addArrangedSubview(searchRow)

        sourceRuleControl.controlSize = .small
        sourceRuleControl.target = self
        sourceRuleControl.action = #selector(sourceRuleChanged)

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
        skipButton.bezelStyle = .rounded
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
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
        inboxActions.addArrangedSubview(skipButton)
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
            inboxPanel.heightAnchor.constraint(equalToConstant: 300),
            inboxScrollView.leadingAnchor.constraint(equalTo: inboxPanel.leadingAnchor, constant: 10),
            inboxScrollView.trailingAnchor.constraint(equalTo: inboxPanel.trailingAnchor, constant: -10),
            inboxScrollView.topAnchor.constraint(equalTo: inboxPanel.topAnchor, constant: 10),
            inboxScrollView.bottomAnchor.constraint(equalTo: inboxPanel.bottomAnchor, constant: -10),
        ])
        root.addArrangedSubview(inboxPanel)

        let selectedPanel = buildSelectedMessagePanel()
        messageDetailPanel = selectedPanel
        root.addArrangedSubview(selectedPanel)
        root.addArrangedSubview(panel(voiceSummary, fill: false, padding: 8))

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
        notifyRow.addArrangedSubview(notificationLabel)
        notifyRow.addArrangedSubview(notifySpacer)
        for button in [doctorButton, requestNotificationsButton] {
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
            ("Settings", #selector(openNotificationSettingsTapped)),
            ("Pronunciations", #selector(openPronunciationsTapped)),
            ("Folder", #selector(openFolderTapped)),
            ("Quit", #selector(quitTapped)),
        ] {
            let button = NSButton(title: label, target: self, action: action)
            button.bezelStyle = .rounded
            bottom.addArrangedSubview(button)
        }
        root.addArrangedSubview(bottom)
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

    private func buildSelectedMessagePanel() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6

        selectedTitleLabel.font = .systemFont(ofSize: 13.2, weight: .semibold)
        selectedTitleLabel.textColor = Theme.text
        selectedTitleLabel.maximumNumberOfLines = 1
        selectedTitleLabel.lineBreakMode = .byTruncatingTail

        selectedMetaLabel.font = .systemFont(ofSize: 10.8, weight: .medium)
        selectedMetaLabel.textColor = Theme.muted
        selectedMetaLabel.maximumNumberOfLines = 1
        selectedMetaLabel.lineBreakMode = .byTruncatingTail

        selectedTextView.isEditable = false
        selectedTextView.isSelectable = true
        selectedTextView.drawsBackground = false
        selectedTextView.textColor = Theme.text
        selectedTextView.font = .systemFont(ofSize: 12.2, weight: .regular)
        selectedTextView.textContainerInset = NSSize(width: 0, height: 4)
        selectedTextView.textContainer?.lineFragmentPadding = 0

        let scroll = NSScrollView()
        scroll.documentView = selectedTextView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.heightAnchor.constraint(equalToConstant: 52).isActive = true

        stack.addArrangedSubview(selectedTitleLabel)
        stack.addArrangedSubview(selectedMetaLabel)
        stack.addArrangedSubview(scroll)

        let box = panel(stack, fill: false, padding: 10)
        box.heightAnchor.constraint(equalToConstant: 104).isActive = true
        return box
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
        updateSelectedDetail()
    }

    func setPlaybackSummary(_ text: String, color: NSColor, isPlaying: Bool, hasQueue: Bool) {
        playbackStatusLabel.stringValue = text
        playbackStatusLabel.textColor = color
        skipButton.isEnabled = isPlaying
        stopButton.isEnabled = isPlaying || hasQueue
    }

    func reload() {
        let config = store.readConfig()
        let state = store.readState()

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
        updateSourcePopup(with: items)
        updateSourceRuleControl()
        let visibleItems = filtered(items)
        ensureSelectedItem(in: visibleItems)
        let filteredCount = visibleItems.count
        let messageWord = items.count == 1 ? "message" : "messages"
        if filteredCount != items.count {
            inboxCountLabel.stringValue = "\(filteredCount) shown / \(items.count) \(messageWord)"
        } else {
            inboxCountLabel.stringValue = "\(items.count) \(messageWord)"
        }

        let modeText = displayModeName(config.mode)
        let updated = state?.updated_at ?? "never"
        statusLabel.stringValue = "\(modeText) / updated \(shortTimestamp(updated))"
        tuneButton.title = tuningVisible ? "Hide" : "Tune"
        controlsPanel?.isHidden = !tuningVisible

        rebuildInbox()
        updateSelectedDetail()
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

    private func ensureSelectedItem(in items: [VoiceItem]) {
        if let expandedItemID, items.contains(where: { $0.stableKey == expandedItemID }) {
            return
        }
        expandedItemID = items.first?.stableKey
    }

    private func currentSelectedItem() -> VoiceItem? {
        let items = filtered(store.recentItems(limit: 80))
        ensureSelectedItem(in: items)
        guard let expandedItemID else { return nil }
        return items.first { $0.stableKey == expandedItemID }
    }

    private func updateSelectedDetail() {
        guard let item = currentSelectedItem() else {
            selectedTitleLabel.stringValue = "No message selected"
            selectedMetaLabel.stringValue = "Incoming agent messages will appear above."
            selectedTextView.string = ""
            messageDetailPanel?.isHidden = false
            replayButton.isEnabled = false
            archiveButton.isEnabled = false
            return
        }

        selectedTitleLabel.stringValue = item.displayTitle
        let playback = playbackFooterText(store.latestPlaybackEvent(for: item), isPlaying: isPlaying(item))
        selectedMetaLabel.stringValue = [
            sourceName(item),
            displayModeName(item.mode ?? "message"),
            item.status?.capitalized,
            playback,
        ].compactMap { $0 }.joined(separator: "  •  ")
        selectedTextView.string = item.displayBodyText
        replayButton.isEnabled = item.file != nil
        archiveButton.isEnabled = true
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
        let playbackByFile = store.latestPlaybackEventsByFile()
        for item in items {
            let itemKey = item.stableKey
            let isExpanded = itemKey == expandedItemID
            let bubbleWidth = max(300, width - 74)
            let rowHeight = height(for: item, width: width, isExpanded: isExpanded)
            let row = BubbleRow(
                item: item,
                isPlaying: isPlaying(item),
                isExpanded: isExpanded,
                bubbleWidth: bubbleWidth,
                playbackSummary: playbackFooterText(item.file.flatMap { playbackByFile[$0] }, isPlaying: isPlaying(item)),
                playsOnClick: true,
                target: self,
                action: #selector(replayBubble(_:))
            )
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
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            switch filterControl.selectedSegment {
            case 1:
                if item.status != "ready" { return false }
            case 2:
                guard let status = item.status, status != "ready" else { return false }
            default:
                break
            }
            if source != "All Sources" && sourceName(item) != source {
                return false
            }
            if query.isEmpty { return true }
            let haystack = [
                item.title,
                item.source,
                item.priority,
                item.mode,
                item.status,
                item.text,
                item.speech_text,
                item.error,
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private func emptyInboxText() -> String {
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No messages match this search."
        }
        if (sourcePopup.selectedItem?.title ?? "All Sources") != "All Sources" {
            return "No messages from this source in this filter."
        }
        switch filterControl.selectedSegment {
        case 1:
            return "No ready messages in this filter yet."
        case 2:
            return "No active renders or failures right now."
        default:
            return "No messages yet. Notify and DND modes still save incoming agent speech here."
        }
    }

    private func updateSourcePopup(with items: [VoiceItem]) {
        let selected = sourcePopup.selectedItem?.title ?? "All Sources"
        let sources = Array(Set(items.map { sourceName($0) })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        sourcePopup.removeAllItems()
        sourcePopup.addItem(withTitle: "All Sources")
        for source in sources {
            sourcePopup.addItem(withTitle: source)
        }
        if sources.contains(selected) {
            sourcePopup.selectItem(withTitle: selected)
        } else {
            sourcePopup.selectItem(withTitle: "All Sources")
        }
    }

    private func updateSourceRuleControl() {
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        sourceRuleControl.isEnabled = source != "All Sources"
        guard source != "All Sources" else {
            sourceRuleControl.selectedSegment = 0
            return
        }
        switch store.ruleMode(for: source) {
        case "autoplay": sourceRuleControl.selectedSegment = 1
        case "notify": sourceRuleControl.selectedSegment = 2
        case "silent": sourceRuleControl.selectedSegment = 3
        default: sourceRuleControl.selectedSegment = 0
        }
    }

    private func modeForRuleSegment() -> String? {
        switch sourceRuleControl.selectedSegment {
        case 1: return "autoplay"
        case 2: return "notify"
        case 3: return "silent"
        default: return nil
        }
    }

    private func sourceName(_ item: VoiceItem) -> String {
        let value = (item.source ?? "agent").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "agent" : value
    }

    private func isPlaying(_ item: VoiceItem) -> Bool {
        guard let file = item.file, !file.isEmpty else { return false }
        return file == playingFile
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
        isExpanded ? 96 : 86
    }

    @objc private func replayBubble(_ sender: ReplayBubbleButton) {
        expandedItemID = sender.itemID ?? sender.filePath
        rebuildInbox()
        updateSelectedDetail()
        if let file = sender.filePath {
            onReplayFile?(file)
        }
    }

    @objc private func filterChanged() {
        reload()
    }

    @objc private func searchChanged() {
        reload()
    }

    @objc private func sourceChanged() {
        updateSourceRuleControl()
        reload()
    }

    @objc private func sourceRuleChanged() {
        let source = sourcePopup.selectedItem?.title ?? "All Sources"
        guard source != "All Sources" else { return }
        store.setRuleMode(modeForRuleSegment(), for: source)
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
        if obj.object as? NSTextField === voiceField {
            voiceChanged()
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            reload()
        }
    }

    @objc private func replayTapped() {
        if let item = currentSelectedItem(), let file = item.file {
            expandedItemID = item.stableKey
            rebuildInbox()
            updateSelectedDetail()
            onReplayFile?(file)
            return
        }
        if let item = store.readState()?.last {
            expandedItemID = item.stableKey
            rebuildInbox()
            updateSelectedDetail()
        }
        onReplayLast?()
    }
    @objc private func skipTapped() { onSkip?() }
    @objc private func stopTapped() { onStop?() }
    @objc private func speakTestTapped() { onSpeakTest?() }
    @objc private func requestNotificationsTapped() { onRequestNotifications?() }
    @objc private func testNotificationTapped() { onTestNotification?() }
    @objc private func doctorTapped() { onRunDoctor?() }
    @objc private func openNotificationSettingsTapped() { onOpenNotificationSettings?() }
    @objc private func openPronunciationsTapped() { onOpenPronunciations?() }
    @objc private func openFolderTapped() { onOpenFolder?() }
    @objc private func openDashboardTapped() { onOpenDashboard?() }
    @objc private func archiveTapped() { onArchiveItem?(currentSelectedItem()?.stableKey ?? store.readState()?.last?.id) }
    @objc private func clearInboxTapped() { onClearInbox?() }
    @objc private func quitTapped() { onQuit?() }
}

final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
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
    private var autoplayQueue: [String] = []
    private var queuedAutoplayFiles = Set<String>()
    private var unreadCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerBundleWithLaunchServices()
        configureNotifications(requestPermission: true)
        configurePopover()
        configureStatusItem()
        updatePlaybackSummary()
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh(initial: false)
            self?.updatePlaybackSummary()
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
        popoverController.onSkip = { [weak self] in self?.skipPlayback() }
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
        panel = PopoverPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Agent Voice Bar"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.delegate = self
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
                        enqueueAutoplay(file: file)
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
        case "skip":
            skipPlayback()
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
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            popoverController.reload()
            showPanel()
        }
    }

    private func showPanel() {
        NSApp.setActivationPolicy(.accessory)
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

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        panel.orderOut(nil)
        if dashboardWindow?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showDashboard() {
        panel.orderOut(nil)
        if dashboardWindow == nil {
            let controller = DashboardViewController(store: store)
            controller.onReplayFile = { [weak self] file in self?.replay(file: file) }
            controller.onStop = { [weak self] in self?.stopPlayback() }
            controller.onSkip = { [weak self] in self?.skipPlayback() }
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
        guard let dashboardWindow else { return }
        if !dashboardWindow.isVisible {
            dashboardWindow.center()
        }
        dashboardWindow.level = .floating
        dashboardWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dashboardWindow.level = .normal
        }
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
                    let ruleCount = self.store.readRules().sources.count
                    let playbackLine = self.latestPlaybackLine()
                    let audioLine = self.systemAudioLine()
                    let queueLine = "Autoplay queue: \(self.autoplayQueue.count)"
                    let mode = self.displayModeName(config.mode)
                    let text = [
                        "Delivery: \(mode)",
                        "Voice: \(config.voice)",
                        "Render speed: \(config.speed)x",
                        "Talk speed: \(config.replay_speed)x",
                        "Source rules: \(ruleCount)",
                        queueLine,
                        playbackLine,
                        audioLine,
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

    private func systemAudioLine() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "set s to get volume settings\nreturn (output volume of s as text) & \",\" & (output muted of s as text)"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "System audio: unavailable"
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = raw.split(separator: ",", maxSplits: 1).map(String.init)
            let volume = parts.first?.isEmpty == false ? parts[0] : "unknown"
            let muted = parts.count > 1 ? parts[1] : "unknown"
            if muted == "true" {
                return "System audio: muted, volume \(volume)%"
            }
            if volume == "0" {
                return "System audio: volume 0%"
            }
            return "System audio: volume \(volume)%, muted \(muted)"
        } catch {
            return "System audio: unavailable - \(error.localizedDescription)"
        }
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

    private func latestPlaybackLine() -> String {
        guard let event = store.recentPlaybackEvents(limit: 1).first else {
            return "Last playback: none recorded"
        }
        let title = event.title?.isEmpty == false ? event.title! : URL(fileURLWithPath: event.file ?? "").lastPathComponent
        let detail = event.detail?.isEmpty == false ? " - \(event.detail!)" : ""
        return "Last playback: \(event.event) / \(title) / \(event.at)\(detail)"
    }

    private func playbackSummaryText() -> (String, NSColor, Bool, Bool) {
        let isPlaying = playingFile != nil
        let hasQueue = !autoplayQueue.isEmpty
        if let playingFile {
            let suffix = hasQueue ? " / Up next: \(autoplayQueue.count)" : ""
            return ("Now: \(titleForFile(playingFile))\(suffix)", Theme.playing, isPlaying, hasQueue)
        }
        if hasQueue {
            return ("Queued: \(autoplayQueue.count)", Theme.amber, isPlaying, hasQueue)
        }
        return ("Playback idle", Theme.muted, isPlaying, hasQueue)
    }

    private func updatePlaybackSummary() {
        let summary = playbackSummaryText()
        popoverController?.setPlaybackSummary(summary.0, color: summary.1, isPlaying: summary.2, hasQueue: summary.3)
        dashboardController?.setPlaybackSummary(summary.0, color: summary.1, isPlaying: summary.2, hasQueue: summary.3)
    }

    private func titleForFile(_ file: String) -> String {
        if let item = store.recentItems(limit: 0).first(where: { $0.file == file }) {
            return item.displayTitle
        }
        return URL(fileURLWithPath: file).lastPathComponent
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
        play(file: file, source: "manual")
    }

    private func enqueueAutoplay(file: String) {
        guard file != playingFile, !queuedAutoplayFiles.contains(file) else { return }
        autoplayQueue.append(file)
        queuedAutoplayFiles.insert(file)
        recordPlaybackEvent("queued_autoplay", file: file, detail: "Waiting for prior readouts to finish")
        popoverController.setNotificationStatus("Playback: queued \(autoplayQueue.count)", color: Theme.amber)
        updatePlaybackSummary()
        playNextAutoplayIfIdle()
    }

    private func playNextAutoplayIfIdle() {
        guard audioPlayer == nil, !autoplayQueue.isEmpty else { return }
        let next = autoplayQueue.removeFirst()
        queuedAutoplayFiles.remove(next)
        updatePlaybackSummary()
        play(file: next, source: "autoplay")
    }

    private func clearAutoplayQueue(reason: String) {
        let queued = autoplayQueue
        autoplayQueue.removeAll()
        queuedAutoplayFiles.removeAll()
        for file in queued {
            recordPlaybackEvent("skipped", file: file, detail: reason)
        }
        updatePlaybackSummary()
    }

    private func play(file: String, source: String) {
        if playingFile == file {
            stopPlayback()
            return
        }
        if source == "manual" {
            clearAutoplayQueue(reason: "Manual replay interrupted queued autoplay")
            stopPlayback()
        } else if audioPlayer != nil {
            enqueueAutoplay(file: file)
            return
        }

        guard FileManager.default.fileExists(atPath: file) else {
            clearPlaybackState()
            popoverController.setNotificationStatus("Playback: missing file", color: .systemRed)
            recordPlaybackEvent("missing_file", file: file, detail: "Audio file was missing")
            appendAppMessage(title: "Playback failed", text: "Audio file was missing:\n\(file)", priority: "high")
            if source == "autoplay" {
                playNextAutoplayIfIdle()
            }
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
                recordPlaybackEvent("failed_start", file: file, detail: "AVAudioPlayer.play() returned false", duration: player.duration, rate: player.rate)
                clearPlaybackState()
                popoverController.setNotificationStatus("Playback: could not start", color: .systemRed)
                if source == "autoplay" {
                    playNextAutoplayIfIdle()
                }
                return
            }
            playingFile = file
            popoverController.setPlayingFile(file)
            dashboardController?.setPlayingFile(file)
            popoverController.setNotificationStatus("Playback: playing", color: Theme.playing)
            recordPlaybackEvent("started", file: file, detail: nil, duration: player.duration, rate: player.rate)
            updatePlaybackSummary()
            schedulePlaybackWatchdog(for: file, player: player)
        } catch {
            recordPlaybackEvent("failed_load", file: file, detail: error.localizedDescription)
            clearPlaybackState()
            popoverController.setNotificationStatus("Playback: \(error.localizedDescription)", color: .systemRed)
            if source == "autoplay" {
                playNextAutoplayIfIdle()
            }
        }
    }

    private func stopPlayback(clearQueue: Bool = true) {
        if clearQueue {
            clearAutoplayQueue(reason: "Playback stopped")
        }
        let file = playingFile
        audioPlayer?.stop()
        clearPlaybackState()
        if let file {
            recordPlaybackEvent("stopped", file: file, detail: "Stopped by user")
        }
        popoverController.setNotificationStatus("Playback: stopped", color: Theme.muted)
        updatePlaybackSummary()
    }

    private func skipPlayback() {
        guard let file = playingFile else {
            playNextAutoplayIfIdle()
            popoverController.setNotificationStatus("Playback: nothing to skip", color: Theme.muted)
            return
        }
        audioPlayer?.stop()
        recordPlaybackEvent("skipped", file: file, detail: "Skipped to next queued readout", duration: audioPlayer?.duration, rate: audioPlayer?.rate)
        clearPlaybackState()
        popoverController.setNotificationStatus("Playback: skipped", color: Theme.amber)
        updatePlaybackSummary()
        playNextAutoplayIfIdle()
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
                self.recordPlaybackEvent("watchdog_finished", file: file, detail: "Playback watchdog cleared stale state", duration: player.duration, rate: player.rate)
                self.clearPlaybackState()
                self.popoverController.setNotificationStatus("Playback: finished", color: Theme.green)
                self.updatePlaybackSummary()
                self.playNextAutoplayIfIdle()
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
        updatePlaybackSummary()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard audioPlayer === player else { return }
        let file = playingFile
        if let file {
            recordPlaybackEvent(flag ? "finished" : "stopped", file: file, detail: flag ? nil : "Playback ended unsuccessfully", duration: player.duration, rate: player.rate)
        }
        clearPlaybackState()
        popoverController.setNotificationStatus(flag ? "Playback: finished" : "Playback: stopped", color: flag ? Theme.green : Theme.muted)
        updatePlaybackSummary()
        playNextAutoplayIfIdle()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard audioPlayer === player else { return }
        let file = playingFile
        if let file {
            recordPlaybackEvent("decode_failed", file: file, detail: error?.localizedDescription, duration: player.duration, rate: player.rate)
        }
        clearPlaybackState()
        popoverController.setNotificationStatus("Playback: decode failed", color: .systemRed)
        updatePlaybackSummary()
        playNextAutoplayIfIdle()
    }

    private func recordPlaybackEvent(_ name: String, file: String?, detail: String?, duration: Double? = nil, rate: Float? = nil) {
        let item = file.flatMap { path in
            store.recentItems(limit: 0).first { $0.file == path }
        }
        let event = PlaybackEvent(
            at: ISO8601DateFormatter().string(from: Date()),
            event: name,
            file: file,
            source: item?.source,
            title: item?.displayTitle,
            detail: detail,
            duration: duration,
            rate: rate
        )
        store.appendPlaybackEvent(event)
        lastStorageSignature = nil
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
