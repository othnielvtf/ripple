import AppKit
import AVFoundation

@main
@MainActor
struct PlaybackTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("FAIL: \(message)") }
            checks += 1
            print("PASS: \(message)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ripple-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("First.wav")
        let second = directory.appendingPathComponent("Second.WAV")
        let broken = directory.appendingPathComponent("Broken.mp3")
        let unsupported = directory.appendingPathComponent("Text.txt")
        try makeWave(first, duration: 6)
        try makeWave(second, duration: 1)
        try Data("not audio".utf8).write(to: broken)
        let suite = "RippleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlaybackController(defaults: defaults)
        var errors: [String] = []
        model.onError = { errors.append($0) }
        model.volume = 0 // Exercise the output device silently.

        model.open([first], autoplay: false)
        check(model.currentTrack?.url == first, "load a WAV file")
        check(abs(model.duration - 6) < 0.02, "read WAV duration")
        check(!model.isPlaying, "load without autoplay")
        model.togglePlayback()
        check(model.isPlaying, "start playback on the audio output")
        model.togglePlayback()
        check(!model.isPlaying, "pause playback")
        model.seek(to: 2)
        check(abs(model.currentTime - 2) < 0.02, "seek to a position")
        model.skip(by: -5)
        check(model.currentTime == 0, "clamp backward seek to zero")
        model.seek(to: 999)
        check(model.currentTime < model.duration && model.currentTime > 5, "clamp seek to the end")
        model.open([second], append: true, autoplay: false)
        check(model.queue.count == 2 && model.currentIndex == 0, "append without interrupting the current file")
        model.next()
        check(model.currentIndex == 1 && !model.isPlaying, "next track preserves paused state")
        model.previous()
        check(model.currentIndex == 0, "previous track")
        model.seek(to: 4)
        model.previous()
        check(model.currentTime < 0.02, "previous restarts a track after three seconds")
        model.repeatOne = true
        check(model.player?.numberOfLoops == -1, "enable repeat one")
        model.repeatOne = false
        check(model.player?.numberOfLoops == 0, "disable repeat one")
        model.volume = 0.3
        check(model.player?.volume == 0.3, "apply volume")
        check(PlaybackController(defaults: defaults).volume == 0.3, "remember volume between launches")
        model.volume = 0
        model.open([unsupported], autoplay: false)
        check(model.queue.count == 2 && !errors.isEmpty, "reject unsupported files without losing the queue")
        errors = []
        check(!model.select(999), "ignore an invalid queue index")
        model.open([broken, first], autoplay: false)
        check(model.currentIndex == 1 && errors.isEmpty, "skip a damaged first file")
        model.open([broken], autoplay: false)
        check(model.player == nil && errors.count == 1, "report an entirely unplayable queue")
        model.open([second], append: true, autoplay: false)
        check(model.currentIndex == 1 && model.player != nil, "recover by appending a valid file")
        model.open([first, second], autoplay: false)
        model.audioPlayerDidFinishPlaying(model.player!, successfully: true)
        check(model.currentIndex == 1 && model.isPlaying, "advance automatically at end of track")
        model.togglePlayback()
        model.audioPlayerDidFinishPlaying(model.player!, successfully: true)
        check(!model.isPlaying && model.currentTime == 0, "reset after the final track")

        // This case runs the actual decoder and delegate completion through the main run loop.
        model.open([second, first], autoplay: true)
        let deadline = Date().addingTimeInterval(4)
        while model.currentIndex == 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        check(model.currentIndex == 1 && model.isPlaying, "real audio completion advances the queue")
        model.clear()
        check(model.queue.isEmpty && model.player == nil && !model.isPlaying, "clear stops playback and releases the file")

        if let path = CommandLine.arguments.dropFirst().first {
            let mp3 = URL(fileURLWithPath: path)
            model.open([mp3], autoplay: true)
            check(model.isPlaying && model.duration > 0, "decode and play an MP3 file")
            model.togglePlayback()
            model.seek(to: model.duration / 2)
            check(abs(model.currentTime - model.duration / 2) < 0.1, "seek in an MP3 file")
            model.clear()
        }
        print("\(checks) checks passed.")
    }

    static func makeWave(_ url: URL, duration: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frames = AVAudioFrameCount(duration * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: Int(frames)) }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}
