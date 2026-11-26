import AppKit
import Combine
import QuotedCore

@MainActor
final class ReaderModel: ObservableObject {
    enum Phase: Equatable { case welcome, waiting, loading, reading, choose, permission, failed }
    @Published var phase: Phase = .welcome
    @Published var track: Track?
    @Published var document: LyricsDocument?
    @Published var candidates: [LyricsCandidate] = []
    @Published var message = ""
    @Published var playing = false
    @Published var showChooser = false
    @Published var showLinkEntry = false
    @Published var linkText = ""
    @Published var choosingID: String?
    @Published var chooserError: String?
    @Published var showCredits = false
    @Published var credits: SongCredits?
    @Published var creditsLoading = false
    @Published var creditsError: String?
    @Published var fontSize: Double = UserDefaults.standard.double(forKey: "fontSize") == 0 ? 26 : UserDefaults.standard.double(forKey: "fontSize")
    @Published var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "dark"

    let service = LyricsService()
    private let spotify = SpotifyReader()
    private var polling: Task<Void, Never>?
    private var lookup: Task<Void, Never>?
    private var selection: Task<Void, Never>?
    private var creditsTask: Task<Void, Never>?
    private var cache: [String: LyricsDocument] = [:]
    private var cacheOrder: [String] = []
    private var pins: [String: String] = UserDefaults.standard.dictionary(forKey: "choices") as? [String: String] ?? [:]
    private var currentKey: String?
    private let demo: Bool
    var isPreview: Bool { demo }

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            let sampleTrack = Track(id: "demo", title: "A little room for words", artist: "Quoted", album: "", duration: 0)
            let sample = LyricsCandidate(id: "demo", title: sampleTrack.title, artists: ["Quoted"], source: .genius,
                url: URL(string: "https://genius.com")!)
            track = sampleTrack
            playing = true
            document = LyricsDocument(candidate: sample, text: Self.sampleText)
            phase = .reading
        } else if UserDefaults.standard.bool(forKey: "connected") { connect() }
    }

    func connect() {
        guard !demo else { return }
        UserDefaults.standard.set(true, forKey: "connected")
        phase = .waiting
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.spotify.read()
                guard !Task.isCancelled else { return }
                self.receive(snapshot)
                // Denial doesn't cause repeated permission requests or polling.
                if self.phase == .permission { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func receive(_ snapshot: SpotifySnapshot) {
        switch snapshot {
        case .closed:
            resetTrack(); phase = .waiting; message = "Open Spotify and play something.\nThe words will meet you here."
        case .idle:
            resetTrack(); phase = .waiting; message = "Play a song in Spotify.\nThe words will meet you here."
        case .permissionDenied:
            resetTrack(); phase = .permission
            message = "Allow Quoted to read Spotify in\nSystem Settings → Privacy & Security → Automation."
        case .failed(let error):
            // Never display the previous song's lyrics against new or unreadable metadata.
            resetTrack(); phase = .failed; message = error
        case .track(let incoming, let isPlaying):
            playing = isPlaying
            guard currentKey != incoming.key else { return }
            clearCredits()
            selection?.cancel(); showChooser = false; showLinkEntry = false
            currentKey = incoming.key; track = incoming
            document = nil; candidates = []; chooserError = nil
            load(incoming)
        }
    }

    private func resetTrack() {
        clearCredits()
        lookup?.cancel(); selection?.cancel(); currentKey = nil; track = nil
        document = nil; candidates = []; showChooser = false; showLinkEntry = false
    }

    private func load(_ track: Track, reload: Bool = false) {
        lookup?.cancel()
        if !reload, let stored = cache[track.key] { document = stored; candidates = [stored.candidate]; phase = .reading; return }
        document = nil
        phase = .loading; message = "Finding the words…"
        lookup = Task { [weak self] in
            guard let self else { return }
            do {
                if let pin = pins[track.key], pin.hasPrefix("manual:"),
                   let url = URL(string: String(pin.dropFirst("manual:".count))), LyricsService.validGeniusURL(url) {
                    let candidate = LyricsCandidate(id: pin, title: track.title, artists: [track.artist], source: .genius, url: url)
                    let text = try await service.text(for: candidate)
                    guard !Task.isCancelled, currentKey == track.key else { return }
                    candidates = [candidate]
                    accept(LyricsDocument(candidate: candidate, text: text, manuallyChosen: true), for: track)
                    return
                }
                let result = try await service.search(for: track)
                guard !Task.isCancelled, currentKey == track.key else { return }
                candidates = result.candidates; message = result.notice ?? ""
                if let pinned = pins[track.key], let candidate = candidates.first(where: { $0.id == pinned }) {
                    let text = try await service.text(for: candidate)
                    guard !Task.isCancelled, currentKey == track.key else { return }
                    accept(LyricsDocument(candidate: candidate, text: text, manuallyChosen: true), for: track)
                } else if let found = result.document { accept(found, for: track) }
                else { document = nil; phase = .choose }
            } catch {
                guard !Task.isCancelled, currentKey == track.key else { return }
                document = nil; phase = .failed
                message = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the lyrics service. Try again when you're online."
            }
        }
    }

    private func accept(_ document: LyricsDocument, for track: Track) {
        if let previous = self.document, previous.candidate.id != document.candidate.id { clearCredits() }
        self.document = document; phase = .reading
        cache[track.key] = document
        cacheOrder.removeAll { $0 == track.key }; cacheOrder.append(track.key)
        if cacheOrder.count > 40 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }

    func retry() {
        if let track { load(track, reload: true) } else { connect() }
    }

    func choose(_ candidate: LyricsCandidate) {
        guard let track else { return }
        selection?.cancel(); choosingID = candidate.id; chooserError = nil
        selection = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await service.text(for: candidate)
                guard !Task.isCancelled, currentKey == track.key else { return }
                pins[track.key] = candidate.id; UserDefaults.standard.set(pins, forKey: "choices")
                accept(LyricsDocument(candidate: candidate, text: text, manuallyChosen: true), for: track)
                choosingID = nil; showChooser = false; showLinkEntry = false
            } catch {
                guard !Task.isCancelled, currentKey == track.key else { return }
                choosingID = nil
                chooserError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load that match. Please try another."
            }
        }
    }

    func useGeniusLink() {
        guard let track, let url = URL(string: linkText.trimmingCharacters(in: .whitespacesAndNewlines)), LyricsService.validGeniusURL(url) else {
            chooserError = LyricsError.invalidURL.errorDescription; return
        }
        let candidate = LyricsCandidate(id: "manual:\(url.absoluteString)", title: track.title, artists: [track.artist], source: .genius, url: url)
        choose(candidate)
    }

    func searchGenius() {
        guard let track else { return }
        var url = URLComponents(string: "https://genius.com/search")!
        url.queryItems = [URLQueryItem(name: "q", value: "\(track.artist) \(track.title)")]
        if let url = url.url { NSWorkspace.shared.open(url) }
    }

    private func clearCredits() {
        creditsTask?.cancel(); credits = nil; creditsError = nil
        creditsLoading = false; showCredits = false
    }

    func loadCredits() {
        guard let track, credits == nil, !creditsLoading else { return }
        if demo { creditsError = "Credits appear here when you're listening to a song."; return }
        creditsLoading = true; creditsError = nil
        let candidate = document?.candidate
        creditsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.credits(for: track, candidate: candidate)
                guard !Task.isCancelled, currentKey == track.key else { return }
                credits = result; creditsLoading = false
            } catch {
                guard !Task.isCancelled, currentKey == track.key else { return }
                creditsLoading = false
                creditsError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load the credits. Try again."
            }
        }
    }

    func openSource() { if let url = document?.candidate.url { NSWorkspace.shared.open(url) } }
    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
    func changeSize(_ delta: Double) {
        fontSize = min(40, max(17, fontSize + delta)); UserDefaults.standard.set(fontSize, forKey: "fontSize")
    }
    func setAppearance(_ value: String) {
        appearance = value; UserDefaults.standard.set(value, forKey: "appearance")
        NSApp.appearance = value == "system" ? nil : NSAppearance(named: value == "light" ? .aqua : .darkAqua)
    }

    static let sampleText = """
    [Intro]
    A window, soft as morning.
    A song beyond the glass.
    A little space for every word,
    and time to let it pass.

    [Verse 1]
    No line to chase.
    No place to be.
    Just turn the page
    at your own speed.

    The city carries on outside.
    The light moves through the room.
    You stay a little longer here,
    with nothing else to do.

    [Chorus]
    A little room for words.
    A little room for you.

    [Outro]
    And when another song begins,
    another page comes through.
    The world can wait a moment.
    The words belong to you.
    """
}
