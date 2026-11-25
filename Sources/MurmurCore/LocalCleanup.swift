import Foundation

/// Rule-based, on-device text cleanup. Everything here is deterministic and local; there is no
/// AI rewriting. Rules aim to match what people expect from a dictation app:
/// spoken punctuation, lists, backtracking, snippets and per-app writing styles.
public struct LocalCleanup: CleanupProvider {
    public init() {}
    public func clean(_ request: CleanupRequest, model: String = "local-rules") async throws -> String {
        try Task.checkCancellation()
        return Self.edit(request)
    }

    public static func edit(_ request: CleanupRequest) -> String {
        // Saying only a snippet's cue inserts the snippet exactly as saved.
        if let whole = wholeSnippet(request.transcript, snippets: request.snippets) { return whole }
        if request.mode == .verbatim { return request.transcript }
        var text = request.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = applyDictionary(text, request.dictionary)
        // Protect snippet expansions from later punctuation and casing rules.
        var protected: [String] = []
        text = expandSnippets(text, snippets: request.snippets, into: &protected)

        text = spokenPunctuation(text)
        if request.mode == .balanced || request.mode == .polished {
            // Conservative fillers only. Keep “like”, “so”, “well”, “you know”, and
            // repetitions because they often carry meaning or deliberate emphasis.
            text = replacing(#"(?i)(?<![\p{L}\p{N}_])(?:um+|uh+|erm+|uhm+)(?![\p{L}\p{N}_])[,.]?\s*"#, in: text, with: "")
            text = backtrack(text)
        }
        let list = formatList(text)
        if let list { text = list }

        text = tidySpacing(text)
        // Code mode preserves casing and does not append punctuation to identifiers.
        if request.context == .code { return restore(text, protected) }

        text = capitalizeSentenceStarts(text)
        if list == nil, let last = text.last, last.isLetter || last.isNumber { text += "." }
        if list == nil { text = apply(request.style, to: text) }
        return restore(text, protected)
    }

    /// Adds a space before dictated text when it would otherwise run into the word before the
    /// cursor (e.g. dictating twice in a row). `previous` is the character before the cursor.
    public static func joining(after previous: Character?, _ text: String) -> String {
        guard let previous, let first = text.first else { return text }
        if previous.isWhitespace || previous.isNewline || "([{\"'“‘/-–—@#".contains(previous) { return text }
        if first.isWhitespace || first.isNewline || ",.;:!?)]}”’…".contains(first) { return text }
        return " " + text
    }

    /// Detects a trailing “press enter” / “hit return”. Returns the text without it.
    public static func extractPressEnter(_ text: String) -> (text: String, pressEnter: Bool) {
        let pattern = #"(?i)[,.]?\s*\b(?:press|hit) (?:enter|return)\b[.!]?\s*$"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return (text, false) }
        return (String(text[..<range.lowerBound]), true)
    }

    // MARK: Spoken punctuation

    private static let determiners = "(?<!\\b(?:a|an|the|this|that|each|every|my|your|its|one)\\s)"
    private static let spokenMarks: [(words: String, mark: String)] = [
        ("(?:insert |start a |add a )?new paragraph|skip a line", "\n\n"),
        ("(?:insert )?new line|next line|line break", "\n"),
        ("(?:insert (?:a )?)?question mark", "?"),
        ("exclamation (?:point|mark)", "!"),
        ("semicolon", ";"),
        ("colon", ":"),
        ("em[- ]?dash", "—"),
        ("(?:insert (?:a )?)?comma", ","),
        ("period|full stop", "."),
    ]

    /// Turns spoken punctuation into marks. Phrases right after “a/the/this…” stay as words,
    /// so “a period of time” or “the comma” are left alone.
    static func spokenPunctuation(_ input: String) -> String {
        var text = input
        for (words, mark) in spokenMarks {
            let pattern = "(?i)[,.]?\\s*" + determiners + "\\b(?:" + words + ")\\b[,.;:!?]?"
            let template = mark == "\n" || mark == "\n\n" ? mark : mark + " "
            text = replacing(pattern, in: text, with: NSRegularExpression.escapedTemplate(for: template))
        }
        text = replacing(#"\s*—\s*"#, in: text, with: "—")
        return text
    }

    // MARK: Backtrack

    private static let numberWord = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"
    private static let correction = #"(?:actually|sorry|I mean|no wait|wait,? no)"#

    /// Removes clear self-corrections only.
    static func backtrack(_ input: String) -> String {
        var text = input
        // “…, scratch that” / “never mind.” drops the sentence fragment it follows.
        text = replacing(#"(?i)[^.!?\n]*?\b(?:scratch that|forget that|delete that)\b[,.!?]?\s*"#, in: text, with: " ")
        text = replacing(#"(?i)[^.!?\n]*?\bnever ?mind\b(?:[,.!?]\s*|\s*$)"#, in: text, with: " ")
        // Finite, unambiguous value swaps: “Tuesday, actually Thursday”, “at 2 actually 3”.
        let groups = [
            "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday",
            "January|February|March|April|May|June|July|August|September|October|November|December",
            #"\d{1,2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?|"# + numberWord + "|noon|midnight",
        ]
        for group in groups {
            let pattern = "(?i)\\b(?:" + group + ")[,.]?\\s+" + correction + "[,.]?\\s+(" + group + ")\\b"
            text = replacing(pattern, in: text, with: "$1")
        }
        return text
    }

    // MARK: Lists

    private static let markerWords: [[String]] = [
        ["one", "first", "firstly"], ["two", "second", "secondly"], ["three", "third", "thirdly"],
        ["four", "fourth"], ["five", "fifth"], ["six", "sixth"], ["seven", "seventh"],
        ["eight", "eighth"], ["nine", "ninth"], ["ten", "tenth"],
    ]

    /// “Groceries one, milk. Two, eggs.” → a numbered list. A marker counts only when it's followed
    /// by punctuation (as Whisper writes spoken list items), so “one dog and two cats” stays prose.
    static func formatList(_ input: String) -> String? {
        let words = markerWords.flatMap { $0 }.joined(separator: "|")
        let pattern = "(?i)(?<![\\p{L}\\p{N}'’])(?:(" + words + ")[,.:]|(\\d{1,2})[.)])\\s+"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = input as NSString
        var markers: [(number: Int, range: NSRange)] = []
        for match in expression.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            var number = 0
            if match.range(at: 1).location != NSNotFound {
                let word = ns.substring(with: match.range(at: 1)).lowercased()
                number = (markerWords.firstIndex { $0.contains(word) } ?? -1) + 1
            } else if match.range(at: 2).location != NSNotFound {
                number = Int(ns.substring(with: match.range(at: 2))) ?? 0
            }
            if number > 0 { markers.append((number, match.range)) }
        }
        var chosen: [NSRange] = []
        for marker in markers where marker.number == chosen.count + 1 { chosen.append(marker.range) }
        guard chosen.count >= 2 else { return nil }

        func clean(_ s: String) -> String {
            var item = s.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = item.last, ",;.".contains(last) { item.removeLast() }
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = item.first, first.isLowercase { item = first.uppercased() + item.dropFirst() }
            return item
        }
        var intro = clean(ns.substring(to: chosen[0].location))
        while let last = intro.last, ":".contains(last) { intro.removeLast() }
        var items: [String] = []
        for (index, range) in chosen.enumerated() {
            let start = range.location + range.length
            let end = index + 1 < chosen.count ? chosen[index + 1].location : ns.length
            let item = clean(ns.substring(with: NSRange(location: start, length: max(0, end - start))))
            guard !item.isEmpty else { return nil }
            items.append("\(index + 1). \(item)")
        }
        return (intro.isEmpty ? "" : intro + ":\n") + items.joined(separator: "\n")
    }

    // MARK: Dictionary

    /// Makes your Dictionary spellings stick: “sounds like” phrases are replaced with the spelling,
    /// and capitalized words that are a letter or two off a Dictionary name are corrected.
    static func applyDictionary(_ input: String, _ entries: [DictionaryEntry]) -> String {
        var text = input
        for entry in entries {
            let spelling = entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spelling.isEmpty else { continue }
            for alias in entry.soundsLike.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !alias.isEmpty {
                let words = alias.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
                text = replacing("(?i)(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s-]+") + "(?![\\p{L}\\p{N}])", in: text, with: NSRegularExpression.escapedTemplate(for: spelling))
            }
        }
        // Near-miss correction for single-word names (4+ letters), only on capitalized words.
        let names = entries.map { $0.spelling.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 4 && !$0.contains(" ") }
        guard !names.isEmpty, let expression = try? NSRegularExpression(pattern: "\\p{Lu}[\\p{L}'’]+") else { return text }
        let ns = text as NSString
        var result = text
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let word = ns.substring(with: match.range)
            guard !names.contains(word) else { continue }
            let lowered = word.lowercased()
            let best = names.map { ($0, distance(lowered, $0.lowercased())) }.min { $0.1 < $1.1 }
            guard let (name, d) = best, d > 0, d <= (name.count >= 5 ? 2 : 1), abs(name.count - word.count) <= 2,
                  name.first?.lowercased() == word.first?.lowercased() else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: name)
        }
        return result
    }

