import Foundation

/// Values read back from Spotify (track IDs) end up inside AppleScript
/// source. Local-file IDs are built from file tags, so treat them as
/// untrusted: validate the shape, and escape before embedding.
public enum AppleScriptLiteral {
    /// A double-quoted AppleScript string literal for `value`.
    public static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public enum SpotifyURI {
    /// True for identifiers shaped like Spotify URIs: `spotify:` followed by
    /// printable ASCII with no quotes, backslashes, spaces or control
    /// characters (Spotify percent-encodes everything else).
    public static func isValid(_ value: String) -> Bool {
        guard value.hasPrefix("spotify:"), value.utf8.count <= 1024 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (0x21...0x7E).contains(scalar.value) && scalar != "\"" && scalar != "\\"
        }
    }
}
