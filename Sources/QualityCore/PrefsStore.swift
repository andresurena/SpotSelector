import Foundation

public enum PrefsError: LocalizedError, Equatable {
    case spotifyDataNotFound
    case unreadable(String)
    case unrecognisedValue
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .spotifyDataNotFound:
            "Couldn't find Spotify's settings file. Open Spotify and log in once, then try again."
        case .unreadable(let reason):
            "Couldn't read Spotify's settings file: \(reason)"
        case .unrecognisedValue:
            "Spotify's settings file has a quality value this app doesn't recognise. Spotify may have changed its format."
        case .verificationFailed:
            "The new quality didn't save correctly. Spotify's settings were restored from backup."
        }
    }
}

/// Locates, reads and safely rewrites the logged-in user's Spotify prefs file.
public struct PrefsStore: Sendable {
    public let spotifyDirectory: URL
    public let backupDirectory: URL

    public init(spotifyDirectory: URL, backupDirectory: URL) {
        self.spotifyDirectory = spotifyDirectory
        self.backupDirectory = backupDirectory
    }

    public static var standard: PrefsStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PrefsStore(
            spotifyDirectory: appSupport.appendingPathComponent("Spotify"),
            backupDirectory: appSupport.appendingPathComponent("SpotSelector/Backups")
        )
    }

    public var usersDirectory: URL {
        spotifyDirectory.appendingPathComponent("Users")
    }

    /// The prefs file of the account Spotify auto-logs into, falling back to
    /// the most recently modified user folder.
    public func userPrefsURL() throws -> URL {
        let fm = FileManager.default

        let globalPrefs = spotifyDirectory.appendingPathComponent("prefs")
        if let text = try? String(contentsOf: globalPrefs, encoding: .utf8),
           let raw = PrefsDocument(text: text).value(forKey: "autologin.canonical_username") {
            let username = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let candidate = usersDirectory.appendingPathComponent("\(username)-user/prefs")
            if !username.isEmpty, fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let folders = (try? fm.contentsOfDirectory(
            at: usersDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let candidates = folders
            .map { $0.appendingPathComponent("prefs") }
            .filter { fm.fileExists(atPath: $0.path) }
            .map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (url, date ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
        guard let newest = candidates.first else { throw PrefsError.spotifyDataNotFound }
        return newest.0
    }

    public func load() throws -> PrefsDocument {
        try load(from: userPrefsURL())
    }

    private func load(from url: URL) throws -> PrefsDocument {
        do {
            return PrefsDocument(text: try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw PrefsError.unreadable(error.localizedDescription)
        }
    }

    public func currentQuality() throws -> Quality {
        guard let quality = try load().quality else { throw PrefsError.unrecognisedValue }
        return quality
    }

    /// Backs up the prefs file, rewrites only the quality keys, and re-reads
    /// to confirm. Callers must make sure Spotify is not running: it
    /// overwrites this file when it quits.
    public func write(_ quality: Quality) throws {
        let fm = FileManager.default
        let url = try userPrefsURL()
        var document = try load(from: url)
        guard document.quality != nil else { throw PrefsError.unrecognisedValue }

        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backup = backupDirectory.appendingPathComponent("prefs.backup")
        try? fm.removeItem(at: backup)
        try fm.copyItem(at: url, to: backup)

        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]

        document.setQuality(quality)
        try Data(document.text.utf8).write(to: url, options: .atomic)
        if let permissions {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }

        let saved = try? load(from: url)
        if saved != document {
            try? fm.removeItem(at: url)
            try? fm.copyItem(at: backup, to: url)
            throw PrefsError.verificationFailed
        }
    }
}
