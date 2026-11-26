import Foundation
import Testing
@testable import QuotedCore

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct ServiceTests {
    private let track = Track(id: "spotify:track:test", title: "Quiet Light", artist: "The Lanterns", album: "Evening", duration: 200)
    private let record = #"{"id":1,"trackName":"Quiet Light","artistName":"The Lanterns","albumName":"Evening","duration":200,"instrumental":false,"plainLyrics":"One quiet line\nAnother quiet line","syncedLyrics":null}"#
    private func service() -> LyricsService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return LyricsService(session: URLSession(configuration: config))
    }

    @Test func testGeniusBlockedFallsBackToVerifiedLRCLIB() async throws {
        var geniusCalls = 0
        MockProtocol.handler = { [record] request in
            expectTrue(request.value(forHTTPHeaderField: "User-Agent")!.contains("Quoted"))
            if request.url!.host == "genius.com" { geniusCalls += 1; return (403, [:], Data()) }
            return (200, [:], Data(record.utf8))
        }
        let service = service()
        let first = try await service.search(for: track)
        expectEqual(first.document?.candidate.source, .lrclib)
        expectEqual(first.document?.text, "One quiet line\nAnother quiet line")
        expectTrue(first.notice!.contains("Genius is unavailable"))
        _ = try await service.search(for: track)
        expectEqual(geniusCalls, 1, "Respect Genius's denial instead of repeatedly requesting it")
    }
    @Test func testGeniusSuccessUsesOnlyMatchedSongPage() async throws {
        MockProtocol.handler = { request in
            if request.url!.path.hasPrefix("/api/") {
                let json = #"{"response":{"sections":[{"hits":[{"result":{"id":12,"title":"Quiet Light","primary_artist":{"name":"The Lanterns"},"url":"https://genius.com/The-lanterns-quiet-light-lyrics"}}]}]}}"#
                return (200, [:], Data(json.utf8))
            }
            expectEqual(request.url!.path, "/The-lanterns-quiet-light-lyrics")
            return (200, [:], Data(#"<div data-lyrics-container="true">One quiet line<br>Another quiet line</div>"#.utf8))
        }
        let result = try await service().search(for: track)
        expectEqual(result.document?.candidate.source, .genius)
        expectEqual(result.document?.text, "One quiet line\nAnother quiet line")
    }
    @Test func testMismatchedExactRecordDoesNotAutoDisplay() async throws {
        MockProtocol.handler = { [record] request in
            if request.url!.host == "genius.com" { return (403, [:], Data()) }
            if request.url!.path == "/api/get" { return (200, [:], Data(record.replacingOccurrences(of: "The Lanterns", with: "Wrong Artist").utf8)) }
            return (200, [:], Data("[]".utf8))
        }
        let result = try await service().search(for: track)
        expectNil(result.document)
    }
    @Test func testRateLimitHonoredWithoutRepeatedRequests() async throws {
        var calls = 0
        MockProtocol.handler = { request in
            if request.url!.host == "genius.com" { return (403, [:], Data()) }
            calls += 1
            return (429, ["Retry-After": "120"], Data())
        }
        let service = service()
        for _ in 0..<2 {
            do { _ = try await service.search(for: track); Issue.record("Expected rate limit") }
            catch LyricsError.rateLimited(let deadline) { expectGreaterThan(deadline.timeIntervalSinceNow, 115) }
        }
        expectEqual(calls, 1)
    }
    @Test func testInstrumentalIsReportedExplicitly() async throws {
        MockProtocol.handler = { [record] request in
            if request.url!.host == "genius.com" { return (403, [:], Data()) }
            return (200, [:], Data(record.replacingOccurrences(of: "\"instrumental\":false", with: "\"instrumental\":true").utf8))
        }
        let result = try await service().search(for: track)
        expectEqual(result.document?.text, "This track is instrumental.")
    }
    @Test func testCreditsUseMatchedIDAndAreCached() async throws {
        var calls = 0
        MockProtocol.handler = { request in
            calls += 1
            expectEqual(request.url!.path, "/api/songs/12")
            let json = #"{"response":{"song":{"id":12,"title":"Quiet Light","url":"https://genius.com/The-lanterns-quiet-light-lyrics","primary_artist":{"name":"The Lanterns","url":"https://genius.com/artists/The-lanterns"},"featured_artists":[],"producer_artists":[{"name":"A Producer","url":"https://genius.com/artists/A-producer"}],"song_art_image_url":"https://images.genius.com/cover.jpg"}}}"#
            return (200, [:], Data(json.utf8))
        }
        let candidate = LyricsCandidate(id: "genius:12", title: track.title, artists: [track.artist], source: .genius,
            url: URL(string: "https://genius.com/The-lanterns-quiet-light-lyrics")!)
        let service = service()
        let credits = try await service.credits(for: track, candidate: candidate)
        expectEqual(credits.producers.first?.name, "A Producer")
        _ = try await service.credits(for: track, candidate: candidate)
        expectEqual(calls, 1)
    }
}

@Suite(.serialized)
struct LiveServiceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QUOTED_LIVE_TEST"] == "1"))
    func testRealTrackWithoutPrintingLyrics() async throws {
        let track = Track(id: "spotify:track:live-check", title: "No Surprises", artist: "Radiohead", album: "OK Computer", duration: 229)
        let service = LyricsService()
        let result = try await service.search(for: track)
        expectNotNil(result.document)
        expectEqual(result.document?.candidate.title, "No Surprises")
        expectGreaterThan(result.document?.text.count ?? 0, 100)
        for noise in ["Contributors", "You might also like", "Read More", "Translations"] {
            expectFalse(result.document!.text.contains(noise), "Page chrome leaked into lyrics: \(noise)")
        }
        print("Live match: \(result.document!.candidate.source.rawValue), \(result.document!.candidate.id), \(result.document!.text.count) characters (text omitted)")
        let credits = try await service.credits(for: track, candidate: result.document?.candidate)
        expectTrue(credits.artists.contains { $0.name == "Radiohead" })
        expectTrue(credits.producers.contains { $0.name == "Nigel Godrich" })
        expectTrue(credits.producers.allSatisfy { $0.url.host == "genius.com" && $0.url.path.hasPrefix("/artists/") })
        print("Live credits: \(credits.artists.map(\.name)), producers: \(credits.producers.map(\.name))")
    }
}
