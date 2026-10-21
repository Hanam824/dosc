import DoscCore
import DoscUI
import SwiftUI

/// One directory of a repository.
struct TreeView: View {
    let target: RepoTarget
    let provider: any SourceControlProvider
    let path: String
    let revision: String?
    @State private var entries = Loader<[FileEntry]>()

    var body: some View {
        LoaderView(loader: entries, retry: load) { entries in
            List(entries) { entry in
                NavigationLink(value: route(for: entry)) {
                    SwiftUI.Label {
                        Text(entry.name)
                    } icon: {
                        Image(systemName: icon(for: entry))
                            .foregroundStyle(entry.kind == .directory ? Palette.accent : Palette.fgMuted)
                    }
                }
                .disabled(entry.kind == .submodule)
            }
            .listStyle(.plain)
            .refreshable { await load() }
            .overlay {
                if entries.isEmpty { MessageView(systemImage: "folder", title: "Empty folder") }
            }
        }
        .inlineTitle(path.isEmpty ? target.repo.name : (path as NSString).lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.commits(target, revision: revision, path: path.isEmpty ? nil : path)) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
        }
        .task { await load() }
    }

    private func route(for entry: FileEntry) -> Route {
        entry.kind == .directory
            ? .tree(target, path: entry.path, revision: revision)
            : .file(target, path: entry.path, revision: revision)
    }

    private func icon(for entry: FileEntry) -> String {
        switch entry.kind {
        case .directory: "folder.fill"
        case .symlink: "arrow.turn.up.right"
        case .submodule: "shippingbox"
        case .file: "doc"
        }
    }

    private func load() async {
        let (provider, repo, path, revision) = (provider, target.repo, path, revision)
        await entries.load { try await provider.contents(repo, path: path, revision: revision) }
    }
}

/// One file: highlighted code, rendered Markdown, an image, or a note for binaries.
struct FileView: View {
    let target: RepoTarget
    let provider: any SourceControlProvider
    let path: String
    let revision: String?
    @State private var file = Loader<FileContent>()
    @State private var showsRenderedMarkdown = true

    /// Bigger files are not shown, to keep memory in check.
    static let displayLimit = 2_000_000

    private var isMarkdown: Bool {
        ["md", "markdown", "mdown"].contains((path as NSString).pathExtension.lowercased())
    }

    var body: some View {
        LoaderView(loader: file, retry: load) { file in
            content(file)
        }
        .inlineTitle((path as NSString).lastPathComponent)
        .toolbar {
            if isMarkdown {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsRenderedMarkdown.toggle()
                    } label: {
                        Image(
                            systemName: showsRenderedMarkdown
                                ? "chevron.left.forwardslash.chevron.right" : "doc.richtext")
                    }
                    .accessibilityLabel(showsRenderedMarkdown ? "Show source" : "Show preview")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.commits(target, revision: revision, path: path)) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
            if let url = file.value?.webURL {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ file: FileContent) -> some View {
        if file.data.count > Self.displayLimit {
            MessageView(
                systemImage: "doc.badge.ellipsis", title: "File too large",
                message:
                    "\(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file)) is too big to show here."
            )
        } else if file.isImage, let image = platformImage(file.data) {
            ScrollView([.horizontal, .vertical]) { image.padding() }
        } else if file.isBinary {
            MessageView(
                systemImage: "doc.zipper", title: "Binary file",
                message: ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
        } else if isMarkdown && showsRenderedMarkdown, let text = file.text {
            ScrollView { MarkdownText(text, baseURL: file.assetBaseURL).padding() }
        } else {
            CodeView(text: file.text ?? "", fileName: file.name)
        }
    }

    private func platformImage(_ data: Data) -> Image? {
        #if canImport(UIKit)
            UIImage(data: data).map { Image(uiImage: $0) }
        #else
            NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }

    private func load() async {
        let (provider, repo, path, revision) = (provider, target.repo, path, revision)
        await file.load { try await provider.file(repo, path: path, revision: revision) }
    }
}
