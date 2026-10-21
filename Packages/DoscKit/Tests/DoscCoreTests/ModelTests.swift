import Foundation
import Testing

@testable import DoscCore

@Suite struct ModelTests {
    @Test func repoRefSplitsOwnerAndName() {
        #expect(RepoRef(path: "apple/swift").owner == "apple")
        #expect(RepoRef(path: "group/sub/project").owner == "group/sub")
        #expect(RepoRef(path: "group/sub/project").name == "project")
        #expect(RepoRef(path: "trunk").owner == "")
        #expect(RepoRef(owner: "a", name: "b").path == "a/b")
    }

    @Test func commitTitleBodyAndShortID() {
        let c = Commit(
            id: "0123456789abcdef0123456789abcdef01234567", message: "Fix crash\n\nDetails here\n",
            author: Signature(name: "A"))
        #expect(c.title == "Fix crash")
        #expect(c.body == "Details here")
        #expect(c.shortID == "0123456")
        let svn = Commit(id: "1234", message: "one line", author: Signature(name: "A"))
        #expect(svn.body == nil)
        #expect(svn.shortID == "1234")
    }

    @Test func fileContentDetectsBinaryAndImages() {
        #expect(FileContent(path: "a.txt", data: Data("hi".utf8)).isBinary == false)
        #expect(FileContent(path: "a.bin", data: Data([0x41, 0x00, 0x42])).isBinary)
        #expect(FileContent(path: "a.bin", data: Data([0xff, 0xfe, 0xfd])).isBinary)
        #expect(FileContent(path: "dir/Logo.PNG", data: Data()).isImage)
        #expect(FileContent(path: "dir/Logo.PNG", data: Data()).name == "Logo.PNG")
    }

    @Test func accountLabelIncludesHostForSelfHosted() {
        let gh = Account(kind: .github, host: URL(string: "https://github.com")!, login: "octo")
        let ghe = Account(kind: .github, host: URL(string: "https://git.corp.example")!, login: "octo")
        #expect(gh.label == "octo")
        #expect(ghe.label == "octo@git.corp.example")
    }

    @Test func providerErrorsHaveMessages() {
        for error in [ProviderError.unauthorized, .notFound, .rateLimited(resetAt: nil), .unsupported] {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
