import Foundation
class XCTestCase {}
var failureCount = 0
func XCTFail(_ message: String = "Failure", file: StaticString = #filePath, line: UInt = #line) { failureCount += 1; print("FAIL \(file):\(line): \(message)") }
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { if !value() { XCTFail("Expected true", file: file, line: line) } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { if value() { XCTFail("Expected false", file: file, line: line) } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { let av = a(), bv = b(); if av != bv { XCTFail("\(av) != \(bv)", file: file, line: line) } }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { XCTFail("Expected nil", file: file, line: line) } }
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value == nil { XCTFail("Expected non-nil", file: file, line: line) } }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "Check", code: 1) }; return value }
import Foundation
import MurmurCore

final class ShortcutTests: XCTestCase {
    func testHold() { var s = ShortcutGesture(); XCTAssertEqual(s.down(at: 0), [.start]); XCTAssertEqual(s.up(at: 1), [.stop]) }
    func testSingleTapIsDiscarded() { var s = ShortcutGesture(); _ = s.down(at: 0); XCTAssertEqual(s.up(at: 0.1), [.scheduleStop]); XCTAssertEqual(s.expireTap(), [.cancel]); XCTAssertEqual(s.expireTap(), []) }
    func testQuickTripleTapCancels() { var s = ShortcutGesture(); _ = s.down(at: 0); _ = s.up(at: 0.1); XCTAssertEqual(s.down(at: 0.25), [.cancelScheduledStop]); _ = s.up(at: 0.3); XCTAssertEqual(s.down(at: 0.5), [.cancel]) }
    func testFnSpaceLocksHandsFree() { var s = ShortcutGesture(); XCTAssertEqual(s.down(at: 0), [.start]); XCTAssertEqual(s.lockHandsFree(at: 0.4), [.cancelScheduledStop]); XCTAssertEqual(s.up(at: 0.6), []); XCTAssertEqual(s.down(at: 3), [.stop]); XCTAssertEqual(s.up(at: 3.1), []); XCTAssertFalse(s.handsFree) }
    func testFnSpaceIgnoredWhenNotHolding() { var s = ShortcutGesture(); XCTAssertEqual(s.lockHandsFree(at: 0), []) }
    func testDoubleTapHandsFree() { var s = ShortcutGesture(); _ = s.down(at: 0); _ = s.up(at: 0.1); XCTAssertEqual(s.down(at: 0.25), [.cancelScheduledStop]); XCTAssertTrue(s.handsFree); XCTAssertEqual(s.up(at: 0.3), []); XCTAssertEqual(s.expireTap(), []); XCTAssertEqual(s.down(at: 1), [.stop]); XCTAssertEqual(s.up(at: 1.1), []); XCTAssertFalse(s.handsFree) }
    func testAutoRepeatIgnored() { var s = ShortcutGesture(); _ = s.down(at: 0); XCTAssertEqual(s.down(at: 0.1), []); XCTAssertEqual(s.up(at: 1), [.stop]); XCTAssertEqual(s.up(at: 2), []) }
    func testResetDuringHold() { var s = ShortcutGesture(); _ = s.down(at: 0); s.reset(); XCTAssertEqual(s.up(at: 1), []); XCTAssertEqual(s.down(at: 2), [.start]) }
    func testResetPendingTap() { var s = ShortcutGesture(); _ = s.down(at: 0); _ = s.up(at: 0.1); s.reset(); XCTAssertEqual(s.expireTap(), []) }
}
final class StateTests: XCTestCase {
    func testFullLifecycle() throws { var s = SessionGate(); let token = try XCTUnwrap(s.begin()); XCTAssertTrue(s.transition(.recording, token: token)); XCTAssertTrue(s.transition(.processing, token: token)); XCTAssertTrue(s.transition(.success, token: token)); XCTAssertNotNil(s.begin()) }
    func testDuplicateStartRejected() { var s = SessionGate(); _ = s.begin(); XCTAssertNil(s.begin()) }
    func testDuplicateCompletionRejected() throws { var s = SessionGate(); let token = try XCTUnwrap(s.begin()); _ = s.transition(.recording, token: token); _ = s.transition(.processing, token: token); XCTAssertTrue(s.transition(.success, token: token)); XCTAssertFalse(s.transition(.success, token: token)) }
    func testCancelInvalidatesResponses() throws { var s = SessionGate(); let token = try XCTUnwrap(s.begin()); s.cancel(); XCTAssertFalse(s.transition(.recording, token: token)); XCTAssertEqual(s.phase, .idle) }
    func testOldResponseCannotAffectNextRecording() throws { var s = SessionGate(); let old = try XCTUnwrap(s.begin()); s.cancel(); let new = try XCTUnwrap(s.begin()); XCTAssertFalse(s.transition(.error, token: old)); XCTAssertTrue(s.transition(.recording, token: new)) }
    func testCannotSkipRecording() throws { var s = SessionGate(); let token = try XCTUnwrap(s.begin()); XCTAssertFalse(s.transition(.success, token: token)); XCTAssertFalse(s.transition(.processing, token: token)) }
    func testErrorCanRestart() throws { var s = SessionGate(); let token = try XCTUnwrap(s.begin()); XCTAssertTrue(s.transition(.error, token: token)); XCTAssertNotNil(s.begin()) }
}
final class InsertionPolicyTests: XCTestCase {
    func testSameTarget() { XCTAssertTrue(InsertionPolicy.mayInsert(originalPID: 1, currentPID: 1, sameField: true, originalSelection: NSRange(location: 5, length: 0), currentSelection: NSRange(location: 5, length: 0))) }
    func testAppSwitchRejected() { XCTAssertFalse(InsertionPolicy.mayInsert(originalPID: 1, currentPID: 2, sameField: true, originalSelection: nil, currentSelection: nil)) }
    func testDifferentFieldRejected() { XCTAssertFalse(InsertionPolicy.mayInsert(originalPID: 1, currentPID: 1, sameField: false, originalSelection: nil, currentSelection: nil)) }
    func testMovedCursorRejected() { XCTAssertFalse(InsertionPolicy.mayInsert(originalPID: 1, currentPID: 1, sameField: true, originalSelection: NSRange(location: 5, length: 0), currentSelection: NSRange(location: 6, length: 0))) }
    func testLostRangeRejected() { XCTAssertFalse(InsertionPolicy.mayInsert(originalPID: 1, currentPID: 1, sameField: true, originalSelection: NSRange(location: 5, length: 0), currentSelection: nil)) }
    func testConcurrentClipboardChangeNotOverwritten() { XCTAssertFalse(InsertionPolicy.mayRestoreClipboard(ownedChange: 12, currentChange: 13)); XCTAssertTrue(InsertionPolicy.mayRestoreClipboard(ownedChange: 12, currentChange: 12)) }
}
final class LocalCleanupTests: XCTestCase {
    func edit(_ text: String, _ mode: CleanupMode = .balanced, context: AppContext = .general) -> String { LocalCleanup.edit(.init(transcript: text, mode: mode, context: context, dictionary: [])) }
    func testVerbatimUntouched() { XCTAssertEqual(edit("  um hello hello  ", .verbatim), "  um hello hello  ") }
    func testMinimalKeepsFillers() { XCTAssertEqual(edit("um hello", .minimal), "Um hello.") }
    func testBalancedRemovesSimpleFillers() { XCTAssertEqual(edit("um hello uh world"), "Hello world.") }
    func testWeekdayCorrection() { XCTAssertEqual(edit("Let's meet Tuesday, actually Thursday"), "Let's meet Thursday.") }
    func testMonthCorrection() { XCTAssertEqual(edit("in January, sorry February"), "In February.") }
    func testDoesNotInferComplexCorrections() { XCTAssertEqual(edit("React and Python actually let's use TypeScript"), "React and Python actually let's use TypeScript.") }
    func testPreservesMeaningfulLike() { XCTAssertEqual(edit("I like this"), "I like this.") }
    func testPreservesRepetition() { XCTAssertEqual(edit("very very good"), "Very very good.") }
    func testPreservesNumbersAndAcronyms() { XCTAssertEqual(edit("Use GPU 42 and HTTP"), "Use GPU 42 and HTTP.") }
    func testExistingPunctuation() { XCTAssertEqual(edit("Ready?"), "Ready?") }
    func testExplicitParagraphCommand() { XCTAssertEqual(edit("Hello insert new paragraph next"), "Hello\n\nNext.") }
    func edit(_ text: String, style: WritingStyle, snippets: [Snippet] = []) -> String { LocalCleanup.edit(.init(transcript: text, mode: .balanced, context: .general, dictionary: [], style: style, snippets: snippets)) }
    func testSpokenPunctuation() { XCTAssertEqual(edit("hello comma how are you question mark"), "Hello, how are you?") }
    func testSpokenPunctuationWithWhisperMarks() { XCTAssertEqual(edit("Hello comma, how are you question mark?"), "Hello, how are you?") }
    func testSpokenPeriodAndNewLine() { XCTAssertEqual(edit("first line period new line second line"), "First line.\nSecond line.") }
    func testSpokenEmDash() { XCTAssertEqual(edit("it was great em dash really great"), "It was great—really great.") }
    func testDiscussingPunctuationStaysWords() { XCTAssertEqual(edit("remove the comma please"), "Remove the comma please.") }
    func testNumberedListFromWords() { XCTAssertEqual(edit("Groceries one, milk. Two, eggs. Three, bread."), "Groceries:\n1. Milk\n2. Eggs\n3. Bread") }
    func testNumberedListFromOrdinals() { XCTAssertEqual(edit("first, book the venue. second, send invites"), "1. Book the venue\n2. Send invites") }
    func testNumbersInProseAreNotAList() { XCTAssertEqual(edit("I have one dog and two cats"), "I have one dog and two cats.") }
    func testTimeBacktrack() { XCTAssertEqual(edit("Let's do coffee at 2 actually 3"), "Let's do coffee at 3.") }
    func testIMeanBacktrack() { XCTAssertEqual(edit("see you Friday I mean Saturday"), "See you Saturday.") }
    func testScratchThat() { XCTAssertEqual(edit("Send the report today. Call Sam scratch that. Thanks"), "Send the report today. Thanks.") }
    func testActuallyInProseKept() { XCTAssertEqual(edit("I actually enjoyed the movie"), "I actually enjoyed the movie.") }
    func testCasualDropsTrailingPeriod() { XCTAssertEqual(edit("sounds good to me", style: .casual), "Sounds good to me") }
    func testVeryCasualLowercases() { XCTAssertEqual(edit("Sounds good. See you soon", style: .veryCasual), "sounds good. see you soon") }
    func testVeryCasualKeepsI() { XCTAssertEqual(edit("I'm in", style: .veryCasual), "I'm in") }
    func testWholeSnippet() { XCTAssertEqual(edit("My calendar link.", style: .formal, snippets: [Snippet(cue: "my calendar link", text: "https://cal.com/me")]), "https://cal.com/me") }
    func testInlineSnippetIsProtected() { XCTAssertEqual(edit("book a time here my calendar link thanks", style: .formal, snippets: [Snippet(cue: "my calendar link", text: "https://cal.com/me")]), "Book a time here https://cal.com/me thanks.") }
    func testSpaceAfterPreviousDictation() { XCTAssertEqual(LocalCleanup.joining(after: ".", "Next one."), " Next one."); XCTAssertEqual(LocalCleanup.joining(after: "d", "and more"), " and more") }
    func testNoSpaceAtStartOrAfterSpace() { XCTAssertEqual(LocalCleanup.joining(after: nil, "Hi."), "Hi."); XCTAssertEqual(LocalCleanup.joining(after: " ", "Hi."), "Hi."); XCTAssertEqual(LocalCleanup.joining(after: "\n", "Hi."), "Hi.") }
    func testNoSpaceBeforePunctuationOrAfterOpeners() { XCTAssertEqual(LocalCleanup.joining(after: "d", ", right?"), ", right?"); XCTAssertEqual(LocalCleanup.joining(after: "(", "aside"), "aside"); XCTAssertEqual(LocalCleanup.joining(after: "@", "steph"), "steph") }
    func names(_ text: String, _ entries: [DictionaryEntry]) -> String { LocalCleanup.edit(.init(transcript: text, mode: .balanced, context: .general, dictionary: entries)) }
    func testSoundsLikeReplaced() { XCTAssertEqual(names("I met shiv on today", [DictionaryEntry(spelling: "Siobhan", soundsLike: "shiv on")]), "I met Siobhan today.") }
    func testNearMissNameCorrected() { XCTAssertEqual(names("Thanks Stef", [DictionaryEntry(spelling: "Steph")]), "Thanks Steph."); XCTAssertEqual(names("Call Katharine tomorrow", [DictionaryEntry(spelling: "Katherine")]), "Call Katherine tomorrow.") }
    func testOrdinaryWordsNotChangedToNames() { XCTAssertEqual(names("the step is easy", [DictionaryEntry(spelling: "Steph")]), "The step is easy."); XCTAssertEqual(names("Mark it done", [DictionaryEntry(spelling: "Murmur")]), "Mark it done.") }
    func testPressEnter() { let r = LocalCleanup.extractPressEnter("Sounds good, press enter."); XCTAssertEqual(r.text, "Sounds good"); XCTAssertTrue(r.pressEnter); XCTAssertFalse(LocalCleanup.extractPressEnter("press enter to continue").pressEnter) }
    func testStyleCategories() { XCTAssertEqual(StyleCategory.detect(bundle: "com.tinyspeck.slackmacgap"), .work); XCTAssertEqual(StyleCategory.detect(bundle: "com.apple.MobileSMS"), .personal); XCTAssertEqual(StyleCategory.detect(bundle: "com.apple.mail"), .email); XCTAssertNil(StyleCategory.detect(bundle: "com.google.Chrome")); XCTAssertEqual(StyleCategory.detect(bundle: "com.apple.Notes"), .other) }
    func testOldSettingsGetNewDefaults() throws { let decoded = try JSONDecoder().decode(DictationSettings.self, from: Data(#"{"mode":"minimal"}"#.utf8)); XCTAssertEqual(decoded.mode, .minimal); XCTAssertEqual(decoded.personalStyle, .casual); XCTAssertTrue(decoded.snippets.isEmpty); XCTAssertFalse(decoded.muteWhileDictating) }
    func testLiteralParagraphWords() { XCTAssertEqual(edit("a new paragraph is useful"), "A new paragraph is useful.") }
    func testLiteralPunctuationWords() { XCTAssertEqual(edit("a period of time"), "A period of time.") }
    func testCodePreservesCase() { XCTAssertEqual(edit("myVariable", context: .code), "myVariable") }
    func testChinesePreserved() { XCTAssertEqual(edit("你好世界。"), "你好世界。") }
    func testSpanishPreserved() { XCTAssertEqual(edit("¿Cómo estás?"), "¿Cómo estás?") }
    func testDoesNotRemovePartialWords() { XCTAssertEqual(edit("umbrella and UHF"), "Umbrella and UHF.") }
    func testEmptyInput() { XCTAssertEqual(edit(""), "") }
    func testLegacyPolishedUsesSameRules() { XCTAssertEqual(edit("um hello", .polished), edit("um hello", .balanced)) }
    func testNoCloudSettings() throws {
        let original = DictationSettings(); let data = try JSONEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["transcriptionModel"]); XCTAssertNil(json["cleanupModel"])
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: data); XCTAssertEqual(decoded, original)
    }
    func testReadsPreviousSettings() throws {
        let data = try JSONEncoder().encode(DictationSettings()); var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["transcriptionModel"] = "old-cloud-model"; json["cleanupModel"] = "old-cleanup"
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: JSONSerialization.data(withJSONObject: json)); XCTAssertEqual(decoded.mode, .balanced)
    }
    func testPrivacyDefaults() { XCTAssertFalse(DictationSettings().keepHistory) }
    func testBrowserDoesNotReadTabs() { XCTAssertEqual(AppContext.detect(bundle: "com.google.Chrome"), .general) }
    func testCodeCategory() { XCTAssertEqual(AppContext.detect(bundle: "com.microsoft.VSCode"), .code) }
    func testAsyncLocalCleanup() async throws {
        let result = try await LocalCleanup().clean(.init(transcript: "um hello", mode: .balanced, context: .general, dictionary: []), model: "ignored")
        XCTAssertEqual(result, "Hello.")
    }
}

