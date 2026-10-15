import AppKit
import UniformTypeIdentifiers

struct AudioFileFormat {
    let title: String
    let extensions: String
    let type: UTType
    var id: String { type.identifier }

    static let all: [AudioFileFormat] = [
        AudioFileFormat(title: "MP3", extensions: ".mp3", type: UTType("public.mp3")!),
        AudioFileFormat(title: "WAV", extensions: ".wav, .wave", type: UTType("com.microsoft.waveform-audio")!),
        AudioFileFormat(title: "M4A", extensions: ".m4a", type: UTType("com.apple.m4a-audio")!),
        AudioFileFormat(title: "AAC", extensions: ".aac", type: UTType("public.aac-audio")!),
        AudioFileFormat(title: "AIFF", extensions: ".aif, .aiff", type: UTType("public.aiff-audio")!),
        AudioFileFormat(title: "CAF", extensions: ".caf", type: UTType("com.apple.coreaudio-format")!)
    ]
}

@MainActor
protocol DefaultApplicationWorkspace {
    func defaultApplication(for type: UTType) -> URL?
    func setDefaultApplication(at url: URL, for type: UTType) async throws
}

@MainActor
struct SystemApplicationWorkspace: DefaultApplicationWorkspace {
    func defaultApplication(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }
    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
    }
}

@MainActor
final class FileAssociationManager {
    let applicationURL: URL
    private let workspace: DefaultApplicationWorkspace
    private(set) var applications: [String: URL] = [:]
    private(set) var isBusy = false
    private(set) var pendingID: String?
    private(set) var message = ""
    var onChange: (() -> Void)?
    var canSetDefaults: Bool { applicationURL.pathExtension == "app" }

    init(applicationURL: URL = Bundle.main.bundleURL,
         workspace: DefaultApplicationWorkspace? = nil) {
        self.applicationURL = applicationURL
        self.workspace = workspace ?? SystemApplicationWorkspace()
        refresh()
    }

    func refresh() {
        applications = [:]
        for format in AudioFileFormat.all { applications[format.id] = workspace.defaultApplication(for: format.type) }
        onChange?()
    }

    func isDefault(for format: AudioFileFormat) -> Bool {
        guard let current = applications[format.id] else { return false }
        return current.resolvingSymlinksInPath().standardizedFileURL == applicationURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func applicationName(for format: AudioFileFormat) -> String {
        guard let url = applications[format.id] else { return "No default app" }
        return (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// macOS owns consent prompts. Never report success without checking the resulting handler.
    func makeDefault(for formats: [AudioFileFormat]) async {
        guard !isBusy, !formats.isEmpty else { return }
        guard canSetDefaults else {
            message = "Open Ripple.app to change default audio apps."
            onChange?()
            return
        }
        isBusy = true
        message = "Confirm any default-app prompts from macOS."
        var changed: [String] = []
        var failures: [String] = []
        refresh()
        for format in formats where !isDefault(for: format) {
            pendingID = format.id
            onChange?()
            do {
                try await workspace.setDefaultApplication(at: applicationURL, for: format.type)
                refresh()
                if isDefault(for: format) { changed.append(format.title) }
                else { failures.append(format.title) }
            } catch {
                failures.append(format.title)
            }
        }
        isBusy = false
        pendingID = nil
        refresh()
        if !failures.isEmpty {
            message = "Default app wasn’t changed for \(failures.joined(separator: ", ")). You can try again or use Finder → Get Info → Open with → Change All."
        } else if changed.isEmpty {
            message = "Ripple is already the default for these formats."
        } else {
            message = "Ripple is now the default for \(changed.joined(separator: ", "))."
        }
        onChange?()
    }
}
