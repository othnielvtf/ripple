import AppKit
import AVFoundation

struct AudioTrack: Equatable {
    let url: URL
    var title: String { url.deletingPathExtension().lastPathComponent }
    var format: String { url.pathExtension.uppercased() }
}

@MainActor
final class PlaybackController: NSObject, AVAudioPlayerDelegate {
    static let supportedExtensions: Set<String> = ["mp3", "wav", "wave", "m4a", "aac", "aif", "aiff", "caf"]

    private(set) var queue: [AudioTrack] = []
    private(set) var currentIndex: Int?
    private(set) var player: AVAudioPlayer?
    private var timer: Timer?
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    var onProgress: (() -> Void)?
    var onError: ((String) -> Void)?

    var currentTrack: AudioTrack? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }
    var isPlaying: Bool { player?.isPlaying ?? false }
    var duration: TimeInterval { player?.duration ?? 0 }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var audioDetails: String {
        guard let player else { return "MP3, WAV, M4A & AIFF" }
        let rate = player.settings[AVSampleRateKey] as? Double ?? 0
        let rateText = rate > 0 ? String(format: "%.1f kHz", rate / 1_000) : ""
        let channels = player.numberOfChannels == 1 ? "Mono" : "Stereo"
        return [currentTrack?.format ?? "", rateText, channels].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    var volume: Float {
        didSet {
            player?.volume = volume
            defaults.set(volume, forKey: "volume")
            onChange?()
        }
    }
    var repeatOne: Bool {
        didSet {
            player?.numberOfLoops = repeatOne ? -1 : 0
            defaults.set(repeatOne, forKey: "repeatOne")
            onChange?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volume = defaults.object(forKey: "volume") == nil ? 0.8 : min(1, max(0, defaults.float(forKey: "volume")))
        repeatOne = defaults.bool(forKey: "repeatOne")
        super.init()
    }

    /// Files are kept in the order supplied by Finder or the open panel.
    func open(_ urls: [URL], append: Bool = false, autoplay: Bool = true) {
        let supported = urls.filter { $0.isFileURL && Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        guard !supported.isEmpty else {
            onError?("Choose an MP3, WAV, M4A, AAC, AIFF, or CAF audio file.")
            return
        }
        let newTracks = supported.map { AudioTrack(url: $0.standardizedFileURL) }
        if append && !queue.isEmpty {
            let firstAdded = queue.count
            queue.append(contentsOf: newTracks)
            if player == nil { loadFirstPlayable(in: Array(firstAdded..<queue.count), autoplay: autoplay) }
            else { onChange?() }
            return
        }
        stopTimer()
        player?.stop()
        player = nil
        currentIndex = nil
        queue = newTracks
        loadFirstPlayable(in: Array(queue.indices), autoplay: autoplay)
    }

    @discardableResult
    func select(_ index: Int, autoplay: Bool = true, reportError: Bool = true) -> Bool {
        guard queue.indices.contains(index) else { return false }
        do {
            let next = try AVAudioPlayer(contentsOf: queue[index].url)
            next.delegate = self
            next.volume = volume
            next.numberOfLoops = repeatOne ? -1 : 0
            guard next.prepareToPlay() else { throw PlaybackError.cannotPrepare }
            if autoplay && !next.play() { throw PlaybackError.cannotPlay }
            player?.stop()
            stopTimer()
            player = next
            currentIndex = index
            if autoplay { startTimer() }
            onChange?()
            onProgress?()
            return true
        } catch {
            if reportError {
                onError?("Couldn’t play “\(queue[index].url.lastPathComponent)”. The file may be missing, damaged, or use an unsupported audio encoding.")
            }
            return false
        }
    }

    func togglePlayback() {
        guard let player else {
            if !queue.isEmpty { loadFirstPlayable(in: Array(queue.indices), autoplay: true) }
            return
        }
        if player.isPlaying {
            player.pause()
            stopTimer()
        } else {
            if player.currentTime >= player.duration - 0.02 { player.currentTime = 0 }
            guard player.play() else {
                onError?("Playback couldn’t start. Check your audio output and try again.")
                return
            }
            startTimer()
        }
        onChange?()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), max(0, player.duration - 0.01))
        onProgress?()
    }

    func skip(by seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func previous() {
        guard let index = currentIndex else { return }
        if currentTime > 3 || index == 0 { seek(to: 0); return }
        loadFirstPlayable(in: Array((0..<index).reversed()), autoplay: isPlaying)
    }

    func next() {
        guard let index = currentIndex, index + 1 < queue.count else { return }
        loadFirstPlayable(in: Array((index + 1)..<queue.count), autoplay: isPlaying)
    }

    func clear() {
        stopTimer()
        player?.stop()
        player = nil
        currentIndex = nil
        queue = []
        onChange?()
        onProgress?()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopTimer()
        if let index = currentIndex, index + 1 < queue.count {
            loadFirstPlayable(in: Array((index + 1)..<queue.count), autoplay: true)
        } else {
            player.currentTime = 0
            onChange?()
            onProgress?()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        player.stop()
        stopTimer()
        onChange?()
        onError?("The audio file couldn’t be decoded. Try another file.")
    }

    private func loadFirstPlayable(in indices: [Int], autoplay: Bool) {
        for index in indices where select(index, autoplay: autoplay, reportError: false) { return }
        onChange?()
        onProgress?()
        onError?("None of these files could be played. Check that they exist and contain valid audio.")
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onProgress?() }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private enum PlaybackError: Error { case cannotPrepare, cannotPlay }
}