final class NoteTests: XCTestCase {
    private func withArchive(_ run: (NoteArchive, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(NoteArchive(directory: directory), directory)
    }

    func testCreateEditDeleteAndReload() throws {
        try withArchive { archive, directory in
            let empty = try archive.load()
            XCTAssertEqual(empty, [])
            let created = try archive.add("First note")
            let first = try XCTUnwrap(created.first)
            let added = try archive.add("Second note")
            XCTAssertEqual(added.map(\.text), ["Second note", "First note"])

            let edited = try archive.update(first.id, text: "Edited first note")
            let reopened = NoteArchive(directory: directory)
            let loaded = try reopened.load()
            XCTAssertEqual(loaded, edited)
            XCTAssertEqual(edited.last?.id, first.id)
            XCTAssertEqual(edited.last?.text, "Edited first note")
            let remaining = try reopened.delete(first.id)
            XCTAssertEqual(remaining.map(\.text), ["Second note"])
            let reloaded = try archive.load()
            XCTAssertEqual(reloaded, remaining)
        }
    }

    func testSearchUsesEntireNote() throws {
        try withArchive { archive, _ in
            let notes = try archive.add("\n   \n  Project plan \nRésumé and deadlines")
            let note = try XCTUnwrap(notes.first)
            XCTAssertEqual(note.title, "Project plan")
            XCTAssertTrue(note.matches("  RESUME "))
            XCTAssertTrue(note.matches("deadlines"))
            XCTAssertTrue(note.matches("  "))
            XCTAssertFalse(note.matches("budget"))
        }
    }

    func testCorruptedNotesAreNotOverwritten() throws {
        try withArchive { archive, directory in
            let file = directory.appendingPathComponent("notes.json")
            let corrupted = Data("not JSON".utf8)
            try corrupted.write(to: file)
            do {
                _ = try archive.add("A new note")
                XCTFail("Expected unreadable notes to block saves")
            } catch {}
            let stored = try Data(contentsOf: file)
            XCTAssertEqual(stored, corrupted)
        }
    }
}

final class UpdateTests: XCTestCase {
    private let validHash = String(repeating: "a", count: 64)

