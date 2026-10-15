import AppKit
import UniformTypeIdentifiers

func textLabel(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
               color: Palette.Role = .text) -> NSTextField {
    let label = ThemeLabel(labelWithString: string)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.colourRole = color
    label.applyTheme()
    label.lineBreakMode = .byTruncatingMiddle
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

final class PlayerWindow: NSWindow {
    var handleKey: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

class SymbolButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
}

final class DropSurface: ThemeSurface {
    var onDrop: (([URL]) -> Void)?
    private var highlighted = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { PlaybackController.supportedExtensions.contains($0.pathExtension.lowercased()) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = !fileURLs(sender).isEmpty
        return highlighted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        !fileURLs(sender).isEmpty ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if highlighted {
            Palette.accent.withAlphaComponent(0.08).setFill()
            bounds.fill()
            Palette.accent.setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 7), xRadius: 12, yRadius: 12)
            border.lineWidth = 2
            border.stroke()
        }
    }
}

final class RecordArtwork: NSView {
    var active = false { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 110) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        Palette.panel.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        for (radius, alpha) in [(44.0, 0.12), (35.0, 0.2), (26.0, 0.3)] {
            Palette.accent.withAlphaComponent(alpha).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
            ring.lineWidth = 1
            ring.stroke()
        }
        (active ? Palette.accent : Palette.secondary).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 17, y: center.y - 17, width: 34, height: 34)).fill()
        Palette.background.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)).fill()
    }
}

final class QueueRow: NSTableCellView {
    let number = textLabel("", size: 11, color: .secondary)
    let name = textLabel("", size: 12, weight: .medium)
    let format = textLabel("", size: 10, weight: .semibold, color: .secondary)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let row = NSStackView(views: [number, name, format])
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            number.widthAnchor.constraint(equalToConstant: 22),
            format.widthAnchor.constraint(equalToConstant: 40)
        ])
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        format.alignment = .right
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class QueueSelectionRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Palette.accent.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7).fill()
    }
}

