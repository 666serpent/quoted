import Foundation

public enum LyricsError: LocalizedError {
    case http(Int), unavailable, invalidURL, emptyLyrics, rateLimited(Date)
    public var errorDescription: String? {
        switch self {
        case .http(let code): return "The lyrics service returned \(code). Try again in a moment."
        case .unavailable: return "Couldn't reach the lyrics service. Check your connection and try again."
        case .invalidURL: return "Use a Genius song link ending in -lyrics."
        case .emptyLyrics: return "This page didn't provide readable lyrics. Try another match."
        case .rateLimited: return "The lyrics service needs a little time. Please try again later."
        }
    }
}

public actor LyricsService {
    private let session: URLSession
    private var retryAfter: [String: Date] = [:]
    private var lastRequest: [String: Date] = [:]
    private var creditsCache: [String: SongCredits] = [:]

    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 16
            self.session = URLSession(configuration: configuration)
        }
    }

    public func search(for track: Track) async throws -> SearchOutcome {
        var candidates: [LyricsCandidate] = []
        var geniusUnavailable = false
        do {
            let genius = try await searchGenius(track)
            candidates += genius
            if let candidate = TrackMatcher.automaticChoice(genius, for: track) {
                do {
                    let text = try await text(for: candidate)
                    return SearchOutcome(candidates: candidates, document: LyricsDocument(candidate: candidate, text: text))
                } catch { try Task.checkCancellation(); geniusUnavailable = true }
            }
        } catch { try Task.checkCancellation(); geniusUnavailable = true }

        try Task.checkCancellation()
        do {
            let records = try await searchLRCLIB(track)
            candidates += records
            if let candidate = TrackMatcher.automaticChoice(records, for: track) {
                let text = candidate.instrumental ? "This track is instrumental." : (candidate.lyrics ?? "")
                if !text.isEmpty {
                    return SearchOutcome(candidates: TrackMatcher.ranked(candidates, for: track),
                        document: LyricsDocument(candidate: candidate, text: text),
                        notice: geniusUnavailable ? "Genius is unavailable. These lyrics are from LRCLIB." : nil)
                }
            }
        } catch {
            try Task.checkCancellation()
            if candidates.isEmpty { throw error }
        }
        return SearchOutcome(candidates: TrackMatcher.ranked(candidates, for: track),
            notice: candidates.isEmpty ? "No matching lyrics yet. You can try again or search on Genius." : "Choose the right recording to read its lyrics.")
    }

    public func text(for candidate: LyricsCandidate) async throws -> String {
        if candidate.instrumental { return "This track is instrumental." }
        if let text = candidate.lyrics, !text.isEmpty { return text }
        guard candidate.source == .genius, Self.validGeniusURL(candidate.url) else { throw LyricsError.invalidURL }
        let (data, response) = try await request(candidate.url)
        guard let finalURL = response.url, Self.validGeniusURL(finalURL),
              Self.canonicalPath(finalURL) == Self.canonicalPath(candidate.url) else { throw LyricsError.invalidURL }
        guard let html = String(data: data, encoding: .utf8), let lyrics = GeniusHTML.lyrics(from: html) else { throw LyricsError.emptyLyrics }
        return lyrics
    }

    public func credits(for track: Track, candidate: LyricsCandidate? = nil) async throws -> SongCredits {
        let reference: LyricsCandidate
        if let candidate, candidate.source == .genius, candidate.id.hasPrefix("genius:"),
           Int(candidate.id.dropFirst(7)) != nil, Self.validGeniusURL(candidate.url) {
            reference = candidate
        } else {
            let results = try await searchGenius(track)
            guard let found = TrackMatcher.automaticChoice(results, for: track) else { throw CreditsError.unavailable }
            reference = found
        }
        if let cached = creditsCache[reference.id] { return cached }
        let id = String(reference.id.dropFirst(7))
        let url = makeURL("https://genius.com/api/songs/\(id)", ["text_format": "plain"])
        let (data, _) = try await request(url)
        let credits = try GeniusCredits.parse(data, for: reference, artworkURL: nil)
        if creditsCache.count >= 40, let first = creditsCache.keys.first { creditsCache.removeValue(forKey: first) }
        creditsCache[reference.id] = credits
        return credits
    }

    public static func validGeniusURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["genius.com", "www.genius.com"].contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && url.path.lowercased().hasSuffix("-lyrics")
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
    }

    private func searchGenius(_ track: Track) async throws -> [LyricsCandidate] {
        let url = makeURL("https://genius.com/api/search/song", ["q": "\(track.artist) \(TrackMatcher.baseTitle(track.title))", "per_page": "10"])
        let (data, _) = try await request(url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let response = root?["response"] as? [String: Any]
        let sections = response?["sections"] as? [[String: Any]] ?? []
        var hits = sections.flatMap { $0["hits"] as? [[String: Any]] ?? [] }
        hits += response?["hits"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return hits.compactMap { hit in
            guard let result = hit["result"] as? [String: Any],
                  let rawID = result["id"] as? NSNumber,
                  let title = result["title"] as? String,
                  let rawURL = result["url"] as? String, let url = URL(string: rawURL),
                  Self.validGeniusURL(url), seen.insert(rawID.stringValue).inserted else { return nil }
            let primary = result["primary_artist"] as? [String: Any]
            var artists = (result["primary_artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            if artists.isEmpty, let name = primary?["name"] as? String { artists = [name] }
            let featured = (result["featured_artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            artists += featured
            guard !artists.isEmpty else { return nil }
            // Translation/romanization pages are separate texts, not the original lyrics.
            guard !artists.contains(where: { $0.lowercased().hasPrefix("genius ") }),
                  !title.lowercased().contains("translation"), !title.lowercased().contains("romanization") else { return nil }
            return LyricsCandidate(id: "genius:\(rawID)", title: title, artists: artists, source: .genius, url: url)
        }
    }

    private func searchLRCLIB(_ track: Track) async throws -> [LyricsCandidate] {
        if track.duration > 0 && track.duration <= 3600 && !track.album.isEmpty {
            let url = makeURL("https://lrclib.net/api/get", ["track_name": track.title, "artist_name": track.artist,
                "album_name": track.album, "duration": String(Int(track.duration.rounded()))])
            do {
                let (data, _) = try await request(url)
                let record = try JSONDecoder().decode(LRCRecord.self, from: data)
                let candidate = record.candidate
                if TrackMatcher.score(candidate, for: track) >= 0.95,
                   candidate.instrumental || candidate.lyrics?.isEmpty == false { return [candidate] }
            } catch LyricsError.http(404) { /* Search the catalog next. */ }
        }
        let url = makeURL("https://lrclib.net/api/search", ["track_name": TrackMatcher.baseTitle(track.title), "artist_name": track.artist])
        let (data, _) = try await request(url)
        return try JSONDecoder().decode([LRCRecord].self, from: data).map(\.candidate)
            .filter { $0.instrumental || $0.lyrics?.isEmpty == false }
    }

    private func makeURL(_ base: String, _ query: [String: String]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func request(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let host = url.host ?? ""
        if let deadline = retryAfter[host], deadline > Date() { throw LyricsError.rateLimited(deadline) }
        if let last = lastRequest[host] {
            let delay = 0.25 - Date().timeIntervalSince(last)
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        }
        try Task.checkCancellation()
        lastRequest[host] = Date()
        var request = URLRequest(url: url)
        request.setValue("Quoted/1.1.0 (personal macOS reader; https://lrclib.net)", forHTTPHeaderField: "User-Agent")
        request.setValue(url.path.hasPrefix("/api/") ? "application/json" : "text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw LyricsError.unavailable }
        if response.statusCode == 429 || response.statusCode == 503 {
            let raw = response.value(forHTTPHeaderField: "Retry-After") ?? "60"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let seconds = Double(raw) ?? formatter.date(from: raw)?.timeIntervalSinceNow ?? 60
            let deadline = Date().addingTimeInterval(max(1, seconds) + Double.random(in: 0...1))
            retryAfter[host] = deadline
            throw LyricsError.rateLimited(deadline)
        }
        if response.statusCode == 403 { retryAfter[host] = Date().addingTimeInterval(900) }
        guard (200...299).contains(response.statusCode) else { throw LyricsError.http(response.statusCode) }
        guard data.count <= 12_000_000 else { throw LyricsError.emptyLyrics }
        return (data, response)
    }
}

private struct LRCRecord: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    var candidate: LyricsCandidate {
        let plain = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (plain?.isEmpty == false) ? plain : syncedLyrics.map(GeniusHTML.plainLRC)
        return LyricsCandidate(id: "lrclib:\(id)", title: trackName, artists: [artistName],
            album: albumName, duration: duration, source: .lrclib,
            url: URL(string: "https://lrclib.net/api/get/\(id)")!, lyrics: text, instrumental: instrumental)
    }
}
