import AppKit
import UniformTypeIdentifiers

@MainActor
final class FakeApplicationWorkspace: DefaultApplicationWorkspace {
    var applications: [String: URL] = [:]
    var failures: Set<String> = []
    var unapplied: Set<String> = []
    var calls: [String] = []

    func defaultApplication(for type: UTType) -> URL? { applications[type.identifier] }
    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        calls.append(type.identifier)
        await Task.yield()
        if failures.contains(type.identifier) { throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
        if !unapplied.contains(type.identifier) { applications[type.identifier] = url }
    }
}

@main
@MainActor
struct SettingsTests {
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("FAIL: \(message)") }
            checks += 1
            print("PASS: \(message)")
        }
        let suite = "RippleSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        check(settings.appearance == .auto && settings.colour == .mint, "fresh settings follow the system with Mint")
        check(settings.sliderEffect == .glowy, "new slider effects default to Glowy")
        settings.appearance = .light
        check(NSApp.appearance?.name == .aqua && !Palette.isDark, "Light forces a light app appearance")
        settings.appearance = .dark
        check(NSApp.appearance?.name == .darkAqua && Palette.isDark, "Dark forces a dark app appearance")
        settings.systemAppearanceChanged(NSAppearance(named: .aqua)!)
        check(Palette.isDark, "explicit Dark ignores system appearance changes")
        settings.appearance = .auto
        check(NSApp.appearance == nil, "Auto removes the app appearance override")
        settings.systemAppearanceChanged(NSAppearance(named: .darkAqua)!)
        check(Palette.isDark, "Auto responds to a Dark system appearance")
        settings.systemAppearanceChanged(NSAppearance(named: .aqua)!)
        check(!Palette.isDark, "Auto responds to a Light system appearance")
        settings.colour = .yellow
        settings.sliderEffect = .laser
        let restored = AppSettings(defaults: defaults, appliesToApplication: false)
        check(restored.appearance == .auto && restored.colour == .yellow, "remember mode and colour across launches")
        check(restored.sliderEffect == .laser && Palette.sliderEffect == .laser, "remember and apply the slider effect")
        defaults.set("unknown", forKey: "colourTheme")
        defaults.set("unknown", forKey: "appearanceMode")
        defaults.set("unknown", forKey: "sliderEffect")
        let recovered = AppSettings(defaults: defaults, appliesToApplication: false)
        check(recovered.appearance == .auto && recovered.colour == .mint, "recover from invalid saved settings")
        check(recovered.sliderEffect == .glowy, "recover from an invalid saved slider effect")

        for dark in [false, true] {
            Palette.isDark = dark
            for theme in ColourTheme.allCases {
                Palette.theme = theme
                check(contrast(Palette.accent, Palette.background) >= 4.5,
                      "\(theme.title) has readable accent text in \(dark ? "Dark" : "Light") mode")
            }
            check(contrast(Palette.secondary, Palette.background) >= 4.5, "secondary text is readable in \(dark ? "Dark" : "Light") mode")
        }

        let appURL = URL(fileURLWithPath: "/Applications/Ripple.app")
        let otherURL = URL(fileURLWithPath: "/Applications/Other Player.app")
        let fake = FakeApplicationWorkspace()
        let manager = FileAssociationManager(applicationURL: appURL, workspace: fake)
        let mp3 = AudioFileFormat.all[0]
        let wav = AudioFileFormat.all[1]
        fake.applications[mp3.id] = otherURL
        manager.refresh()
        check(!manager.isDefault(for: mp3) && manager.applicationName(for: mp3) == "Other Player", "read the current default player")
        await manager.makeDefault(for: [mp3, wav])
        check(manager.isDefault(for: mp3) && manager.isDefault(for: wav), "set selected formats through the workspace")
        check(manager.message.contains("MP3, WAV") && !manager.isBusy, "report verified success and finish the operation")
        let calls = fake.calls.count
        await manager.makeDefault(for: [mp3, wav])
        check(fake.calls.count == calls, "skip formats already assigned to Ripple")
        fake.applications = [:]
        fake.failures = [wav.id]
        manager.refresh()
        await manager.makeDefault(for: [mp3, wav])
        check(manager.isDefault(for: mp3) && !manager.isDefault(for: wav), "preserve individual results when macOS rejects a change")
        check(manager.message.contains("wasn’t changed for WAV") && !manager.isBusy, "report cancellation without claiming success")
        fake.failures = []
        fake.unapplied = [wav.id]
        await manager.makeDefault(for: [wav])
        check(manager.message.contains("wasn’t changed for WAV"), "verify the handler after a successful API response")
        fake.unapplied = []
        await manager.makeDefault(for: AudioFileFormat.all)
        check(AudioFileFormat.all.allSatisfy { manager.isDefault(for: $0) }, "make Ripple default for all six formats")
        let unbundled = FileAssociationManager(applicationURL: URL(fileURLWithPath: "/tmp/Ripple"), workspace: fake)
        let before = fake.calls.count
        await unbundled.makeDefault(for: [mp3])
        check(!unbundled.canSetDefaults && fake.calls.count == before, "avoid changing defaults from an unbundled executable")

        let declaredTypes = Set(AudioFileFormat.all.map(\.id))
        for extensionName in PlaybackController.supportedExtensions.sorted() {
            check(UTType(filenameExtension: extensionName).map { declaredTypes.contains($0.identifier) } ?? false,
                  "file association covers .\(extensionName)")
        }
        // Read-only integration with the real macOS default-app database.
        let system = FileAssociationManager()
        system.refresh()
        check(!system.isBusy, "read live macOS associations without changing them")
        print("\(checks) settings and association checks passed.")
    }

    static func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> Double {
                let x = Double(value)
                return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
