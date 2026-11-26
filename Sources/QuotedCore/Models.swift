import Foundation

public struct Track: Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let artworkURL: URL?

    public init(id: String, title: String, artist: String, album: String, duration: Double, artworkURL: URL? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        // Spotify's dictionary says seconds; desktop builds also report milliseconds.
        self.duration = duration > 10_000 ? duration / 1000 : duration
        self.artworkURL = artworkURL?.scheme == "https" ? artworkURL : nil
    }

    public var key: String { [id, title, artist, album, String(Int(duration.rounded()))].joined(separator: "\u{1f}") }
}

public struct GeniusPerson: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL
    public var id: String { url.absoluteString }
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

public struct SongCredits: Sendable {
    public let title: String
    public let artworkURL: URL?
    public let artists: [GeniusPerson]
    public let producers: [GeniusPerson]
    public let songURL: URL
    public init(title: String, artworkURL: URL?, artists: [GeniusPerson], producers: [GeniusPerson], songURL: URL) {
        self.title = title; self.artworkURL = artworkURL; self.artists = artists
        self.producers = producers; self.songURL = songURL
    }
}

public enum LyricsSource: String, Codable, Sendable {
    case genius = "Genius"
    case lrclib = "LRCLIB"
}

public struct LyricsCandidate: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let duration: Double?
    public let source: LyricsSource
    public let url: URL
    public let lyrics: String?
    public let instrumental: Bool

    public init(id: String, title: String, artists: [String], album: String? = nil,
                duration: Double? = nil, source: LyricsSource, url: URL,
                lyrics: String? = nil, instrumental: Bool = false) {
        self.id = id; self.title = title; self.artists = artists; self.album = album
        self.duration = duration; self.source = source; self.url = url
        self.lyrics = lyrics; self.instrumental = instrumental
    }

    public var artist: String { artists.joined(separator: ", ") }
}

public struct LyricsDocument: Codable, Sendable {
    public let candidate: LyricsCandidate
    public let text: String
    public let manuallyChosen: Bool

    public init(candidate: LyricsCandidate, text: String, manuallyChosen: Bool = false) {
        self.candidate = candidate; self.text = text; self.manuallyChosen = manuallyChosen
    }
}

public struct SearchOutcome: Sendable {
    public var candidates: [LyricsCandidate]
    public var document: LyricsDocument?
    public var notice: String?
    public init(candidates: [LyricsCandidate], document: LyricsDocument? = nil, notice: String? = nil) {
        self.candidates = candidates; self.document = document; self.notice = notice
    }
}
