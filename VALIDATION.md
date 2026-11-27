# Murmur 0.2.0 validation

This build replaces API transcription and model cleanup with Apple's on-device Speech framework and deterministic local cleanup. Previous cloud-version validation does not establish speech recognition quality in this version.

## Automated/build verification

- Release build and ad-hoc app packaging on arm64 macOS with Swift 6.1.2 Command Line Tools.
- 44 dependency-free checks covering shortcut hold/tap/hands-free handling, cancellation/stale-session gates, insertion/clipboard policy, local cleanup and backward-compatible settings decoding.
- Tests explicitly preserve meaningful words (“like”), deliberate repetitions, technical acronyms/numbers, Spanish/Chinese text and complex corrections the rules cannot safely resolve.
- Verbatim leaves recognition output byte-for-byte unchanged. Minimal retains fillers. Balanced resolves adjacent weekday/month corrections only.
- No OpenAI client, credential UI, Keychain access, URLSession or transcription/cleanup HTTP request code remains in the app sources.
- The Microphone usage description is included (Speech Recognition is no longer used as of 0.3.0). Signatures and property-list syntax are verified during packaging.

## Limitations / manual checks still required

The 0.2.0 native UI and live microphone→recognition→insertion path have not been verified with permission grants. Desktop-control tools stalled during prior launch verification, so the build report is not a claim of successful interactive relaunch.

Before daily use, install at a stable location and download the speech model in Setup and enable Microphone, Accessibility and Input Monitoring. Verify a physical Fn hold, release, double-tap, stop, fallback shortcut and Escape. Test recognition accuracy in the chosen language, denied/revoked permission, a missing or partially downloaded model, microphone changes, silence, the 55-second capture limit, cancellation, and sleep/lock.

Verify original cursor/field preservation and single insertion in TextEdit and your real applications. Unsupported or ambiguous fields require manual copy. Clipboard fallback restores only if ownership did not change, and cannot prove target paste consumption.

Apple's model assets and selected locale control whether offline recognition is available. The implementation checks support before recognizing and requires local recognition on the request; it never opts into server fallback. Lack of support produces an error, not a fabricated transcript. A local support diagnostic does not establish recognition accuracy or microphone access.

No certified verbatim transcription, general grammar rewriting, automatic language identification, guaranteed code-switching, or notarized distribution is claimed.

## Diagnostic result on this Mac

The noninteractive `--check-speech-support` command completed and reported no Assistant asset for en-US / on-device recognition unavailable for en_US. This build therefore cannot yet complete local English dictation here until macOS supplies the asset/support. The diagnostic ran without requesting Speech permission or recording audio; support should be checked again after setup. All 44 checks passed in the optimized runner. Release code-signature and plist verification passed.


## 0.3.0 Whisper check (2026-11-24)

On an Apple silicon Mac running macOS 15.7, the Balanced model (openai_whisper-small_216MB) downloaded through Murmur's own download path and transcribed synthesized test audio: an English sentence in 1.2 s (0.7 s on a warm second launch, which loaded the model and tokenizer from disk) and a Spanish sentence in 0.4 s with automatic language detection. A live microphone dictation through the Fn shortcut was not part of this check.

## Voice notes shortcut regression checks (macOS)

- Start a note, tap Fn once, and wait a second. The recording should continue; click Stop note and verify the saved note. Start another note and press Escape; the recording should stop without saving.
