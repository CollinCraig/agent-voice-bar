import AppKit
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
    var temperature: String = "0.45"
    var top_p: String = "0.85"
    var voice: String = "Chelsie"
    var max_chars: Int = 1200
}

struct VoiceItem: Codable {
    var id: String?
    var created_at: String?
    var ready_at: String?
    var source: String?
    var mode: String?
    var status: String?
    var voice: String?
    var speed: String?
    var temperature: String?
    var top_p: String?
    var text: String?
    var speech_text: String?
    var file: String?
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

    func recentItems(limit: Int = 24) -> [VoiceItem] {
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
        return order.suffix(limit).compactMap { byID[$0] }.reversed()
    }

    func clearInbox() {
        try? "".write(to: queueURL, atomically: true, encoding: .utf8)
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

    init(item: VoiceItem, isPlaying: Bool, target: AnyObject, action: Selector) {
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

        let body = NSTextField(wrappingLabelWithString: item.text ?? "(empty)")
        body.font = .systemFont(ofSize: 12.8, weight: .regular)
        body.textColor = Theme.text
        body.maximumNumberOfLines = 2
        body.lineBreakMode = .byTruncatingTail

        let footer = NSTextField(labelWithString: footerText(for: item, isPlaying: isPlaying))
        footer.font = .systemFont(ofSize: 11, weight: .medium)
        footer.textColor = isPlaying ? Theme.playing : Theme.muted

        let overlay = ReplayBubbleButton(title: "", target: target, action: action)
        overlay.isBordered = false
        overlay.filePath = item.file
        overlay.itemID = item.id
        overlay.isEnabled = item.file != nil
        overlay.toolTip = item.file == nil ? "Audio not ready yet" : (isPlaying ? "Stop playback" : "Replay this message")
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
            bubble.widthAnchor.constraint(equalToConstant: 356),
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
        let mode = item.mode?.capitalized ?? "Message"
        let status = isPlaying ? "Playing" : (item.status?.capitalized ?? "Queued")
        let speed = item.speed ?? "1.35"
        return "\(mode) / \(status) / \(speed)x"
    }

    private func glyphText(for item: VoiceItem, isPlaying: Bool) -> String {
        if isPlaying { return "||" }
        return item.status == "ready" ? ">" : "..."
    }

    private func footerText(for item: VoiceItem, isPlaying: Bool) -> String {
        if isPlaying { return "Playing now - click to stop" }
        return item.file == nil ? "Audio rendering" : "Click to replay"
    }

    private func color(for status: String?, isPlaying: Bool) -> NSColor {
        if isPlaying { return Theme.playing }
        switch status {
        case "ready": return Theme.green
        case "generating": return .systemOrange
        default: return Theme.muted
        }
    }
}

final class VoicePopoverController: NSViewController {
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
    var onClearInbox: (() -> Void)?
    var onQuit: (() -> Void)?
    var onConfigChanged: (() -> Void)?
    private var playingFile: String?

    private let modeControl = NSSegmentedControl(labels: ["Auto", "Notify", "Silent"], trackingMode: .selectOne, target: nil, action: nil)
    private let speedControl = NSSegmentedControl(labels: ["1.20", "1.28", "1.35", "1.45"], trackingMode: .selectOne, target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Waiting for messages")
    private let notificationLabel = NSTextField(labelWithString: "Notifications: checking")
    private let inboxScrollView = NSScrollView()
    private let inboxDocument = InboxDocumentView()
    private let replayButton = NSButton(title: "Replay Last", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let speakTestButton = NSButton(title: "Speak Test", target: nil, action: nil)
    private let requestNotificationsButton = NSButton(title: "Request", target: nil, action: nil)
    private let testNotificationButton = NSButton(title: "Test", target: nil, action: nil)
    private let clearInboxButton = NSButton(title: "Clear", target: nil, action: nil)

    init(store: VoiceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 720))
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
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
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

        statusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        statusLabel.textColor = Theme.muted
        root.addArrangedSubview(statusLabel)

        let notifyRow = NSStackView()
        notifyRow.orientation = .horizontal
        notifyRow.alignment = .centerY
        notifyRow.spacing = 8
        notificationLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        notificationLabel.textColor = Theme.muted
        let notifySpacer = NSView()
        notifySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        notifyRow.addArrangedSubview(notificationLabel)
        notifyRow.addArrangedSubview(notifySpacer)
        for button in [requestNotificationsButton, testNotificationButton] {
            button.bezelStyle = .rounded
            notifyRow.addArrangedSubview(button)
        }
        requestNotificationsButton.target = self
        requestNotificationsButton.action = #selector(requestNotificationsTapped)
        testNotificationButton.target = self
        testNotificationButton.action = #selector(testNotificationTapped)
        root.addArrangedSubview(panel(notifyRow, fill: false))

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.spacing = 8
        controls.addArrangedSubview(labeledRow("Delivery", modeControl, labelWidth: 62))
        controls.addArrangedSubview(labeledRow("Speed", speedControl, labelWidth: 62))
        root.addArrangedSubview(panel(controls, fill: false))
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        speedControl.target = self
        speedControl.action = #selector(speedChanged)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        for button in [replayButton, stopButton, speakTestButton] {
            button.bezelStyle = .rounded
            buttons.addArrangedSubview(button)
        }
        replayButton.target = self
        replayButton.action = #selector(replayTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        speakTestButton.target = self
        speakTestButton.action = #selector(speakTestTapped)
        root.addArrangedSubview(buttons)

