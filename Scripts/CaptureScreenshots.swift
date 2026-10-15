import AppKit
import AVFoundation

/// Exports the real AppKit views with generated, silent demo files.
/// Windows stay offscreen, and all preferences use a disposable suite.
@main
@MainActor
struct CaptureScreenshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let scratch = URL(fileURLWithPath: CommandLine.arguments[2])
            .appendingPathComponent("screenshots-\(UUID().uuidString)")
        let audio = scratch.appendingPathComponent("Audio")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "RippleScreenshots-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "appearanceMode")
        defaults.set("mint", forKey: "colourTheme")
        defaults.set("glowy", forKey: "sliderEffect")
        defaults.set(0.68, forKey: "volume")
        let settings = AppSettings(defaults: defaults)
        settings.apply()

        let names = ["Midnight Circuit", "Daybreak", "Soft Landing"]
        let urls = names.map { audio.appendingPathComponent($0).appendingPathExtension("wav") }
        for url in urls { try writeSilentWave(to: url, seconds: 222) }
        let playback = PlaybackController(defaults: defaults)
        let player = PlayerWindowController(playback: playback)
        playback.open(urls, autoplay: false)
        playback.seek(to: 87)
        try snapshot(player.window!, to: output.appendingPathComponent("player-dark.png"))

        let preferences = SettingsWindowController(settings: settings)
        try snapshot(preferences.window!, to: output.appendingPathComponent("settings.png"))

        settings.appearance = .light
        settings.colour = .blue
        settings.sliderEffect = .neon
        try snapshot(player.window!, to: output.appendingPathComponent("player-light.png"))
        playback.clear()
        print("Screenshots saved to \(output.path)")
    }

    static func snapshot(_ window: NSWindow, to url: URL) throws {
        let frame = window.contentView!.superview ?? window.contentView!
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    static func writeSilentWave(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: 4096) }
        var remaining = Int(seconds * 44_100)
        while remaining > 0 {
            buffer.frameLength = AVAudioFrameCount(min(4096, remaining))
            try file.write(from: buffer)
            remaining -= Int(buffer.frameLength)
        }
    }
}
