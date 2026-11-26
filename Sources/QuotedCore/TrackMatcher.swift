import Foundation

/// Conservative metadata matching. An ambiguous result requires a person's choice.
public enum TrackMatcher {
    public static func normalized(_ text: String) -> String {
        var folded = text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        // Strip Latin accents without merging distinct Cyrillic letters such as й/и.
        if let latin = try? NSRegularExpression(pattern: "[\\p{Latin}\\p{M}]+") {
            let original = folded
            for match in latin.matches(in: original, range: NSRange(original.startIndex..., in: original)).reversed() {
                if let range = Range(match.range, in: folded) {
                    let plain = String(folded[range]).folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                    folded.replaceSubrange(range, with: plain)
                }
            }
        }
        return folded
            .replacingOccurrences(of: "[’'`\u{200b}\u{200c}\u{200d}\u{feff}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func baseTitle(_ title: String) -> String {
        var value = title
        // Remaster dates and featured credits don't change the song's words.
        value = value.replacingOccurrences(of: "(?i)\\s*[\\(\\[]\\s*(?:feat\\.?|ft\\.?|featuring)\\s+[^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)\\s+(?:feat\\.?|ft\\.?|featuring)\\s+.*$", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)\\s*(?:[-–—]\\s*|[\\(\\[])\\s*(?:(?:19|20)\\d{2}\\s+)?(?:digital(?:ly)?\\s+)?remaster(?:ed)?(?:\\s+(?:version|(?:19|20)\\d{2}))*\\s*[\\)\\]]?\\s*$", with: "", options: .regularExpression)
        return normalized(value)
    }

    private static let versionPatterns: [(String, String)] = [
        ("live", "\\blive\\b"), ("remix", "\\bremix\\b"), ("acoustic", "\\bacoustic\\b"),
        ("instrumental", "\\binstrumental\\b"), ("karaoke", "\\bkaraoke\\b"),
        ("sped up", "\\bsped up\\b"), ("slowed", "\\bslowed\\b"),
        ("demo", "\\bdemo\\b"), ("radio edit", "\\bradio edit\\b"),
        ("extended", "\\bextended\\b"), ("clean", "\\bclean\\b"),
        ("taylors version", "\\btaylors version\\b")
    ]

    public static func versions(_ title: String) -> Set<String> {
        let value = normalized(title)
        return Set(versionPatterns.compactMap { name, pattern in
            value.range(of: pattern, options: .regularExpression) == nil ? nil : name
        })
    }

    private static func artistWords(_ text: String) -> Set<String> {
        Set(normalized(text).split(separator: " ").map(String.init))
    }

    public static func artistMatches(_ artist: String, candidates: [String]) -> Bool {
        let wanted = artistWords(artist)
        guard !wanted.isEmpty else { return false }
        if candidates.contains(where: { artistWords($0) == wanted }) { return true }
        if artistWords(candidates.joined(separator: " ")) == wanted { return true }
        let credits = artist.components(separatedBy: try! NSRegularExpression(pattern: "(?i)\\s+(?:feat\\.?|ft\\.?|featuring|&|x)\\s+|;") )
        return credits.contains { credit in candidates.contains { artistWords($0) == artistWords(credit) } }
    }

    public static func score(_ candidate: LyricsCandidate, for track: Track) -> Double {
        guard baseTitle(track.title) == baseTitle(candidate.title),
              artistMatches(track.artist, candidates: candidate.artists),
              versions(track.title) == versions(candidate.title) else { return 0 }
        var result = 0.85
        if let duration = candidate.duration, track.duration > 0 {
            let difference = abs(duration - track.duration)
            guard difference <= 3 else { return 0 }
            result += difference <= 2 ? 0.10 : 0.05
        }
        if let album = candidate.album, !track.album.isEmpty, normalized(album) == normalized(track.album) {
            result += 0.05
        }
        return min(result, 1)
    }

    public static func ranked(_ candidates: [LyricsCandidate], for track: Track) -> [LyricsCandidate] {
        candidates.sorted {
            let a = score($0, for: track), b = score($1, for: track)
            if a != b { return a > b }
            if $0.source != $1.source { return $0.source == .genius }
            return $0.id < $1.id
        }
    }

    public static func automaticChoice(_ candidates: [LyricsCandidate], for track: Track) -> LyricsCandidate? {
        let ranked = ranked(candidates, for: track).filter { score($0, for: track) >= 0.85 }
        guard let first = ranked.first else { return nil }
        // Different source records may describe the same edition. Different lyrics at
        // equally good metadata confidence need a choice rather than a silent guess.
        for second in ranked.dropFirst() where score(first, for: track) - score(second, for: track) < 0.025 && first.source == second.source {
            if first.source == .genius { return nil }
            if first.instrumental != second.instrumental { return nil }
            if let a = first.lyrics, let b = second.lyrics,
               normalized(a) != normalized(b) { return nil }
        }
        return first
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let value = regex.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "\u{1f}")
        return value.components(separatedBy: "\u{1f}")
    }
}