    func testVersionComparison() {
        let current = AppVersion(shortVersion: "0.4.0", build: 5)
        XCTAssertTrue(AppVersion(shortVersion: "0.4.0", build: 6).isNewer(than: current))
        XCTAssertTrue(AppVersion(shortVersion: "0.5.0", build: 1).isNewer(than: current))
        XCTAssertTrue(AppVersion(shortVersion: "v0.4.1", build: 5).isNewer(than: current))
        XCTAssertFalse(AppVersion(shortVersion: "0.4.0", build: 5).isNewer(than: current))
        XCTAssertFalse(AppVersion(shortVersion: "0.4.0", build: 4).isNewer(than: current))
        XCTAssertFalse(AppVersion(shortVersion: "0.3.9", build: 99).isNewer(than: current))
    }

    func testManifestDecodingAndValidation() throws {
        let json = """
        {
          "version": "0.4.0",
          "build": 7,
          "commit": "abc1234",
          "downloadURL": "https://github.com/stephaniesgao/murmur/releases/download/v0.4.0-b7/Murmur.zip",
          "sha256": "\(validHash)",
          "notes": "Add auto-updates"
        }
        """
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        try manifest.validate()
        XCTAssertTrue(UpdatePolicy.isUpdateAvailable(current: AppVersion(shortVersion: "0.4.0", build: 5), manifest: manifest))
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(current: AppVersion(shortVersion: "0.4.0", build: 7), manifest: manifest))
    }

