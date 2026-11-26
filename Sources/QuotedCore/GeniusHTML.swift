import Foundation

/// Extract only Genius's marked lyric containers, never the page's surrounding prose.
public enum GeniusHTML {
    public static func lyrics(from html: String) -> String? {
        guard let tokens = try? NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|<[^>]+>|[^<]+") else { return nil }
        var stack: [(name: String, container: Bool, excluded: Bool)] = []
        var parts: [String] = []
        var current = ""
        var active = false
        let voids: Set<String> = ["br", "hr", "img", "meta", "link", "input", "wbr", "source", "area", "base", "embed", "param", "track", "col"]
        for match in tokens.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let token = String(html[range])
            if token.hasPrefix("<!--") { continue }
            if token.hasPrefix("<") {
                let lower = token.lowercased()
                guard let nameRange = lower.range(of: "(?<=<)/?[a-z][a-z0-9:-]*", options: .regularExpression) else { continue }
                let rawName = String(lower[nameRange]); let name = rawName.replacingOccurrences(of: "/", with: "")
                if rawName.hasPrefix("/") {
                    if let index = stack.lastIndex(where: { $0.name == name }) {
                        let removed = stack[index...]
                        let closesLyrics = removed.contains(where: { $0.container })
                        stack.removeSubrange(index...)
                        if closesLyrics && active {
                            parts.append(current); current = ""; active = false
                        }
                    }
                    continue
                }
                let container = lower.range(of: "data-lyrics-container\\s*=\\s*[\"']true[\"']", options: .regularExpression) != nil
                let excluded = ["script", "style", "noscript", "button"].contains(name)
                    || lower.contains("data-exclude-from-selection") || lower.contains("lyricsheader")
                if container && !active { active = true; current = "" }
                let blocked = excluded || stack.contains(where: { $0.excluded })
                if active && name == "br" && !blocked { current += "\n" }
                if !voids.contains(name) && !lower.hasSuffix("/>") {
                    stack.append((name, container, excluded))
                }
            } else if active && !stack.contains(where: { $0.excluded }) {
                current += decodeEntities(token)
            }
        }
        if active { parts.append(current) }
        let text = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\n{4,}", with: "\n\n\n", options: .regularExpression)
        guard text.count >= 8, text.contains("\n") else { return nil }
        return text
    }

    public static func decodeEntities(_ string: String) -> String {
        let named: [String: String] = ["amp":"&", "lt":"<", "gt":">", "quot":"\"", "apos":"'", "nbsp":" ",
            "rsquo":"’", "lsquo":"‘", "rdquo":"”", "ldquo":"“", "ndash":"–", "mdash":"—", "hellip":"…",
            "eacute":"é", "Eacute":"É", "ouml":"ö", "uuml":"ü", "auml":"ä", "copy":"©", "trade":"™"]
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return string }
        var result = string
        for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: string), let range = Range(match.range, in: result) else { continue }
            let key = String(string[keyRange])
            let replacement: String?
            if key.hasPrefix("#x"), let code = UInt32(key.dropFirst(2), radix: 16), let scalar = UnicodeScalar(code) { replacement = String(scalar) }
            else if key.hasPrefix("#"), let code = UInt32(key.dropFirst()), let scalar = UnicodeScalar(code) { replacement = String(scalar) }
            else { replacement = named[key] }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    public static func plainLRC(_ lrc: String) -> String {
        lrc.components(separatedBy: .newlines).compactMap { line in
            if line.range(of: "^\\[(?:ar|al|ti|by|offset|re|ve):", options: .regularExpression) != nil { return nil }
            return line.replacingOccurrences(of: "\\[\\d{1,3}:\\d{2}(?:[.:]\\d+)?\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