    /// Edit distance between two short words.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }; guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count { current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Snippets

    private static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func wholeSnippet(_ transcript: String, snippets: [Snippet]) -> String? {
        let spoken = normalized(transcript)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { !normalized($0.cue).isEmpty && normalized($0.cue) == spoken }?.text
    }

    private static func expandSnippets(_ input: String, snippets: [Snippet], into protected: inout [String]) -> String {
        var text = input
        for snippet in snippets {
            let words = normalized(snippet.cue).split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty, let expression = try? NSRegularExpression(pattern: "(?i)\\b" + words.joined(separator: "[\\s,.]+") + "\\b[.,]?") else { continue }
            let ns = text as NSString
            let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var result = text
            for match in matches.reversed() {
                let token = "\u{E000}\(protected.count)\u{E001}"
                protected.append(snippet.text)
                result = (result as NSString).replacingCharacters(in: match.range, with: token)
            }
            text = result
        }
        return text
    }

    private static func restore(_ input: String, _ protected: [String]) -> String {
        var text = input
        for (index, value) in protected.enumerated() { text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: value) }
        return text
    }

    // MARK: Styles

    static func apply(_ style: WritingStyle, to input: String) -> String {
        guard style != .formal else { return input }
        var text = input
        // Casual messages don't end with a period (an ellipsis is kept).
        if text.hasSuffix("."), !text.hasSuffix("..") { text.removeLast() }
        if style == .veryCasual {
            text = transformSentenceStarts(text) { word in
                // Keep “I”, “I'm” and acronyms; lowercase ordinary capitalized words.
                guard word.count > 1, let second = word.dropFirst().first, second.isLowercase else { return word }
                return word.prefix(1).lowercased() + word.dropFirst()
            }
        }
        return text
    }

    // MARK: Spacing and casing

    private static func tidySpacing(_ input: String) -> String {
        var text = input
        text = replacing(#"[\t ]+"#, in: text, with: " ")
        text = replacing(#" +([,.;:!?])"#, in: text, with: "$1")
        // Collapse doubled marks left by spoken punctuation next to Whisper's own.
        text = replacing(#"([,;:])[,.]+"#, in: text, with: "$1")
        text = replacing(#"([.!?])[,.]+"#, in: text, with: "$1")
        text = replacing(#",([.!?])"#, in: text, with: "$1")
        text = replacing(#"([,;:!?])(?=\p{L})"#, in: text, with: "$1 ")
        text = replacing(#" +\n"#, in: text, with: "\n")
        text = replacing(#"\n +"#, in: text, with: "\n")
        text = replacing(#"^[,.;:]\s*"#, in: text, with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentenceStarts(_ input: String) -> String {
        transformSentenceStarts(input) { word in
            guard let first = word.first, first.isLowercase else { return word }
            return first.uppercased() + word.dropFirst()
        }
    }

    /// Applies `change` to the first word of the text and of every sentence or line.
    private static func transformSentenceStarts(_ input: String, _ change: (String) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?:^|(?<=[.!?]\s)|(?<=\n))([\p{L}][\p{L}'’]*)"#) else { return input }
        let ns = input as NSString
        var result = input
        for match in expression.matches(in: input, range: NSRange(location: 0, length: ns.length)).reversed() {
            let word = ns.substring(with: match.range(at: 1))
            result = (result as NSString).replacingCharacters(in: match.range(at: 1), with: change(word))
        }
        return result
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
