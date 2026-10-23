import XCTest
@testable import QualityCore

final class PrefsDocumentTests: XCTestCase {
    func testReadsQualityFromNonMeteredKey() {
        let doc = PrefsDocument(text: """
        audio.play_bitrate_non_metered_migrated=true
        audio.play_bitrate_non_metered_enumeration=5
        audio.play_bitrate_enumeration=4

        """)
        XCTAssertEqual(doc.quality, .lossless)
    }

    func testFallsBackToLegacyKey() {
        let doc = PrefsDocument(text: "audio.play_bitrate_enumeration=3\n")
        XCTAssertEqual(doc.quality, .high)
    }

    func testMissingKeysMeanAutomatic() {
        XCTAssertEqual(PrefsDocument(text: "app.something=1\n").quality, .automatic)
    }

    func testUnknownValueIsNil() {
        XCTAssertNil(PrefsDocument(text: "audio.play_bitrate_non_metered_enumeration=9\n").quality)
        XCTAssertNil(PrefsDocument(text: "audio.play_bitrate_non_metered_enumeration=abc\n").quality)
    }

    func testSetQualityOnlyTouchesQualityLines() {
        let original = """
        audio.play_bitrate_non_metered_migrated=true
        connect.mdns_devices="[{\\"a\\":\\"b=c\\"}]"
        audio.play_bitrate_non_metered_enumeration=5
        ui.other="audio.play_bitrate_enumeration=1"
        audio.play_bitrate_enumeration=5

        """
        var doc = PrefsDocument(text: original)
        doc.setQuality(.veryHigh)
        XCTAssertEqual(doc.text, original.replacingOccurrences(of: "enumeration=5", with: "enumeration=4"))
    }

    func testSetQualityAddsMissingKeysBeforeTrailingNewline() {
        var doc = PrefsDocument(text: "app.x=1\n")
        doc.setQuality(.lossless)
        XCTAssertEqual(doc.text, """
        app.x=1
        audio.play_bitrate_enumeration=5
        audio.play_bitrate_non_metered_enumeration=5
        audio.play_bitrate_non_metered_migrated=true

        """)
        XCTAssertEqual(doc.quality, .lossless)
    }

    func testRoundTripIsByteIdentical() {
        for text in ["a=1\nb=2\n", "a=1\nb=2", "", "\n\n", "a=x=y\n"] {
            XCTAssertEqual(PrefsDocument(text: text).text, text)
        }
    }
}

final class PrefsStoreTests: XCTestCase {
    private var root: URL!
    private var store: PrefsStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = PrefsStore(
            spotifyDirectory: root.appendingPathComponent("Spotify"),
            backupDirectory: root.appendingPathComponent("Backups")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeUser(_ name: String, prefs: String) throws -> URL {
        let dir = store.usersDirectory.appendingPathComponent("\(name)-user")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("prefs")
        try prefs.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testThrowsWhenSpotifyDataMissing() {
        XCTAssertThrowsError(try store.currentQuality()) {
            XCTAssertEqual($0 as? PrefsError, .spotifyDataNotFound)
        }
    }

    func testPrefersAutologinUser() throws {
        _ = try makeUser("alice", prefs: "audio.play_bitrate_non_metered_enumeration=2\n")
        _ = try makeUser("bob", prefs: "audio.play_bitrate_non_metered_enumeration=4\n")
        try "autologin.canonical_username=\"alice\"\n".write(
            to: store.spotifyDirectory.appendingPathComponent("prefs"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.userPrefsURL().deletingLastPathComponent().lastPathComponent, "alice-user")
        XCTAssertEqual(try store.currentQuality(), .normal)
    }

    func testWriteUpdatesFileAndKeepsBackup() throws {
        let original = "x=1\naudio.play_bitrate_non_metered_enumeration=5\naudio.play_bitrate_enumeration=5\n"
        let url = try makeUser("alice", prefs: original)
        try store.write(.high)
        XCTAssertEqual(try store.currentQuality(), .high)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("x=1\naudio.play_bitrate_non_metered_enumeration=3\naudio.play_bitrate_enumeration=3\n"))
        let backup = try String(
            contentsOf: store.backupDirectory.appendingPathComponent("prefs.backup"), encoding: .utf8)
        XCTAssertEqual(backup, original)
    }

    func testWriteRefusesUnrecognisedFile() throws {
        let original = "audio.play_bitrate_non_metered_enumeration=42\n"
        let url = try makeUser("alice", prefs: original)
        XCTAssertThrowsError(try store.write(.high))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }
}
