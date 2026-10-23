import Foundation

/// Spotify's `prefs` file: one `key=value` per line. Edits touch only the
/// targeted lines so everything else round-trips byte-for-byte.
public struct PrefsDocument: Equatable, Sendable {
    public static let streamingKey = "audio.play_bitrate_enumeration"
    public static let streamingNonMeteredKey = "audio.play_bitrate_non_metered_enumeration"
    public static let nonMeteredMigratedKey = "audio.play_bitrate_non_metered_migrated"

    private var lines: [String]

    public init(text: String) {
        lines = text.components(separatedBy: "\n")
    }

    public var text: String {
        lines.joined(separator: "\n")
    }

    public func value(forKey key: String) -> String? {
        let prefix = key + "="
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    public mutating func setValue(_ value: String, forKey key: String) {
        let prefix = key + "="
        let newLine = prefix + value
        if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            lines[index] = newLine
        } else if lines.last == "" {
            lines.insert(newLine, at: lines.count - 1)
        } else {
            lines.append(newLine)
        }
    }

    /// The streaming quality Spotify will use. Missing keys mean the setting
    /// was never changed from its default, which is Automatic.
    public var quality: Quality? {
        let raw = value(forKey: Self.streamingNonMeteredKey) ?? value(forKey: Self.streamingKey)
        guard let raw else { return .automatic }
        guard let number = Int(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Quality(rawValue: number)
    }

    public mutating func setQuality(_ quality: Quality) {
        let raw = String(quality.rawValue)
        setValue(raw, forKey: Self.streamingKey)
        setValue(raw, forKey: Self.streamingNonMeteredKey)
        // Without this flag Spotify re-derives the non-metered value from the
        // legacy key on launch.
        setValue("true", forKey: Self.nonMeteredMigratedKey)
    }
}
