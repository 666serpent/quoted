import Foundation
import Testing
@testable import QuotedCore

@Suite
struct CreditsParsingTests {
    private var candidate: LyricsCandidate {
        LyricsCandidate(id: "genius:12", title: "Quiet Light", artists: ["The Lanterns"], source: .genius,
            url: URL(string: "https://genius.com/The-lanterns-quiet-light-lyrics")!)
    }
    private var song: [String: Any] {
        ["id": 12, "title": "Quiet Light", "url": candidate.url.absoluteString,
         "primary_artist": ["name": "The Lanterns", "url": "https://genius.com/artists/The-lanterns"],
         "featured_artists": [["name": "A Friend", "url": "https://genius.com/artists/A-friend"]],
         "producer_artists": [["name": "A Producer", "url": "https://genius.com/artists/A-producer"]],
         "song_art_image_url": "https://images.genius.com/song.jpg",
         "album": ["cover_art_url": "https://images.genius.com/album.jpg"]]
    }
    private func data(_ song: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["response": ["song": song]])
    }
    @Test func profilesAndArtworkComeFromMatchedSong() throws {
        let credits = try GeniusCredits.parse(data(song), for: candidate, artworkURL: nil)
        #expect(credits.artists.map(\.name) == ["The Lanterns", "A Friend"])
        #expect(credits.producers.map(\.name) == ["A Producer"])
        #expect(credits.producers.first?.url.absoluteString == "https://genius.com/artists/A-producer")
        #expect(credits.artworkURL?.absoluteString == "https://images.genius.com/album.jpg")
    }
    @Test func missingProducersStayEmpty() throws {
        var raw = song; raw["producer_artists"] = []
        let credits = try GeniusCredits.parse(data(raw), for: candidate, artworkURL: nil)
        #expect(credits.producers.isEmpty)
        #expect(!credits.artists.isEmpty)
    }
    @Test func incorrectSongOrArtistIsRejected() throws {
        for field in ["id", "title", "primary_artist", "url"] {
            var raw = song
            switch field {
            case "id": raw[field] = 13
            case "title": raw[field] = "Another Song"
            case "primary_artist": raw[field] = ["name": "Wrong Band", "url": "https://genius.com/artists/Wrong-band"]
            default: raw[field] = "https://genius.com/Another-song-lyrics"
            }
            #expect(throws: CreditsError.self) { try GeniusCredits.parse(data(raw), for: candidate, artworkURL: nil) }
        }
    }
    @Test func invalidProfileLinksAreNotMadeClickable() throws {
        var raw = song
        raw["producer_artists"] = [["name": "Unsafe", "url": "https://genius.com.evil.example/artists/Unsafe"],
            ["name": "Wrong path", "url": "https://genius.com/search?q=producer"],
            ["name": "Real Producer", "url": "https://genius.com/artists/Real-producer"],
            ["name": "Real Producer", "url": "https://genius.com/artists/Real-producer"]]
        let credits = try GeniusCredits.parse(data(raw), for: candidate, artworkURL: nil)
        #expect(credits.producers.map(\.name) == ["Real Producer"])
    }
}
