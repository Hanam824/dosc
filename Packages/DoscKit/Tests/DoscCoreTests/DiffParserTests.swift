import Testing

@testable import DoscCore

@Suite struct DiffParserTests {
    @Test func parsesHunksWithLineNumbers() {
        let patch = """
            @@ -1,3 +1,4 @@ struct A
             let a = 1
            -let b = 2
            +let b = 3
            +let c = 4
             let d = 5
            @@ -10,2 +11,2 @@
             x
            -y
            \\ No newline at end of file
            +z
            """
        let hunks = UnifiedDiffParser.parseHunks(patch)
        #expect(hunks.count == 2)
        #expect(hunks[0].header == "@@ -1,3 +1,4 @@ struct A")
        #expect(hunks[0].lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context])
        #expect(hunks[0].lines[1].oldNumber == 2 && hunks[0].lines[1].newNumber == nil)
        #expect(hunks[0].lines[3].newNumber == 3 && hunks[0].lines[3].text == "let c = 4")
        #expect(hunks[0].lines[4].oldNumber == 3 && hunks[0].lines[4].newNumber == 4)
        #expect(hunks[1].oldStart == 10 && hunks[1].newStart == 11)
        #expect(hunks[1].lines.map(\.kind) == [.context, .deletion, .noNewline, .addition])
        #expect(hunks[1].lines[3].newNumber == 12)
    }

    @Test func skipsFileHeadersAndSingleLineCounts() {
        let patch = """
            diff --git a/f b/f
            --- a/f
            +++ b/f
            @@ -0,0 +1 @@
            +hello
            """
        let hunks = UnifiedDiffParser.parseHunks(patch)
        #expect(hunks.count == 1)
        #expect(hunks[0].newStart == 1)
        #expect(hunks[0].lines == [DiffLine(kind: .addition, text: "hello", oldNumber: nil, newNumber: 1)])
    }

    @Test func malformedHeaderStopsParsing() {
        #expect(UnifiedDiffParser.parseHunks("@@ nonsense @@\n+x").isEmpty)
        #expect(UnifiedDiffParser.parseHunks("").isEmpty)
    }

    @Test func handlesCRLF() {
        let hunks = UnifiedDiffParser.parseHunks("@@ -1 +1 @@\r\n-a\r\n+b\r\n")
        #expect(hunks.first?.lines.map(\.text) == ["a", "b"])
    }
}
