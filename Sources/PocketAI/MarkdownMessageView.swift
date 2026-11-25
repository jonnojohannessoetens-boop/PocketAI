import SwiftUI
import UIKit

struct MarkdownMessageView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parse(markdown)) { block in
                switch block.content {
                case .text(let value):
                    if let attributed = try? AttributedString(markdown: value) {
                        Text(attributed)
                            .textSelection(.enabled)
                    } else {
                        Text(value).textSelection(.enabled)
                    }
                case .code(let language, let source):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(language.isEmpty ? "Code" : language.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = source
                            } label: {
                                Label("Kopiëren", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("Code kopiëren")
                        }
                        ScrollView(.horizontal) {
                            Text(source)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private struct Block: Identifiable {
        enum Content { case text(String), code(language: String, source: String) }
        let id = UUID()
        let content: Content
    }

    private func parse(_ source: String) -> [Block] {
        let pattern = "```([^\\n`]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [Block(content: .text(source))]
        }
        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        guard !matches.isEmpty else { return [Block(content: .text(source))] }

        var result: [Block] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let preceding = nsSource.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if !preceding.isEmpty { result.append(Block(content: .text(preceding))) }
            }
            let language = nsSource.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let code = nsSource.substring(with: match.range(at: 2)).trimmingCharacters(in: .newlines)
            result.append(Block(content: .code(language: language, source: code)))
            cursor = NSMaxRange(match.range)
        }
        if cursor < nsSource.length {
            result.append(Block(content: .text(nsSource.substring(from: cursor))))
        }
        return result
    }
}
