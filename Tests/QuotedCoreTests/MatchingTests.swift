import Testing
import Foundation
@testable import QuotedCore

@Suite(.serialized)
struct MatchingTests {
    private let track = Track(id: "spotify:track:test", title: "Quiet Light", artist: "The Lanterns", album: "Evening", duration: 200)
    private func candidate(title: String = "Quiet Light", artist: String = "The Lanterns", duration: Double = 200,
                           album: String = "Evening", text: String = "One quiet line\nAnother quiet line", id: String = "lrc:1") -> LyricsCandidate {
        LyricsCandidate(id: id, title: title, artists: [artist], album: album, duration: duration,
            source: .lrclib, url: URL(string: "https://lrclib.net/api/get/1")!, lyrics: text)
    }

    @Test func testExactMetadataWins() {
        let correct = candidate()
        expectEqual(TrackMatcher.score(correct, for: track), 1)
        expectEqual(TrackMatcher.automaticChoice([candidate(artist: "A Cover Band"), correct], for: track)?.id, correct.id)
    }
    @Test func testRejectsSameTitleByDifferentArtist() {
        expectNil(TrackMatcher.automaticChoice([candidate(artist: "A Cover Band")], for: track))
    }
    @Test func testRejectsDifferentWordsAndVersions() {
        for title in ["Quiet Lights", "Quiet Light (Live)", "Quiet Light (Remix)", "Quiet Light - Acoustic", "Quiet Light (Sped Up)", "Quiet Light (Demo)"] {
            expectNil(TrackMatcher.automaticChoice([candidate(title: title)], for: track), title)
        }
    }
    @Test func testRemastersAndFeaturedCreditsAreHarmless() {
        for title in ["Quiet Light - 2011 Remaster", "Quiet Light (Remastered 2020)", "Quiet Light (feat. A Friend)"] {
            expectEqual(TrackMatcher.baseTitle(title), "quiet light", title)
        }
    }
    @Test func testDurationRejectsDifferentRecording() {
        expectNil(TrackMatcher.automaticChoice([candidate(duration: 205)], for: track))
        expectNotNil(TrackMatcher.automaticChoice([candidate(duration: 201.5)], for: track))
    }
    @Test func testAlbumBreaksTie() {
        let wrongAlbum = candidate(album: "A Compilation", text: "Different text entirely", id: "lrc:2")
        expectEqual(TrackMatcher.automaticChoice([wrongAlbum, candidate()], for: track)?.id, "lrc:1")
    }
    @Test func testConflictingTextsRequireManualChoice() {
        expectNil(TrackMatcher.automaticChoice([candidate(), candidate(text: "Two entirely different lines\nNothing alike", id: "lrc:2")], for: track))
    }
    @Test func testEquivalentPunctuationDoesNotCreateAmbiguity() {
        expectNotNil(TrackMatcher.automaticChoice([candidate(), candidate(text: "One quiet line!\nAnother quiet line.", id: "lrc:2")], for: track))
    }
    @Test func testAllTiedRecordsAreCheckedForConflicts() {
        expectNil(TrackMatcher.automaticChoice([candidate(), candidate(id: "lrc:2"), candidate(text: "An entirely different version\nWith different words", id: "lrc:3")], for: track))
    }
    @Test func testUnicodeAndApostrophesNormalize() {
        expectEqual(TrackMatcher.normalized("DON’T — café"), "dont cafe")
        expectEqual(TrackMatcher.normalized("Тихий свет"), "тихий свет")
        expectTrue(TrackMatcher.artistMatches("Radiohead", candidates: ["Radiohead RADIOHEAD"]))
        expectFalse(TrackMatcher.artistMatches("Tyler, The Creator", candidates: ["Tyler"]))
    }
    @Test func testCollaboratorsAndCompleteArtistNames() {
        expectTrue(TrackMatcher.artistMatches("A & B", candidates: ["A", "B"]))
        expectTrue(TrackMatcher.artistMatches("Tyler, The Creator", candidates: ["Tyler, The Creator"]))
        expectFalse(TrackMatcher.artistMatches("The Lanterns", candidates: ["The Lanterns Tribute"]))
    }
    @Test func testSpotifyMillisecondsAndCacheIdentity() {
        expectEqual(Track(id: "a", title: "a", artist: "b", album: "c", duration: 229_123).duration, 229.123)
        expectEqual(track.duration, 200)
        expectNotEqual(track.key, Track(id: track.id, title: track.title, artist: "Another", album: track.album, duration: 200).key)
    }
    @Test func testGeniusURLValidation() {
        expectTrue(LyricsService.validGeniusURL(URL(string: "https://genius.com/Artist-title-lyrics")!))
        for value in ["https://genius.com.evil.example/song-lyrics", "http://genius.com/song-lyrics", "https://genius.com/search", "https://evil.example/song-lyrics", "https://user:pass@genius.com/song-lyrics"] {
            expectFalse(LyricsService.validGeniusURL(URL(string: value)!), value)
        }
    }
}
