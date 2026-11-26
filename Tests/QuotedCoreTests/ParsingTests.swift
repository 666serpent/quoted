import Testing
@testable import QuotedCore

@Suite(.serialized)
struct ParsingTests {
    @Test func testExtractsOnlyLyricsWithNestedAnnotations() {
        let html = """
        <html><body><h1>Noise Lyrics</h1><div>Contributors and translations</div>
        <div data-lyrics-container="true"><span>[Verse]</span><br/><a href="/annotation">First &amp; quiet line</a><br>
        <div><span>Second &#x1F319; line</span></div><span data-exclude-from-selection="true">Read More</span></div>
        <div>Advertisement</div><div data-lyrics-container='true'>[Chorus]<br>Third &#39;line&#39;<br>Fourth line</div>
        <aside>You might also like</aside></body></html>
        """
        let text = GeniusHTML.lyrics(from: html)
        expectNotNil(text)
        expectTrue(text!.contains("First & quiet line"))
        expectTrue(text!.contains("Second 🌙 line"))
        expectTrue(text!.contains("\n\n[Chorus]\nThird 'line'"))
        for noise in ["Contributors", "Read More", "Advertisement", "You might also like", "Noise Lyrics"] {
            expectFalse(text!.contains(noise), noise)
        }
    }
    @Test func testNoFallbackToWholePage() {
        expectNil(GeniusHTML.lyrics(from: "<html><h1>Access denied</h1><p>Please sign in.</p></html>"))
        expectNil(GeniusHTML.lyrics(from: "<div data-lyrics-container='true'>Empty</div>"))
    }
    @Test func testEntityDecodingAndLRCRemoval() {
        expectEqual(GeniusHTML.decodeEntities("&lt; &#233; &#x1f319; &amp; &#39;"), "< é 🌙 & '")
        expectEqual(GeniusHTML.plainLRC("[ar:An Artist]\n[00:01.22]One line\n[00:02.000]Second line\n[00:03.00]"), "One line\nSecond line")
    }
}
