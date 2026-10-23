import AppKit
import QualityCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var current: Quality?
    @Published private(set) var status: String?
    @Published private(set) var problem: String?
    @Published private(set) var launchAtLogin = false

    @Published var hidden: Set<Quality> {
        didSet { defaults.set(hidden.map(\.rawValue).sorted(), forKey: Keys.hidden) }
    }
    @Published var resumePlayback: Bool {
        didSet { defaults.set(resumePlayback, forKey: Keys.resumePlayback) }
    }
    @Published var showLabel: Bool {
        didSet { defaults.set(showLabel, forKey: Keys.showLabel) }
    }

    var isSwitching: Bool { status != nil }

    /// Qualities offered in the menu; the active one is always included.
    var menuQualities: [Quality] {
        Quality.allCases.reversed().filter { !hidden.contains($0) || $0 == current }
    }

    private enum Keys {
        static let hidden = "hiddenQualities"
        static let resumePlayback = "resumePlayback"
        static let showLabel = "showLabel"
        static let loginItemConfigured = "loginItemConfigured"
    }

    private let defaults = UserDefaults.standard
    private let store = PrefsStore.standard
    private var controller: SpotifyController { SpotifyController(store: store) }
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var observers: [NSObjectProtocol] = []

    init() {
        defaults.register(defaults: [Keys.resumePlayback: true, Keys.showLabel: true])
        let raw = defaults.array(forKey: Keys.hidden) as? [Int] ?? []
        hidden = Set(raw.compactMap(Quality.init(rawValue:)))
        resumePlayback = defaults.bool(forKey: Keys.resumePlayback)
        showLabel = defaults.bool(forKey: Keys.showLabel)
        registerLoginItemOnFirstRun()
        launchAtLogin = SMAppService.mainApp.status == .enabled

        refresh()

        // Spotify rewrites prefs when settings change in its own UI and on
        // quit; pick those up so the checkmark stays truthful.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == SpotifyController.bundleID else { return }
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    func refresh() {
        guard !isSwitching else { return }
        do {
            current = try store.currentQuality()
            problem = nil
        } catch {
            current = nil
            problem = error.localizedDescription
        }
        watchPrefsDirectory()
    }

    func select(_ quality: Quality) {
        guard !isSwitching, quality != current else { return }
        status = "Switching to \(quality.title)…"
        Task {
            do {
                try await controller.switchQuality(to: quality, resumePlayback: resumePlayback) { [weak self] step in
                    self?.status = step
                }
                status = nil
                refresh()
            } catch {
                status = nil
                refresh()
                present(error)
            }
        }
    }

    func setHidden(_ quality: Quality, _ isHidden: Bool) {
        if isHidden { hidden.insert(quality) } else { hidden.remove(quality) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            present(error)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Opt in to launch at login once, on the first run from /Applications.
    /// Registering from a build folder would point the login item at a copy
    /// that gets deleted on the next build. The user can turn it off in Options.
    private func registerLoginItemOnFirstRun() {
        guard !defaults.bool(forKey: Keys.loginItemConfigured) else { return }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: Keys.loginItemConfigured)
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't switch Spotify quality"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func watchPrefsDirectory() {
        guard let directory = try? store.userPrefsURL().deletingLastPathComponent() else { return }
        guard directory.path != watchedPath else { return }
        watcher?.cancel()
        watcher = nil
        watchedPath = nil

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
        watchedPath = directory.path
    }
}
