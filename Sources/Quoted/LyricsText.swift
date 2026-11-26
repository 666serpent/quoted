import SwiftUI

struct LyricsText: View {
    let text: String
    let fontSize: Double
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(styledText)
            .lineSpacing(fontSize * 0.31)
            .textSelection(.disabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var styledText: AttributedString {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result = AttributedString()

        func bodyLine(_ value: String) -> AttributedString {
            var line = AttributedString(value)
            line.font = .system(size: fontSize, weight: .semibold)
            line.foregroundColor = .primary.opacity(0.88)
            line.alignment = .left
            return line
        }

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let label = trimmed.dropFirst().dropLast()
            let isSection = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
                && !label.isEmpty && !label.contains("[") && !label.contains("]")
            if isSection {
                if index > 0 && !lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(bodyLine("\n"))
                }
                var heading = AttributedString(String(label).uppercased() + "\n")
                heading.font = .system(size: min(13, max(10, fontSize * 0.54)), weight: .medium)
                heading.foregroundColor = .primary.opacity(contrast == .increased ? 0.7 : 0.45)
                heading.tracking = 1.6
                heading.alignment = .center
                result.append(heading)
                if index + 1 < lines.count && !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                    var space = bodyLine("\n")
                    space.font = .system(size: fontSize * 0.3)
                    result.append(space)
                }
            } else {
                result.append(bodyLine(rawLine + (index == lines.count - 1 ? "" : "\n")))
            }
        }
        return result
    }
}
