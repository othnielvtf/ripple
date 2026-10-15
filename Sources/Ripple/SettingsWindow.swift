import AppKit

final class ColourSwatch: SymbolButton {
    let theme: ColourTheme
    init(theme: ColourTheme) {
        self.theme = theme
        super.init(frame: .zero)
        isBordered = false
        setAccessibilityLabel("\(theme.title) colour theme")
        toolTip = theme.title
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 76).isActive = true
        heightAnchor.constraint(equalToConstant: 66).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSRect(x: bounds.midX - 14, y: 27, width: 28, height: 28)
        theme.colour(dark: Palette.isDark).setFill()
        NSBezierPath(ovalIn: dot).fill()
        if state == .on {
            Palette.text.setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -4, dy: -4))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: state == .on ? .semibold : .regular),
            .foregroundColor: state == .on ? Palette.text : Palette.secondary
        ]
        let text = theme.title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 4), withAttributes: attributes)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let associations: FileAssociationManager
    private let modes = NSSegmentedControl(labels: ["Auto", "Light", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    private let sections = NSSegmentedControl(labels: ["Appearance", "File Associations"], trackingMode: .selectOne, target: nil, action: nil)
    private let effects = NSSegmentedControl(labels: SliderEffect.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let effectDescription = textLabel("", size: 11, color: .secondary)
    private let effectPreview = EffectSlider(initialValue: 0.62)
    private var pages: [NSStackView] = []
    private var swatches: [ColourSwatch] = []
    private var formatButtons: [String: NSButton] = [:]
    private var formatStatus: [String: NSTextField] = [:]
    private let makeAll = NSButton()
    private let messageLabel = textLabel("", size: 11, color: .secondary)

    init(settings: AppSettings? = nil, associations: FileAssociationManager? = nil) {
        self.settings = settings ?? .shared
        self.associations = associations ?? FileAssociationManager()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ripple Settings"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.background
        super.init(window: window)
        buildInterface()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .rippleThemeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAssociations), name: NSApplication.didBecomeActiveNotification, object: nil)
        self.associations.onChange = { [weak self] in self?.refreshAssociationControls() }
        themeChanged()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        associations.refresh()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildInterface() {
        guard let window else { return }
        let surface = ThemeSurface()
        window.contentView = surface
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: surface.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -28),
            root.bottomAnchor.constraint(lessThanOrEqualTo: surface.bottomAnchor, constant: -18)
        ])
        root.addArrangedSubview(textLabel("Make it yours.", size: 25, weight: .semibold))
        root.setCustomSpacing(5, after: root.arrangedSubviews.last!)
        root.addArrangedSubview(textLabel("A little personality. The same simple player.", size: 12, color: .secondary))
        root.setCustomSpacing(22, after: root.arrangedSubviews.last!)
        sections.selectedSegment = 0
        sections.target = self
        sections.action = #selector(changeSection(_:))
        sections.segmentDistribution = .fillEqually
        sections.setAccessibilityLabel("Settings section")
        addFullWidth(sections, to: root)
        addFullWidth(ThemeDivider(), to: root)

        let container = NSView()
        pages = [makeAppearancePage(), makeAssociationPage()]
        for page in pages {
            container.addSubview(page)
            page.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                page.topAnchor.constraint(equalTo: container.topAnchor),
                page.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
            ])
            page.setContentHuggingPriority(.required, for: .vertical)
        }
        pages[1].isHidden = true
        addFullWidth(container, to: root)
    }

    private func makePage() -> NSStackView {
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 14
        return page
    }

    private func makeAppearancePage() -> NSStackView {
        let page = makePage()
        page.addArrangedSubview(textLabel("APPEARANCE", size: 10, weight: .semibold, color: .secondary))

        modes.target = self
        modes.action = #selector(changeMode(_:))
        modes.segmentDistribution = .fillEqually
        modes.setAccessibilityLabel("Window appearance")
        modes.translatesAutoresizingMaskIntoConstraints = false
        modes.widthAnchor.constraint(equalToConstant: 240).isActive = true
        addFullWidth(horizontal([textLabel("Window appearance", size: 13, weight: .medium), spacer(), modes]), to: page)
        page.setCustomSpacing(4, after: page.arrangedSubviews.last!)
        page.addArrangedSubview(textLabel("Auto follows your Mac’s Light or Dark appearance.", size: 11, color: .secondary))
        page.setCustomSpacing(17, after: page.arrangedSubviews.last!)
        page.addArrangedSubview(textLabel("Colour theme", size: 13, weight: .medium))
        page.setCustomSpacing(7, after: page.arrangedSubviews.last!)

        swatches = ColourTheme.allCases.map { theme in
            let swatch = ColourSwatch(theme: theme)
            swatch.target = self
            swatch.action = #selector(changeColour(_:))
            return swatch
        }
        let swatchRow = horizontal(swatches, spacing: 8)
        addFullWidth(swatchRow, to: page)


        addFullWidth(ThemeDivider(), to: page)
        effects.target = self
        effects.action = #selector(changeEffect(_:))
        effects.segmentDistribution = .fillEqually
        effects.setAccessibilityLabel("Progress and volume slider effect")
        effects.translatesAutoresizingMaskIntoConstraints = false
        effects.widthAnchor.constraint(equalToConstant: 288).isActive = true
        addFullWidth(horizontal([textLabel("Slider effect", size: 13, weight: .medium), spacer(), effects]), to: page)
        page.setCustomSpacing(4, after: page.arrangedSubviews.last!)
        addFullWidth(effectDescription, to: page)
        page.setCustomSpacing(10, after: effectDescription)
        effectPreview.controlSize = .small
        effectPreview.setAccessibilityLabel("Slider effect preview")
        addFullWidth(horizontal([textLabel("PREVIEW", size: 9, weight: .semibold, color: .secondary), effectPreview], spacing: 18), to: page)
        page.addArrangedSubview(textLabel("Applies to both playback position and volume.", size: 11, color: .secondary))
        return page
    }

    private func makeAssociationPage() -> NSStackView {
        let page = makePage()
        page.addArrangedSubview(textLabel("DEFAULT AUDIO PLAYER", size: 10, weight: .semibold, color: .secondary))
        page.setCustomSpacing(4, after: page.arrangedSubviews.last!)
        page.addArrangedSubview(textLabel("Open these audio files in Ripple when you double-click them.", size: 12, color: .secondary))
        page.setCustomSpacing(10, after: page.arrangedSubviews.last!)

        let formats = NSStackView()
        formats.orientation = .vertical
        formats.alignment = .leading
        formats.spacing = 4
        for (index, format) in AudioFileFormat.all.enumerated() {
            let title = textLabel(format.title, size: 12, weight: .semibold)
            title.translatesAutoresizingMaskIntoConstraints = false
            title.widthAnchor.constraint(equalToConstant: 42).isActive = true
            let detail = textLabel(format.extensions, size: 10, color: .secondary)
            let name = NSStackView(views: [title, detail])
            name.orientation = .vertical
            name.alignment = .leading
            name.spacing = 2
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let status = textLabel("", size: 11, color: .secondary)
            formatStatus[format.id] = status
            let button = NSButton(title: "Make Default", target: self, action: #selector(setFormatDefault(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.setAccessibilityLabel("Make Ripple the default for \(format.title)")
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 115).isActive = true
            formatButtons[format.id] = button
            let row = horizontal([name, status, spacer(), button], spacing: 12)
            row.heightAnchor.constraint(equalToConstant: 38).isActive = true
            addFullWidth(row, to: formats)
        }
        addFullWidth(formats, to: page)
        page.setCustomSpacing(12, after: formats)

        makeAll.title = "Make Default for All"
        makeAll.target = self
        makeAll.action = #selector(setAllDefaults(_:))
        makeAll.bezelStyle = .rounded
        makeAll.font = .systemFont(ofSize: 12, weight: .medium)
        let allRow = horizontal([spacer(), makeAll])
        addFullWidth(allRow, to: page)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping
        addFullWidth(messageLabel, to: page)
        return page
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        return row
    }
    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    @objc private func themeChanged() {
        window?.backgroundColor = Palette.background
        if let content = window?.contentView { applyTheme(to: content) }
        modes.selectedSegment = AppearanceMode.allCases.firstIndex(of: settings.appearance) ?? 0
        modes.selectedSegmentBezelColor = settings.colour.colour(dark: false)
        sections.selectedSegmentBezelColor = settings.colour.colour(dark: false)
        effects.selectedSegmentBezelColor = settings.colour.colour(dark: false)
        effects.selectedSegment = SliderEffect.allCases.firstIndex(of: settings.sliderEffect) ?? 0
        effectDescription.stringValue = settings.sliderEffect.summary
        for swatch in swatches {
            swatch.state = swatch.theme == settings.colour ? .on : .off
            swatch.setAccessibilityValue(swatch.state == .on ? "Selected" : "Not selected")
            swatch.needsDisplay = true
        }
        refreshAssociationControls()
    }
    @objc private func changeSection(_ sender: NSSegmentedControl) {
        for (index, page) in pages.enumerated() { page.isHidden = index != sender.selectedSegment }
    }
    @objc private func changeEffect(_ sender: NSSegmentedControl) {
        guard SliderEffect.allCases.indices.contains(sender.selectedSegment) else { return }
        settings.sliderEffect = SliderEffect.allCases[sender.selectedSegment]
    }
    @objc private func changeMode(_ sender: NSSegmentedControl) {
        guard AppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
        settings.appearance = AppearanceMode.allCases[sender.selectedSegment]
    }
    @objc private func changeColour(_ sender: ColourSwatch) { settings.colour = sender.theme }
    @objc private func refreshAssociations() { associations.refresh() }
    @objc private func setFormatDefault(_ sender: NSButton) {
        guard AudioFileFormat.all.indices.contains(sender.tag) else { return }
        Task { await associations.makeDefault(for: [AudioFileFormat.all[sender.tag]]) }
    }
    @objc private func setAllDefaults(_ sender: Any?) {
        Task { await associations.makeDefault(for: AudioFileFormat.all) }
    }
    private func refreshAssociationControls() {
        for format in AudioFileFormat.all {
            let isDefault = associations.isDefault(for: format)
            let pending = associations.pendingID == format.id
            formatStatus[format.id]?.stringValue = isDefault ? "Ripple is the default" : "Current: \(associations.applicationName(for: format))"
            formatStatus[format.id]?.textColor = isDefault ? Palette.accent : Palette.secondary
            formatButtons[format.id]?.title = pending ? "Setting…" : (isDefault ? "Default ✓" : "Make Default")
            formatButtons[format.id]?.isEnabled = associations.canSetDefaults && !associations.isBusy && !isDefault
        }
        let allDefault = AudioFileFormat.all.allSatisfy { associations.isDefault(for: $0) }
        makeAll.title = allDefault ? "Default for All ✓" : "Make Default for All"
        makeAll.isEnabled = associations.canSetDefaults && !associations.isBusy && !allDefault
        messageLabel.stringValue = associations.message.isEmpty ? "macOS may ask you to confirm a change of default app." : associations.message
    }
}