@MainActor
final class PlayerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let playback: PlaybackController
    var onOpenSettings: (() -> Void)?
    private let titleLabel = textLabel("Make room for sound.", size: 25, weight: .semibold)
    private let subtitleLabel = textLabel("Drop a file here, or open your next listen.", size: 13, color: .secondary)
    private let detailsLabel = textLabel("MP3, WAV, M4A & AIFF", size: 11, color: .secondary)
    private let stateLabel = textLabel("READY WHEN YOU ARE", size: 10, weight: .semibold, color: .accent)
    private let elapsed = textLabel("0:00", size: 11, color: .secondary)
    private let remaining = textLabel("0:00", size: 11, color: .secondary)
    private let queueLabel = textLabel("YOUR QUEUE", size: 10, weight: .semibold, color: .secondary)
    private let queueHint = textLabel("Your next listen starts here.", size: 12, color: .secondary)
    private let footerLabel = textLabel("LOCAL FILES. JUST PRESS PLAY.", size: 9, weight: .medium, color: .secondary)
    private let artwork = RecordArtwork()
    private let progress = EffectSlider(initialValue: 0)
    private let volume = EffectSlider(initialValue: 0.8)
    private let table = NSTableView()
    private let playButton = SymbolButton()
    private let previousButton = SymbolButton()
    private let nextButton = SymbolButton()
    private let repeatButton = SymbolButton()
    private let clearButton = NSButton()
    private let settingsButton = SymbolButton()
    private var accentButtons: [NSButton] = []
    private var updatingSelection = false

    init(playback: PlaybackController) {
        self.playback = playback
        let window = PlayerWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Ripple"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Palette.background
        window.minSize = NSSize(width: 600, height: 540)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .rippleThemeChanged, object: nil)
        playback.onChange = { [weak self] in self?.refresh() }
        playback.onProgress = { [weak self] in self?.refreshProgress() }
        playback.onError = { [weak self] message in self?.showError(message) }
        window.handleKey = { [weak self] event in
            guard self?.window?.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            switch event.keyCode {
            case 49: self?.togglePlayback(nil); return true
            case 123: self?.playback.skip(by: -5); return true
            case 124: self?.playback.skip(by: 5); return true
            default: return false
            }
        }
        themeChanged()
        window.center()
        window.setFrameAutosaveName("RipplePlayerWindow")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        guard let window else { return }
        let surface = DropSurface()
        surface.onDrop = { [weak self] urls in self?.playback.open(urls) }
        window.contentView = surface
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: surface.topAnchor, constant: 44),
            root.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -28),
            root.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -20)
        ])

        let brand = textLabel("ripple", size: 24, weight: .bold)
        let brandDot = textLabel("●", size: 10, color: .accent)
        let openButton = NSButton(title: "Open audio…", target: self, action: #selector(openAudio(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.font = .systemFont(ofSize: 12, weight: .medium)
        openButton.toolTip = "Open audio files (⌘O)"
        configureButton(settingsButton, symbol: "gearshape", label: "Settings", action: #selector(openSettings(_:)), width: 30)
        settingsButton.toolTip = "Settings (⌘,)"
        let header = horizontal([brand, brandDot, flexibleSpace(), settingsButton, openButton], spacing: 7)
        addFullWidth(header, to: root)
        addFullWidth(divider(), to: root)

        titleLabel.maximumNumberOfLines = 1
        subtitleLabel.maximumNumberOfLines = 1
        let metadata = NSStackView(views: [stateLabel, titleLabel, subtitleLabel, detailsLabel])
        metadata.orientation = .vertical
        metadata.alignment = .leading
        metadata.spacing = 9
        let hero = horizontal([artwork, metadata], spacing: 22)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 110),
            artwork.heightAnchor.constraint(equalToConstant: 110)
        ])
        addFullWidth(hero, to: root)

        progress.target = self
        progress.action = #selector(scrub(_:))
        progress.isContinuous = true
        progress.controlSize = .small
        progress.setAccessibilityLabel("Playback position")
        let timeline = NSStackView()
        timeline.orientation = .vertical
        timeline.spacing = 3
        addFullWidth(progress, to: timeline)
        elapsed.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        remaining.font = elapsed.font
        addFullWidth(horizontal([elapsed, flexibleSpace(), remaining]), to: timeline)
        addFullWidth(timeline, to: root)
        root.setCustomSpacing(10, after: timeline)

        configureButton(previousButton, symbol: "backward.end.fill", label: "Previous track", action: #selector(previous(_:)), width: 36)
        configureButton(playButton, symbol: "play.fill", label: "Play", action: #selector(togglePlayback(_:)), width: 54)
        playButton.layer?.backgroundColor = Palette.accent.cgColor
        playButton.layer?.cornerRadius = 27
        playButton.contentTintColor = Palette.background
        configureButton(nextButton, symbol: "forward.end.fill", label: "Next track", action: #selector(next(_:)), width: 36)
        configureButton(repeatButton, symbol: "repeat.1", label: "Repeat current track", action: #selector(toggleRepeat(_:)), width: 30)
        let transport = horizontal([previousButton, playButton, nextButton], spacing: 14)
        let soundIcon = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")!)
        soundIcon.contentTintColor = Palette.secondary
        volume.target = self
        volume.action = #selector(changeVolume(_:))
        volume.isContinuous = true
        volume.controlSize = .small
        volume.setAccessibilityLabel("Volume")
        volume.translatesAutoresizingMaskIntoConstraints = false
        volume.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let volumeControls = horizontal([soundIcon, volume], spacing: 8)
        volumeControls.translatesAutoresizingMaskIntoConstraints = false
        volumeControls.widthAnchor.constraint(equalToConstant: 122).isActive = true
        let repeatHolder = horizontal([repeatButton, flexibleSpace()])
        repeatHolder.translatesAutoresizingMaskIntoConstraints = false
        repeatHolder.widthAnchor.constraint(equalToConstant: 122).isActive = true
        let controls = NSView()
        for view in [repeatHolder, transport, volumeControls] {
            view.translatesAutoresizingMaskIntoConstraints = false
            controls.addSubview(view)
            view.centerYAnchor.constraint(equalTo: controls.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            controls.heightAnchor.constraint(equalToConstant: 54),
            repeatHolder.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            transport.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            volumeControls.trailingAnchor.constraint(equalTo: controls.trailingAnchor)
        ])
        addFullWidth(controls, to: root)
        addFullWidth(divider(), to: root)

        let addButton = NSButton(title: "Add files", target: self, action: #selector(addAudio(_:)))
        addButton.isBordered = false
        addButton.font = .systemFont(ofSize: 11, weight: .medium)
        addButton.contentTintColor = Palette.accent
        addButton.toolTip = "Add files to the queue (⇧⌘O)"
        accentButtons.append(addButton)
        clearButton.title = "Clear"
        clearButton.target = self
        clearButton.action = #selector(clearQueue(_:))
        clearButton.isBordered = false
        clearButton.font = addButton.font
        clearButton.contentTintColor = Palette.secondary
        addFullWidth(horizontal([queueLabel, flexibleSpace(), addButton, clearButton], spacing: 14), to: root)
        root.setCustomSpacing(8, after: root.arrangedSubviews.last!)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Track"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 36
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = Palette.background
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(playSelected(_:))
        table.setAccessibilityLabel("Playback queue. Select a file to play.")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let queueContainer = NSView()
        queueContainer.addSubview(scroll)
        queueContainer.addSubview(queueHint)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        queueHint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: queueContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: queueContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: queueContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: queueContainer.bottomAnchor),
            queueHint.centerXAnchor.constraint(equalTo: queueContainer.centerXAnchor),
            queueHint.centerYAnchor.constraint(equalTo: queueContainer.centerYAnchor),
            queueContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
        addFullWidth(queueContainer, to: root)
        queueContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let shortcuts = textLabel("SPACE  play / pause     ← →  seek 5s", size: 10, color: .secondary)
        addFullWidth(horizontal([footerLabel, flexibleSpace(), shortcuts]), to: root)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }
    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    private func divider() -> NSView {
        ThemeDivider()
    }
    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector, width: CGFloat) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: width > 40 ? 22 : 16, weight: .medium))
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = action
        button.contentTintColor = Palette.text
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: width).isActive = true
    }

    @objc private func themeChanged() {
        window?.backgroundColor = Palette.background
        if let content = window?.contentView { applyTheme(to: content) }
        playButton.layer?.backgroundColor = Palette.accent.cgColor
        playButton.contentTintColor = Palette.background
        previousButton.contentTintColor = Palette.text
        nextButton.contentTintColor = Palette.text
        settingsButton.contentTintColor = Palette.secondary
        clearButton.contentTintColor = Palette.secondary
        for button in accentButtons { button.contentTintColor = Palette.accent }
        table.backgroundColor = Palette.background
        refresh()
    }

    private func refresh() {
        let track = playback.currentTrack
        titleLabel.stringValue = track?.title ?? "Make room for sound."
        titleLabel.toolTip = track?.url.lastPathComponent
        subtitleLabel.stringValue = track.map { $0.url.deletingLastPathComponent().lastPathComponent } ?? "Drop a file here, or open your next listen."
        subtitleLabel.toolTip = track?.url.path
        detailsLabel.stringValue = playback.audioDetails
        stateLabel.stringValue = track == nil ? "READY WHEN YOU ARE" : (playback.isPlaying ? "NOW PLAYING" : "PAUSED")
        artwork.active = track != nil
        playButton.image = NSImage(systemSymbolName: playback.isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: playback.isPlaying ? "Pause" : "Play")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        playButton.setAccessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        playButton.toolTip = playback.isPlaying ? "Pause (Space)" : "Play (Space)"
        previousButton.isEnabled = track != nil
        nextButton.isEnabled = (playback.currentIndex.map { $0 + 1 < playback.queue.count }) ?? false
        repeatButton.contentTintColor = playback.repeatOne ? Palette.accent : Palette.secondary
        repeatButton.layer?.backgroundColor = playback.repeatOne ? Palette.panel.cgColor : NSColor.clear.cgColor
        repeatButton.setAccessibilityValue(playback.repeatOne ? "On" : "Off")
        repeatButton.toolTip = playback.repeatOne ? "Repeat current track: On (⌘L)" : "Repeat current track: Off (⌘L)"
        volume.floatValue = playback.volume
        queueLabel.stringValue = playback.queue.isEmpty ? "YOUR QUEUE" : "YOUR QUEUE  ·  \(playback.queue.count) \(playback.queue.count == 1 ? "FILE" : "FILES")"
        queueHint.isHidden = !playback.queue.isEmpty
        clearButton.isEnabled = !playback.queue.isEmpty
        window?.title = track.map { "\($0.title) — Ripple" } ?? "Ripple"
        updatingSelection = true
        table.reloadData()
        if let index = playback.currentIndex { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        updatingSelection = false
        refreshProgress()
    }

    private func refreshProgress() {
        progress.isEnabled = playback.player != nil
        progress.maxValue = max(1, playback.duration)
        progress.doubleValue = playback.currentTime
        elapsed.stringValue = Self.timestamp(playback.currentTime)
        remaining.stringValue = playback.player == nil ? "0:00" : "−" + Self.timestamp(max(0, playback.duration - playback.currentTime))
    }

    static func timestamp(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.isFinite ? time : 0))
        return seconds >= 3_600 ? String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @objc func openAudio(_ sender: Any?) { openPanel(append: false) }
    @objc func openSettings(_ sender: Any?) { onOpenSettings?() }
    @objc func addAudio(_ sender: Any?) { openPanel(append: true) }
    private func openPanel(append: Bool) {
        let panel = NSOpenPanel()
        panel.title = append ? "Add audio to your queue" : "Open audio"
        panel.prompt = append ? "Add files" : "Play"
        panel.allowedContentTypes = PlaybackController.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.playback.open(panel.urls, append: append) }
        }
    }
    @objc func togglePlayback(_ sender: Any?) {
        if playback.queue.isEmpty { openAudio(sender) } else { playback.togglePlayback() }
    }
    @objc func previous(_ sender: Any?) { playback.previous() }
    @objc func next(_ sender: Any?) { playback.next() }
    @objc func toggleRepeat(_ sender: Any?) { playback.repeatOne.toggle() }
    @objc func clearQueue(_ sender: Any?) { playback.clear() }
    @objc func scrub(_ sender: NSSlider) { playback.seek(to: sender.doubleValue) }
    @objc func changeVolume(_ sender: NSSlider) { playback.volume = sender.floatValue }
    @objc func playSelected(_ sender: Any?) {
        guard table.selectedRow >= 0 else { return }
        playback.select(table.selectedRow)
    }
    @objc func revealFile(_ sender: Any?) {
        if let url = playback.currentTrack?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { playback.queue.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { QueueSelectionRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = QueueRow()
        let track = playback.queue[row]
        let active = row == playback.currentIndex
        cell.number.stringValue = active && playback.isPlaying ? "▶" : String(format: "%02d", row + 1)
        cell.number.textColor = active ? Palette.accent : Palette.secondary
        cell.name.stringValue = track.title
        cell.name.textColor = active ? Palette.accent : Palette.text
        cell.name.toolTip = track.url.path
        cell.format.stringValue = track.format
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, table.selectedRow >= 0, table.selectedRow != playback.currentIndex else { return }
        if !playback.select(table.selectedRow) { refresh() }
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Unable to play audio"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) }
    }
}
