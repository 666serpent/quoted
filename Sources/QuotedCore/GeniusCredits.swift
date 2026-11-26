import Foundation

public enum CreditsError: LocalizedError {
    case unavailable
    public var errorDescription: String? { "Credits aren't available for this song on Genius." }
}

enum GeniusCredits {
    static func parse(_ data: Data, for candidate: LyricsCandidate, artworkURL: URL?) throws -> SongCredits {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let response = root?["response"] as? [String: Any]
        guard let song = response?["song"] as? [String: Any],
              let id = song["id"] as? NSNumber, candidate.id == "genius:\(id.stringValue)",
              let title = song["title"] as? String,
              let rawURL = song["url"] as? String, let songURL = URL(string: rawURL),
              LyricsService.validGeniusURL(songURL),
              songURL.path.lowercased() == candidate.url.path.lowercased(),
              TrackMatcher.baseTitle(title) == TrackMatcher.baseTitle(candidate.title) else { throw CreditsError.unavailable }
        let primary = song["primary_artist"] as? [String: Any]
        var rawArtists = song["primary_artists"] as? [[String: Any]] ?? []
        if rawArtists.isEmpty, let primary { rawArtists = [primary] }
        rawArtists += song["featured_artists"] as? [[String: Any]] ?? []
        let names = rawArtists.compactMap { $0["name"] as? String }
        guard candidate.artists.contains(where: { TrackMatcher.artistMatches($0, candidates: names) }) else { throw CreditsError.unavailable }

        let artists = people(rawArtists)
        let producers = people(song["producer_artists"] as? [[String: Any]] ?? [])
        let album = song["album"] as? [String: Any]
        let image = artworkURL ?? httpsURL(album?["cover_art_url"] as? String) ?? httpsURL(song["song_art_image_url"] as? String)
        return SongCredits(title: title, artworkURL: image, artists: artists, producers: producers, songURL: songURL)
    }

    private static func people(_ values: [[String: Any]]) -> [GeniusPerson] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let name = value["name"] as? String, !name.isEmpty,
                  let raw = value["url"] as? String, let url = httpsURL(raw),
                  ["genius.com", "www.genius.com"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                  url.path.lowercased().hasPrefix("/artists/"), seen.insert(url.absoluteString).inserted else { return nil }
            return GeniusPerson(name: name, url: url)
        }
    }

    private static func httpsURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
}
