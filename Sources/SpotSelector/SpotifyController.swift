import AppKit
import QualityCore

enum SwitchError: LocalizedError {
    case quitTimedOut
    case spotifyNotInstalled
    case relaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .quitTimedOut:
            "Spotify didn't quit in time, so nothing was changed. Check Spotify for an open dialog and try again."
        case .spotifyNotInstalled:
            "The quality was changed, but Spotify couldn't be found to reopen it."
        case .relaunchFailed(let reason):
            "The quality was changed, but Spotify couldn't be reopened: \(reason)"
        }
    }
}

struct PlaybackSnapshot {
    var isPlaying: Bool
    var trackID: String
    var position: Double
}

/// Drives the Spotify desktop app: quit, edit prefs while it's closed,
/// relaunch, and put playback back where it was.
@MainActor
struct SpotifyController {
    nonisolated static let bundleID = "com.spotify.client"

    let store: PrefsStore

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
    }

    var isRunning: Bool { runningApp != nil }

    func switchQuality(
        to quality: Quality,
        resumePlayback: Bool,
        progress: (String) -> Void
    ) async throws {
        guard let app = runningApp else {
            try store.write(quality)
            return
        }

        let wasFrontmost = app.isActive
        var snapshot: PlaybackSnapshot?
        if resumePlayback, await Self.automationAllowed(for: app) {
            snapshot = playbackSnapshot()
        }

        progress("Quitting Spotify…")
        try await quit()

        progress("Saving quality…")
        var writeError: Error?
        do {
            try store.write(quality)
        } catch {
            writeError = error
        }

        // Reopen Spotify even if the write failed, so the user isn't left
        // without their music.
        progress("Reopening Spotify…")
        try await launch(activate: wasFrontmost)
        if let writeError { throw writeError }

        if let snapshot, snapshot.isPlaying {
            progress("Resuming playback…")
            await resume(snapshot)
        }
    }

    // MARK: - Quit / launch

    private func quit() async throws {
        let deadline = Date().addingTimeInterval(15)
        while let app = runningApp {
            if Date() > deadline { throw SwitchError.quitTimedOut }
            app.terminate()
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Spotify flushes prefs on exit; give the filesystem a beat.
        try? await Task.sleep(for: .milliseconds(400))
        if isRunning { throw SwitchError.quitTimedOut }
    }

    private func launch(activate: Bool) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw SwitchError.spotifyNotInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw SwitchError.relaunchFailed(error.localizedDescription)
        }
    }

    // MARK: - Playback

    /// Asks macOS whether this app may send Apple events to Spotify, showing
    /// the consent prompt the first time. Off the main thread because the
    /// prompt blocks until answered.
    private static func automationAllowed(for app: NSRunningApplication) async -> Bool {
        let pid = app.processIdentifier
        return await Task.detached {
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            return status == noErr
        }.value
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        // Addressing Spotify while it's closed would launch it.
        guard isRunning else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func playbackSnapshot() -> PlaybackSnapshot? {
        let result = run("""
        tell application id "\(Self.bundleID)"
            set theState to player state as string
            if theState is "stopped" then return {theState, "", 0}
            return {theState, id of current track, player position}
        end tell
        """)
        guard let result, result.numberOfItems == 3,
              let state = result.atIndex(1)?.stringValue,
              let trackID = result.atIndex(2)?.stringValue,
              let position = result.atIndex(3)?.doubleValue
        else { return nil }
        return PlaybackSnapshot(isPlaying: state == "playing", trackID: trackID, position: position)
    }

    private func resume(_ snapshot: PlaybackSnapshot) async {
        guard !snapshot.trackID.isEmpty else { return }

        // Spotify restores its last session (track, queue, context) a few
        // seconds after launch; wait for that so plain `play` keeps the queue.
        let deadline = Date().addingTimeInterval(25)
        var restored: PlaybackSnapshot?
        var firstResponse: Date?
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            guard let current = playbackSnapshot() else { continue }
            if firstResponse == nil { firstResponse = Date() }
            if current.trackID == snapshot.trackID {
                restored = current
                break
            }
            // Scriptable but showing something else: allow a short grace
            // period for session restore, then fall back.
            if let firstResponse, Date().timeIntervalSince(firstResponse) > 6 { break }
        }
        guard firstResponse != nil else { return }

        let position = max(0, snapshot.position - 1)
        if restored != nil {
            _ = run("""
            tell application id "\(Self.bundleID)"
                set player position to \(Self.scriptNumber(position))
                play
            end tell
            """)
        } else {
            _ = run("""
            tell application id "\(Self.bundleID)" to play track "\(snapshot.trackID)"
            """)
        }

        try? await Task.sleep(for: .milliseconds(900))
        if let now = playbackSnapshot(), now.trackID == snapshot.trackID, abs(now.position - position) > 4 {
            _ = run("""
            tell application id "\(Self.bundleID)" to set player position to \(Self.scriptNumber(position))
            """)
        }
    }

    private static func scriptNumber(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