    func testManifestRejectsPlainHTTPAndBadChecksum() {
        let remoteHTTP = UpdateManifest(version: "0.4.0", build: 7, downloadURL: URL(string: "http://example.com/Murmur.zip")!, sha256: validHash)
        do { try remoteHTTP.validate(allowLocalHTTP: true); XCTFail("Expected remote HTTP rejection") } catch {}

        let localHTTP = UpdateManifest(version: "0.4.0", build: 7, downloadURL: URL(string: "http://127.0.0.1:8080/Murmur.zip")!, sha256: validHash)
        do { try localHTTP.validate(allowLocalHTTP: false); XCTFail("Expected local HTTP rejection when disallowed") } catch {}
        do { try localHTTP.validate(allowLocalHTTP: true) } catch { XCTFail("Expected local HTTP allowed when opted in: \(error)") }

        let badHash = UpdateManifest(version: "0.4.0", build: 7, downloadURL: URL(string: "https://github.com/stephaniesgao/murmur/releases/download/v0.4.0-b7/Murmur.zip")!, sha256: "not-a-sha")
        do { try badHash.validate(); XCTFail("Expected bad SHA-256 rejection") } catch {}
    }

    func testInstallHelperArgumentsKeepPathsOutOfScript() {
        let args = UpdatePolicy.installHelperArguments(pid: 42, stagedAppPath: "/tmp/a b/Murmur.app", targetAppPath: "/Applications/Murmur.app", stagingRootPath: "/tmp/a b")
        XCTAssertEqual(args.count, 7)
        XCTAssertEqual(args[0], "-c")
        XCTAssertFalse(args[1].contains("/Applications/Murmur.app"))
        XCTAssertEqual(args[3], "42")
        XCTAssertEqual(args[4], "/tmp/a b/Murmur.app")
        XCTAssertEqual(args[5], "/Applications/Murmur.app")
        XCTAssertEqual(args[6], "/tmp/a b")
    }

