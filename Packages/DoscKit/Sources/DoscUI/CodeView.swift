import HighlightSwift
import MarkdownUI
import SwiftUI

/// Source code with line numbers and syntax highlighting (highlight.js, GitHub theme). Files over
/// ``highlightLimit`` bytes are shown plain, because highlighting them would stall the phone.
public struct CodeView: View {
    let text: String
    let fileName: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString?

    public static let highlightLimit = 150_000

    public init(text: String, fileName: String) {
        self.text = text
        self.fileName = fileName
    }

    public var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                Text((1...max(lines, 1)).map(String.init).joined(separator: "\n"))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Palette.fgMuted)
                    .padding(.horizontal, 8)
                    .background(Palette.canvasSubtle)
                Group {
                    if let highlighted {
                        Text(highlighted)
                    } else {
                        Text(text).foregroundStyle(Palette.fgDefault)
                    }
                }
                .padding(.horizontal, 8)
                .textSelection(.enabled)
            }
            .font(.system(.footnote, design: .monospaced))
            .padding(.vertical, 8)
        }
        .background(Palette.canvasDefault)
        .task(id: colorScheme) { await highlight() }
    }

    private func highlight() async {
        guard text.utf8.count <= Self.highlightLimit else { return }
        let colors: HighlightColors = colorScheme == .dark ? .dark(.github) : .light(.github)
        let highlighter = Highlight()
        let ext = (fileName as NSString).pathExtension.lowercased()
        let alias = Self.languageAliases[ext] ?? ext
        do {
            if alias.isEmpty {
                highlighted = try await highlighter.attributedText(text, colors: colors)
            } else {
                highlighted = try await highlighter.request(text, mode: .languageAlias(alias), colors: colors)
                    .attributedText
            }
        } catch {
            highlighted = nil
        }
    }

    /// Extensions highlight.js doesn't know as aliases.
    static let languageAliases: [String: String] = [
        "h": "objectivec", "m": "objectivec", "mm": "objectivec", "kt": "kotlin", "kts": "kotlin",
        "gradle": "groovy", "yml": "yaml", "toml": "ini", "plist": "xml", "storyboard": "xml",
        "xib": "xml", "csproj": "xml", "sln": "plaintext", "txt": "plaintext", "lock": "plaintext",
        "podspec": "ruby", "gemspec": "ruby", "rake": "ruby", "vue": "xml", "svelte": "xml",
    ]
}

/// Markdown rendered like GitHub renders READMEs and comments.
public struct MarkdownText: View {
    let markdown: String
    /// Resolves relative links and images, e.g. the repository's raw URL for README images.
    let baseURL: URL?

    public init(_ markdown: String, baseURL: URL? = nil) {
        self.markdown = markdown
        self.baseURL = baseURL
    }

    public var body: some View {
        Markdown(markdown, baseURL: baseURL, imageBaseURL: baseURL)
            .markdownTheme(.gitHub)
            .textSelection(.enabled)
    }
}
