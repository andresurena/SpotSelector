import AppKit
import QualityCore

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let command = arguments.first, command.hasPrefix("--") {
            CommandLineMode.run(command: command, arguments: Array(arguments.dropFirst()))
        } else {
            SpotSelectorApp.main()
        }
    }
}

/// Headless use, e.g. from scripts or Shortcuts:
///   SpotSelector --get
///   SpotSelector --set lossless [--no-resume]
///   SpotSelector --automation-status
enum CommandLineMode {
    static func run(command: String, arguments: [String]) -> Never {
        switch command {
        case "--get":
            do {
                print(name(of: try PrefsStore.standard.currentQuality()))
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        case "--set":
            guard let raw = arguments.first, let quality = quality(named: raw) else {
                fail("Usage: SpotSelector --set <\(Quality.allCases.map(name(of:)).joined(separator: "|"))> [--no-resume]")
            }
            let resume = !arguments.contains("--no-resume")
            Task { @MainActor in
                do {
                    try await SpotifyController(store: .standard)
                        .switchQuality(to: quality, resumePlayback: resume) { print($0) }
                    print("Spotify quality is now \(quality.title).")
                    exit(0)
                } catch {
                    fail(error.localizedDescription)
                }
            }
            RunLoop.main.run()
            exit(0)
        case "--automation-status":
            // Whether macOS lets this app control Spotify (needed to resume
            // playback). Never shows the consent prompt.
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: SpotifyController.bundleID).first else {
                fail("Spotify isn't running; open it and try again.")
            }
            switch SpotifyController.automationStatus(pid: app.processIdentifier, askIfNeeded: false) {
            case .allowed: print("allowed")
            case .notAsked: print("not-asked")
            case .denied: print("denied")
            case .unknown(let code): print("unknown (\(code))")
            }
            exit(0)
        default:
            fail("Usage: SpotSelector [--get | --set <quality> [--no-resume] | --automation-status]")
        }
    }

    private static func name(of quality: Quality) -> String {
        quality.title.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func quality(named raw: String) -> Quality? {
        Quality.allCases.first { name(of: $0) == raw.lowercased() }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