    func testAutoCheckUpdatesDefaultsTrueForOldSettings() throws {
        let decoded = try JSONDecoder().decode(DictationSettings.self, from: Data(#"{"mode":"balanced"}"#.utf8))
        XCTAssertTrue(decoded.autoCheckUpdates)
    }

    func testAutoCheckUpdatesDoesNotAffectCaptureBehavior() {
        let base = DictationSettings()
        var toggled = base; toggled.autoCheckUpdates = !base.autoCheckUpdates
        XCTAssertFalse(toggled.differsInCaptureBehavior(from: base))
        var modeChanged = base; modeChanged.mode = .verbatim
        XCTAssertTrue(modeChanged.differsInCaptureBehavior(from: base))
    }
}

final class AudioProcessingTests: XCTestCase {
    func testPCM16ToFloat() {
        let floats = AudioSampleUtils.pcm16ToFloat([0, 16_384, -32_768])
        XCTAssertEqual(floats.count, 3)
        XCTAssertEqual(floats[0], 0)
        XCTAssertTrue(abs(floats[1] - 0.5) < 0.0001)
        XCTAssertTrue(abs(floats[2] + 1.0) < 0.0001)
    }

    func testTrimSilenceKeepsPadding() {
        let sr = AudioSampleUtils.sampleRate
        var samples = [Float](repeating: 0, count: sr * 5) // 5 seconds
        // Active speech from 2.0s to 3.0s
        for i in (sr * 2)..<(sr * 3) { samples[i] = 0.2 }
        let trimmed = AudioSampleUtils.trimSilence(samples)
        // Expected: ~1.5s (1s speech + 0.25s padding before and after)
        XCTAssertTrue(trimmed.count >= Int(Double(sr) * 1.45) && trimmed.count <= Int(Double(sr) * 1.55))
        XCTAssertTrue(AudioSampleUtils.peakRMS(trimmed) > 0.15)
    }

    func testTrimSilenceKeepsAllQuietAudio() {
        let samples = [Float](repeating: 0.001, count: AudioSampleUtils.sampleRate)
        let trimmed = AudioSampleUtils.trimSilence(samples)
        XCTAssertEqual(trimmed.count, samples.count)
    }

    func testChunkPlannerIgnoresShortRecordings() {
        let planner = AudioChunkPlanner(minChunkSeconds: 10, maxChunkSeconds: 25, silenceSeconds: 0.45)
        let sr = AudioSampleUtils.sampleRate
        // 8s of speech + 1s silence = 9s (< 10s min)
        let samples = [Int16](repeating: 6_000, count: sr * 8) + [Int16](repeating: 0, count: sr)
        XCTAssertNil(planner.splitLength(for: samples[...]))
    }

    func testChunkPlannerSplitsOnPause() {
        let planner = AudioChunkPlanner(minChunkSeconds: 10, maxChunkSeconds: 25, silenceSeconds: 0.45)
        let sr = AudioSampleUtils.sampleRate
        // 10s of speech + 0.6s of silence
        let samples = [Int16](repeating: 6_000, count: sr * 10) + [Int16](repeating: 0, count: Int(Double(sr) * 0.6))
        let split = planner.splitLength(for: samples[...])
        XCTAssertNotNil(split)
        if let split {
            XCTAssertTrue(split >= sr * 10 && split < samples.count)
        }
    }

    func testChunkPlannerSplitsContinuousSpeechAtMaxLength() {
        let planner = AudioChunkPlanner(minChunkSeconds: 10, maxChunkSeconds: 25, silenceSeconds: 0.45)
        let sr = AudioSampleUtils.sampleRate
        // 26s of continuous speech with a quieter dip around 23.5s
        var samples = [Int16](repeating: 8_000, count: sr * 26)
        let dipStart = Int(Double(sr) * 23.5)
        for i in dipStart..<(dipStart + 640) { samples[i] = 1_000 }
        let split = planner.splitLength(for: samples[...])
        XCTAssertNotNil(split)
        if let split {
            XCTAssertTrue(split >= dipStart && split <= dipStart + 640)
        }
    }
}

@main struct CheckRunner {
    static func main() async throws {
        print("Check: ShortcutTests.testHold"); ShortcutTests().testHold()
        print("Check: ShortcutTests.testSingleTapIsDiscarded"); ShortcutTests().testSingleTapIsDiscarded()
        print("Check: ShortcutTests.testQuickTripleTapCancels"); ShortcutTests().testQuickTripleTapCancels()
        print("Check: ShortcutTests.testFnSpaceLocksHandsFree"); ShortcutTests().testFnSpaceLocksHandsFree()
        print("Check: ShortcutTests.testFnSpaceIgnoredWhenNotHolding"); ShortcutTests().testFnSpaceIgnoredWhenNotHolding()
        print("Check: ShortcutTests.testDoubleTapHandsFree"); ShortcutTests().testDoubleTapHandsFree()
        print("Check: ShortcutTests.testAutoRepeatIgnored"); ShortcutTests().testAutoRepeatIgnored()
        print("Check: ShortcutTests.testResetDuringHold"); ShortcutTests().testResetDuringHold()
        print("Check: ShortcutTests.testResetPendingTap"); ShortcutTests().testResetPendingTap()
        print("Check: StateTests.testFullLifecycle"); try StateTests().testFullLifecycle()
        print("Check: StateTests.testDuplicateStartRejected"); StateTests().testDuplicateStartRejected()
        print("Check: StateTests.testDuplicateCompletionRejected"); try StateTests().testDuplicateCompletionRejected()
        print("Check: StateTests.testCancelInvalidatesResponses"); try StateTests().testCancelInvalidatesResponses()
        print("Check: StateTests.testOldResponseCannotAffectNextRecording"); try StateTests().testOldResponseCannotAffectNextRecording()
        print("Check: StateTests.testCannotSkipRecording"); try StateTests().testCannotSkipRecording()
        print("Check: StateTests.testErrorCanRestart"); try StateTests().testErrorCanRestart()
        print("Check: InsertionPolicyTests.testSameTarget"); InsertionPolicyTests().testSameTarget()
        print("Check: InsertionPolicyTests.testAppSwitchRejected"); InsertionPolicyTests().testAppSwitchRejected()
        print("Check: InsertionPolicyTests.testDifferentFieldRejected"); InsertionPolicyTests().testDifferentFieldRejected()
        print("Check: InsertionPolicyTests.testMovedCursorRejected"); InsertionPolicyTests().testMovedCursorRejected()
        print("Check: InsertionPolicyTests.testLostRangeRejected"); InsertionPolicyTests().testLostRangeRejected()
        print("Check: InsertionPolicyTests.testConcurrentClipboardChangeNotOverwritten"); InsertionPolicyTests().testConcurrentClipboardChangeNotOverwritten()
        print("Check: LocalCleanupTests.testVerbatimUntouched"); LocalCleanupTests().testVerbatimUntouched()
        print("Check: LocalCleanupTests.testMinimalKeepsFillers"); LocalCleanupTests().testMinimalKeepsFillers()
        print("Check: LocalCleanupTests.testBalancedRemovesSimpleFillers"); LocalCleanupTests().testBalancedRemovesSimpleFillers()
        print("Check: LocalCleanupTests.testWeekdayCorrection"); LocalCleanupTests().testWeekdayCorrection()
        print("Check: LocalCleanupTests.testMonthCorrection"); LocalCleanupTests().testMonthCorrection()
        print("Check: LocalCleanupTests.testDoesNotInferComplexCorrections"); LocalCleanupTests().testDoesNotInferComplexCorrections()
        print("Check: LocalCleanupTests.testPreservesMeaningfulLike"); LocalCleanupTests().testPreservesMeaningfulLike()
        print("Check: LocalCleanupTests.testPreservesRepetition"); LocalCleanupTests().testPreservesRepetition()
        print("Check: LocalCleanupTests.testPreservesNumbersAndAcronyms"); LocalCleanupTests().testPreservesNumbersAndAcronyms()
        print("Check: LocalCleanupTests.testExistingPunctuation"); LocalCleanupTests().testExistingPunctuation()
        print("Check: LocalCleanupTests.testExplicitParagraphCommand"); LocalCleanupTests().testExplicitParagraphCommand()
        print("Check: LocalCleanupTests.testSpokenPunctuation"); LocalCleanupTests().testSpokenPunctuation()
        print("Check: LocalCleanupTests.testSpokenPunctuationWithWhisperMarks"); LocalCleanupTests().testSpokenPunctuationWithWhisperMarks()
        print("Check: LocalCleanupTests.testSpokenPeriodAndNewLine"); LocalCleanupTests().testSpokenPeriodAndNewLine()
        print("Check: LocalCleanupTests.testSpokenEmDash"); LocalCleanupTests().testSpokenEmDash()
        print("Check: LocalCleanupTests.testDiscussingPunctuationStaysWords"); LocalCleanupTests().testDiscussingPunctuationStaysWords()
        print("Check: LocalCleanupTests.testNumberedListFromWords"); LocalCleanupTests().testNumberedListFromWords()
        print("Check: LocalCleanupTests.testNumberedListFromOrdinals"); LocalCleanupTests().testNumberedListFromOrdinals()
        print("Check: LocalCleanupTests.testNumbersInProseAreNotAList"); LocalCleanupTests().testNumbersInProseAreNotAList()
        print("Check: LocalCleanupTests.testTimeBacktrack"); LocalCleanupTests().testTimeBacktrack()
        print("Check: LocalCleanupTests.testIMeanBacktrack"); LocalCleanupTests().testIMeanBacktrack()
        print("Check: LocalCleanupTests.testScratchThat"); LocalCleanupTests().testScratchThat()
        print("Check: LocalCleanupTests.testActuallyInProseKept"); LocalCleanupTests().testActuallyInProseKept()
        print("Check: LocalCleanupTests.testCasualDropsTrailingPeriod"); LocalCleanupTests().testCasualDropsTrailingPeriod()
        print("Check: LocalCleanupTests.testVeryCasualLowercases"); LocalCleanupTests().testVeryCasualLowercases()
        print("Check: LocalCleanupTests.testVeryCasualKeepsI"); LocalCleanupTests().testVeryCasualKeepsI()
        print("Check: LocalCleanupTests.testWholeSnippet"); LocalCleanupTests().testWholeSnippet()
        print("Check: LocalCleanupTests.testInlineSnippetIsProtected"); LocalCleanupTests().testInlineSnippetIsProtected()
        print("Check: LocalCleanupTests.testSpaceAfterPreviousDictation"); LocalCleanupTests().testSpaceAfterPreviousDictation()
        print("Check: LocalCleanupTests.testNoSpaceAtStartOrAfterSpace"); LocalCleanupTests().testNoSpaceAtStartOrAfterSpace()
        print("Check: LocalCleanupTests.testNoSpaceBeforePunctuationOrAfterOpeners"); LocalCleanupTests().testNoSpaceBeforePunctuationOrAfterOpeners()
        print("Check: LocalCleanupTests.testSoundsLikeReplaced"); LocalCleanupTests().testSoundsLikeReplaced()
        print("Check: LocalCleanupTests.testNearMissNameCorrected"); LocalCleanupTests().testNearMissNameCorrected()
        print("Check: LocalCleanupTests.testOrdinaryWordsNotChangedToNames"); LocalCleanupTests().testOrdinaryWordsNotChangedToNames()
        print("Check: LocalCleanupTests.testPressEnter"); LocalCleanupTests().testPressEnter()
        print("Check: LocalCleanupTests.testStyleCategories"); LocalCleanupTests().testStyleCategories()
        print("Check: LocalCleanupTests.testOldSettingsGetNewDefaults"); try LocalCleanupTests().testOldSettingsGetNewDefaults()
        print("Check: LocalCleanupTests.testLiteralParagraphWords"); LocalCleanupTests().testLiteralParagraphWords()
        print("Check: LocalCleanupTests.testLiteralPunctuationWords"); LocalCleanupTests().testLiteralPunctuationWords()
        print("Check: LocalCleanupTests.testCodePreservesCase"); LocalCleanupTests().testCodePreservesCase()
        print("Check: LocalCleanupTests.testChinesePreserved"); LocalCleanupTests().testChinesePreserved()
        print("Check: LocalCleanupTests.testSpanishPreserved"); LocalCleanupTests().testSpanishPreserved()
        print("Check: LocalCleanupTests.testDoesNotRemovePartialWords"); LocalCleanupTests().testDoesNotRemovePartialWords()
        print("Check: LocalCleanupTests.testEmptyInput"); LocalCleanupTests().testEmptyInput()
        print("Check: LocalCleanupTests.testLegacyPolishedUsesSameRules"); LocalCleanupTests().testLegacyPolishedUsesSameRules()
        print("Check: LocalCleanupTests.testNoCloudSettings"); try LocalCleanupTests().testNoCloudSettings()
        print("Check: LocalCleanupTests.testReadsPreviousSettings"); try LocalCleanupTests().testReadsPreviousSettings()
        print("Check: LocalCleanupTests.testPrivacyDefaults"); LocalCleanupTests().testPrivacyDefaults()
        print("Check: LocalCleanupTests.testBrowserDoesNotReadTabs"); LocalCleanupTests().testBrowserDoesNotReadTabs()
        print("Check: LocalCleanupTests.testCodeCategory"); LocalCleanupTests().testCodeCategory()
        print("Check: LocalCleanupTests.testAsyncLocalCleanup"); try await LocalCleanupTests().testAsyncLocalCleanup()
        print("Check: NoteTests.testCreateEditDeleteAndReload"); try NoteTests().testCreateEditDeleteAndReload()
        print("Check: NoteTests.testSearchUsesEntireNote"); try NoteTests().testSearchUsesEntireNote()
        print("Check: NoteTests.testCorruptedNotesAreNotOverwritten"); try NoteTests().testCorruptedNotesAreNotOverwritten()
        print("Check: UpdateTests.testVersionComparison"); UpdateTests().testVersionComparison()
        print("Check: UpdateTests.testManifestDecodingAndValidation"); try UpdateTests().testManifestDecodingAndValidation()
        print("Check: UpdateTests.testManifestRejectsPlainHTTPAndBadChecksum"); UpdateTests().testManifestRejectsPlainHTTPAndBadChecksum()
        print("Check: UpdateTests.testInstallHelperArgumentsKeepPathsOutOfScript"); UpdateTests().testInstallHelperArgumentsKeepPathsOutOfScript()
        print("Check: UpdateTests.testAutoCheckUpdatesDefaultsTrueForOldSettings"); try UpdateTests().testAutoCheckUpdatesDefaultsTrueForOldSettings()
        print("Check: UpdateTests.testAutoCheckUpdatesDoesNotAffectCaptureBehavior"); UpdateTests().testAutoCheckUpdatesDoesNotAffectCaptureBehavior()
        print("Check: AudioProcessingTests.testPCM16ToFloat"); AudioProcessingTests().testPCM16ToFloat()
        print("Check: AudioProcessingTests.testTrimSilenceKeepsPadding"); AudioProcessingTests().testTrimSilenceKeepsPadding()
        print("Check: AudioProcessingTests.testTrimSilenceKeepsAllQuietAudio"); AudioProcessingTests().testTrimSilenceKeepsAllQuietAudio()
        print("Check: AudioProcessingTests.testChunkPlannerIgnoresShortRecordings"); AudioProcessingTests().testChunkPlannerIgnoresShortRecordings()
        print("Check: AudioProcessingTests.testChunkPlannerSplitsOnPause"); AudioProcessingTests().testChunkPlannerSplitsOnPause()
        print("Check: AudioProcessingTests.testChunkPlannerSplitsContinuousSpeechAtMaxLength"); AudioProcessingTests().testChunkPlannerSplitsContinuousSpeechAtMaxLength()
 print("88 checks, \(failureCount) failures")
 if failureCount > 0 { exit(1) }
 }
}