        let inboxHeader = NSStackView()
        inboxHeader.orientation = .horizontal
        inboxHeader.alignment = .centerY
        let inboxTitle = NSTextField(labelWithString: "Inbox")
        inboxTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        inboxTitle.textColor = Theme.muted
        let inboxSpacer = NSView()
        inboxSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        clearInboxButton.bezelStyle = .rounded
        clearInboxButton.target = self
        clearInboxButton.action = #selector(clearInboxTapped)
        inboxHeader.addArrangedSubview(inboxTitle)
        inboxHeader.addArrangedSubview(inboxSpacer)
        inboxHeader.addArrangedSubview(clearInboxButton)
        root.addArrangedSubview(inboxHeader)

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
            inboxPanel.heightAnchor.constraint(equalToConstant: 396),
            inboxScrollView.leadingAnchor.constraint(equalTo: inboxPanel.leadingAnchor, constant: 10),
            inboxScrollView.trailingAnchor.constraint(equalTo: inboxPanel.trailingAnchor, constant: -10),
            inboxScrollView.topAnchor.constraint(equalTo: inboxPanel.topAnchor, constant: 10),
            inboxScrollView.bottomAnchor.constraint(equalTo: inboxPanel.bottomAnchor, constant: -10),
        ])
        root.addArrangedSubview(inboxPanel)

        let bottom = NSStackView()
        bottom.orientation = .horizontal
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
        footer.font = .systemFont(ofSize: 11, weight: .medium)
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

    private func panel(_ content: NSView, fill: Bool) -> NSView {
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
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
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

    func setPlayingFile(_ file: String?) {
        playingFile = file
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

        let speeds = ["1.20", "1.28", "1.35", "1.45"]
        speedControl.selectedSegment = speeds.firstIndex(of: config.speed) ?? 2

        let modeText = config.mode.capitalized
        let updated = state?.updated_at ?? "never"
        statusLabel.stringValue = "\(modeText) mode / updated \(updated)"

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
                    self?.notificationLabel.stringValue = "Notifications: authorized"
                    self?.notificationLabel.textColor = Theme.cyan
                case .denied:
                    self?.notificationLabel.stringValue = "Notifications: denied"
                    self?.notificationLabel.textColor = .systemRed
                case .notDetermined:
                    self?.notificationLabel.stringValue = "Notifications: not registered"
                    self?.notificationLabel.textColor = .systemOrange
                @unknown default:
                    self?.notificationLabel.stringValue = "Notifications: unknown"
                    self?.notificationLabel.textColor = .secondaryLabelColor
                }
            }
        }
    }

    private func rebuildInbox() {
        for subview in inboxDocument.subviews {
            subview.removeFromSuperview()
        }
        let items = store.recentItems(limit: 80)
        let width: CGFloat = max(420, inboxScrollView.contentSize.width)
        if items.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No messages yet. Notify and silent mode still save incoming agent speech here.")
            empty.textColor = Theme.muted
            empty.font = .systemFont(ofSize: 12.5)
            empty.frame = NSRect(x: 12, y: 14, width: width - 24, height: 44)
            inboxDocument.addSubview(empty)
            inboxDocument.frame = NSRect(x: 0, y: 0, width: width, height: 396)
            return
        }
        var y: CGFloat = 0
        for item in items {
            let row = BubbleRow(item: item, isPlaying: item.file == playingFile, target: self, action: #selector(replayBubble(_:)))
            row.translatesAutoresizingMaskIntoConstraints = true
            row.frame = NSRect(x: 0, y: y, width: width, height: 92)
            inboxDocument.addSubview(row)
            y += 100
        }
        inboxDocument.frame = NSRect(x: 0, y: 0, width: width, height: max(396, y))
        inboxDocument.needsLayout = true
        inboxDocument.needsDisplay = true
    }

    @objc private func replayBubble(_ sender: ReplayBubbleButton) {
        guard let file = sender.filePath else { return }
        onReplayFile?(file)
    }

    @objc private func modeChanged() {
        let modes = ["autoplay", "notify", "silent"]
        var config = store.readConfig()
        config.mode = modes[max(0, modeControl.selectedSegment)]
        store.writeConfig(config)
        reload()
        onConfigChanged?()
    }

    @objc private func speedChanged() {
        let speeds = ["1.20", "1.28", "1.35", "1.45"]
        var config = store.readConfig()
        config.speed = speeds[max(0, speedControl.selectedSegment)]
        store.writeConfig(config)
        reload()
        onConfigChanged?()
    }

    @objc private func replayTapped() { onReplayLast?() }
    @objc private func stopTapped() { onStop?() }
    @objc private func speakTestTapped() { onSpeakTest?() }
    @objc private func requestNotificationsTapped() { onRequestNotifications?() }
    @objc private func testNotificationTapped() { onTestNotification?() }
    @objc private func openNotificationSettingsTapped() { onOpenNotificationSettings?() }
    @objc private func openPronunciationsTapped() { onOpenPronunciations?() }
    @objc private func openFolderTapped() { onOpenFolder?() }
    @objc private func clearInboxTapped() { onClearInbox?() }
    @objc private func quitTapped() { onQuit?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let store = VoiceStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: NSPanel!
    private var popoverController: VoicePopoverController!
    private var timer: Timer?
    private var lastSeenStateKey: String?
    private var playbackProcess: Process?
    private var playingFile: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureNotifications(requestPermission: true)
        configurePopover()
        configureStatusItem()
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh(initial: false)
        }
    }

    private func configureNotifications(requestPermission: Bool) {
        let replay = UNNotificationAction(identifier: "REPLAY_LAST", title: "Replay", options: [])
        let category = UNNotificationCategory(identifier: "VOICE_MESSAGE", actions: [replay], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        if requestPermission {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
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
        popoverController.onClearInbox = { [weak self] in self?.clearInbox() }
        popoverController.onQuit = { NSApp.terminate(nil) }
        popoverController.onConfigChanged = { [weak self] in self?.updateIcon() }
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 720),
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
        if let command = store.consumeCommand() {
            handle(command: command)
        }
        updateIcon()
        popoverController.reload()
        guard let item = store.readState()?.last, let id = item.id else { return }
        let key = "\(id):\(item.status ?? "")"
        if initial {
            lastSeenStateKey = key
            return
        }
        if key != lastSeenStateKey {
            lastSeenStateKey = key
            if item.mode == "notify" && item.status == "ready" {
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
        default:
            NSLog("Agent Voice Bar unknown command: \(command.command)")
        }
    }

    private func updateIcon() {
        let config = store.readConfig()
        let symbol: String
        switch config.mode {
        case "notify": symbol = "bell.badge.circle.fill"
        case "silent": symbol = "speaker.slash.circle.fill"
        default: symbol = "waveform.circle.fill"
        }
        if let button = statusItem.button,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Agent Voice") {
            image.isTemplate = true
            button.image = image
            button.toolTip = "Agent Voice Bar: \(config.mode.capitalized)"
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
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.panel.makeKeyAndOrderFront(nil)
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
        if deliverTerminalNotification(for: item) {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Agent Voice Bar"
        content.subtitle = "Voice message ready"
        content.body = item.text ?? "A new voice message is ready."
        content.sound = .default
        content.categoryIdentifier = "VOICE_MESSAGE"
        content.userInfo = ["file": item.file ?? ""]
        let request = UNNotificationRequest(identifier: item.id ?? UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Agent Voice Bar notification error: \(error.localizedDescription)")
            } else {
                NSLog("Agent Voice Bar UN notification accepted")
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
            mode: "notify",
            status: "ready",
            voice: "Chelsie",
            speed: nil,
            temperature: nil,
            top_p: nil,
            text: text,
            speech_text: nil,
            file: store.readState()?.last?.file
        )
        store.appendManualItem(item)
        popoverController.reload()
        deliverNotification(for: item)
    }

    private func deliverTerminalNotification(for item: VoiceItem) -> Bool {
        let candidates = [
            "/opt/homebrew/bin/terminal-notifier",
            "/usr/local/bin/terminal-notifier",
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            NSLog("Agent Voice Bar terminal-notifier not installed")
            return false
        }
        NSLog("Agent Voice Bar delivering terminal-notifier notification")
        let process = Process()
        process.launchPath = executable
        process.arguments = [
            "-title", "Agent Voice Bar",
            "-subtitle", "Voice message ready",
            "-message", String((item.text ?? "A new voice message is ready.").prefix(240)),
            "-sound", "Glass",
            "-group", item.id ?? "codex-voice-bar",
            "-activate", "com.collincraig.agentvoicebar",
        ]
        do {
            try process.run()
            return true
        } catch {
            NSLog("Agent Voice Bar terminal-notifier error: \(error.localizedDescription)")
            return false
        }
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

        let process = Process()
        process.launchPath = "/usr/bin/afplay"
        process.arguments = [file]
        playbackProcess = process
        playingFile = file
        popoverController.setPlayingFile(file)
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self, self.playbackProcess === process else { return }
                self.playbackProcess = nil
                self.playingFile = nil
                self.popoverController.setPlayingFile(nil)
            }
        }
        do {
            try process.run()
        } catch {
            playbackProcess = nil
            playingFile = nil
            popoverController.setPlayingFile(nil)
        }
    }

    private func stopPlayback() {
        playbackProcess?.terminate()
        playbackProcess = nil
        playingFile = nil
        popoverController.setPlayingFile(nil)
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
        store.clearInbox()
        popoverController.reload()
    }

    private func speakTestLine() {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 99,
            "method": "tools/call",
            "params": [
                "name": "speak_text",
                "arguments": [
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
