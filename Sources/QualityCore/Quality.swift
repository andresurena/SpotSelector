import Foundation

/// Streaming quality levels, with raw values matching the enumeration Spotify
/// stores in its prefs file (verified against Spotify 1.3.0).
public enum Quality: Int, CaseIterable, Identifiable, Sendable {
    case automatic = 0
    case low = 1
    case normal = 2
    case high = 3
    case veryHigh = 4
    case lossless = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .veryHigh: "Very High"
        case .lossless: "Lossless"
        }
    }

    public var detail: String {
        switch self {
        case .automatic: "Adjusts to your connection"
        case .low: "24 kbps"
        case .normal: "96 kbps"
        case .high: "160 kbps"
        case .veryHigh: "320 kbps"
        case .lossless: "FLAC, up to 24-bit/44.1 kHz"
        }
    }

    /// Compact label for the menu bar.
    public var shortLabel: String {
        switch self {
        case .automatic: "Auto"
        case .low: "24"
        case .normal: "96"
        case .high: "160"
        case .veryHigh: "320"
        case .lossless: "FLAC"
        }
    }
}
