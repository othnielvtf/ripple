import AppKit

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                  green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum AppearanceMode: String, CaseIterable {
    case auto, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum SliderEffect: String, CaseIterable {
    case none, neon, glowy, laser
    var title: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .none: return "Classic sliders, without a light effect."
        case .neon: return "A vivid neon tube with a crisp, luminous edge."
        case .glowy: return "A soft halo of colour around the bar and handle."
        case .laser: return "A fine beam with a bright core and a sharp marker."
        }
    }
}

enum ColourTheme: String, CaseIterable {
    case mint, blue, yellow, orange, purple, pink
    var title: String { rawValue.capitalized }

    func colour(dark: Bool) -> NSColor {
        let pair: (Int, Int)
        switch self {
        case .mint: pair = (0xB8F3CE, 0x15764B)
        case .blue: pair = (0x91BFFF, 0x205CC3)
        case .yellow: pair = (0xF4D66E, 0x896100)
        case .orange: pair = (0xFFB26B, 0xAB4D0B)
        case .purple: pair = (0xCDB0FF, 0x7546B9)
        case .pink: pair = (0xF3A6CD, 0xAB3C75)
        }
        return NSColor(hex: dark ? pair.0 : pair.1)
    }
}

extension Notification.Name {
    static let rippleThemeChanged = Notification.Name("RippleThemeChanged")
}

enum Palette {
    static var isDark = true
    static var theme = ColourTheme.mint
    static var sliderEffect = SliderEffect.glowy
    static var background: NSColor { NSColor(hex: isDark ? 0x131B1E : 0xF7F9F8) }
    static var panel: NSColor { NSColor(hex: isDark ? 0x1E2A2D : 0xE8EFEC) }
    static var text: NSColor { NSColor(hex: isDark ? 0xF2F3EA : 0x182629) }
    static var secondary: NSColor { NSColor(hex: isDark ? 0x94A8AC : 0x52676D) }
    static var accent: NSColor { theme.colour(dark: isDark) }
    static var line: NSColor { NSColor(hex: isDark ? 0x304045 : 0xD4DFDA) }

    enum Role { case text, secondary, accent }
    static func colour(_ role: Role) -> NSColor {
        switch role {
        case .text: return text
        case .secondary: return secondary
        case .accent: return accent
        }
    }
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()
    private let defaults: UserDefaults
    private let appliesToApplication: Bool

    var appearance: AppearanceMode {
        didSet {
            guard oldValue != appearance else { return }
            defaults.set(appearance.rawValue, forKey: "appearanceMode")
            if appliesToApplication { apply() }
        }
    }
    var colour: ColourTheme {
        didSet {
            guard oldValue != colour else { return }
            defaults.set(colour.rawValue, forKey: "colourTheme")
            if appliesToApplication { apply() }
        }
    }
    var sliderEffect: SliderEffect {
        didSet {
            guard oldValue != sliderEffect else { return }
            defaults.set(sliderEffect.rawValue, forKey: "sliderEffect")
            if appliesToApplication { apply() }
        }
    }

    init(defaults: UserDefaults = .standard, appliesToApplication: Bool = true) {
        self.defaults = defaults
        self.appliesToApplication = appliesToApplication
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .auto
        colour = ColourTheme(rawValue: defaults.string(forKey: "colourTheme") ?? "") ?? .mint
        sliderEffect = SliderEffect(rawValue: defaults.string(forKey: "sliderEffect") ?? "") ?? .glowy
    }

    func apply() {
        NSApp.appearance = appearance.appearance
        Palette.isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        Palette.theme = colour
        Palette.sliderEffect = sliderEffect
        NotificationCenter.default.post(name: .rippleThemeChanged, object: self)
    }

    func systemAppearanceChanged(_ effectiveAppearance: NSAppearance) {
        guard appearance == .auto else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard dark != Palette.isDark else { return }
        Palette.isDark = dark
        NotificationCenter.default.post(name: .rippleThemeChanged, object: self)
    }
}

final class ThemeLabel: NSTextField {
    var colourRole: Palette.Role = .text
    func applyTheme() { textColor = Palette.colour(colourRole) }
}

class ThemeSurface: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        AppSettings.shared.systemAppearanceChanged(effectiveAppearance)
    }
}

final class ThemeDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.line.cgColor
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
func applyTheme(to view: NSView) {
    if let label = view as? ThemeLabel { label.applyTheme() }
    if view is ThemeSurface { view.layer?.backgroundColor = Palette.background.cgColor }
    if view is ThemeDivider { view.layer?.backgroundColor = Palette.line.cgColor }
    if let slider = view as? NSSlider { slider.trackFillColor = Palette.accent }
    if let image = view as? NSImageView { image.contentTintColor = Palette.secondary }
    view.needsDisplay = true
    for child in view.subviews { applyTheme(to: child) }
}
