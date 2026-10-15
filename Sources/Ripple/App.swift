import AppKit

@main
@MainActor
struct RippleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let playback = PlaybackController()
    private var controller: PlayerWindowController?
    private var settingsController: SettingsWindowController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.apply()
        let controller = PlayerWindowController(playback: playback)
        self.controller = controller
        controller.window?.delegate = self
        controller.onOpenSettings = { [weak self] in self?.showSettings(nil) }
        createMenu(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !pendingURLs.isEmpty {
            playback.open(pendingURLs)
            pendingURLs = []
        } else {
            let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
            if !paths.isEmpty { playback.open(paths.map { URL(fileURLWithPath: $0) }) }
        }
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if let controller {
            playback.open(urls)
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else { pendingURLs.append(contentsOf: urls) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { playback.clear() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === controller?.window {
            playback.clear()
            settingsController?.close()
        }
    }

    private func createMenu(_ controller: PlayerWindowController) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Ripple", action: #selector(showAbout), keyEquivalent: "")
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ripple", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ripple", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addMenu(appMenu, title: "Ripple", to: menu)

        let file = NSMenu(title: "File")
        addItem("Open Audio…", action: #selector(controller.openAudio(_:)), key: "o", target: controller, to: file)
        addItem("Add to Queue…", action: #selector(controller.addAudio(_:)), key: "o", modifiers: [.command, .shift], target: controller, to: file)
        file.addItem(.separator())
        addItem("Reveal in Finder", action: #selector(controller.revealFile(_:)), key: "r", target: controller, to: file)
        addItem("Clear Queue", action: #selector(controller.clearQueue(_:)), key: "\u{8}", target: controller, to: file)
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addMenu(file, title: "File", to: menu)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addMenu(edit, title: "Edit", to: menu)

        let playbackMenu = NSMenu(title: "Playback")
        addItem("Play / Pause", action: #selector(controller.togglePlayback(_:)), key: "", target: controller, to: playbackMenu)
        addItem("Previous Track", action: #selector(controller.previous(_:)), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), target: controller, to: playbackMenu)
        addItem("Next Track", action: #selector(controller.next(_:)), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), target: controller, to: playbackMenu)
        playbackMenu.addItem(.separator())
        addItem("Toggle Repeat Track", action: #selector(controller.toggleRepeat(_:)), key: "l", target: controller, to: playbackMenu)
        addMenu(playbackMenu, title: "Playback", to: menu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        addMenu(windowMenu, title: "Window", to: menu)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    @objc private func showSettings(_ sender: Any?) {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addMenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
    private func addItem(_ title: String, action: Selector, key: String,
                         modifiers: NSEvent.ModifierFlags = .command, target: AnyObject, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Ripple",
            .applicationVersion: "1.2",
            .version: "3",
            .credits: NSAttributedString(string: "A little player for your local audio.\nBuilt with Swift, AppKit, and AVFoundation.\nNo accounts. No libraries to scan. Just sound.")
        ])
    }
}
