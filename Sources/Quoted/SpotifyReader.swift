import AppKit
import QuotedCore

enum SpotifySnapshot {
    case closed, idle, permissionDenied, failed(String)
    case track(Track, playing: Bool)
}

/// A serial actor keeps Apple Events off the UI thread and prevents overlapping reads.
actor SpotifyReader {
    private var script: NSAppleScript?
    func read() -> SpotifySnapshot {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else { return .closed }
        if script == nil {
            script = NSAppleScript(source: """
            with timeout of 3 seconds
                tell application id "com.spotify.client"
                    if player state is stopped then return {"idle"}
                    set t to current track
                    set coverURL to ""
                    try
                        set coverURL to artwork url of t
                    end try
                    return {id of t, name of t, artist of t, album of t, duration of t, (player state is playing), coverURL}
                end tell
            end timeout
            """)
        }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else { return .failed("Spotify couldn't be read.") }
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -1743 || number == -1744 { return .permissionDenied }
            // Track changes briefly leave Spotify without a current-track object.
            if number == -1728 || number == -1719 { return .idle }
            return .failed("Spotify isn't responding. Try again in a moment.")
        }
        guard result.numberOfItems >= 6 else { return .idle }
        let id = result.atIndex(1)?.stringValue ?? ""
        let title = result.atIndex(2)?.stringValue ?? ""
        let artist = result.atIndex(3)?.stringValue ?? ""
        let album = result.atIndex(4)?.stringValue ?? ""
        let duration = result.atIndex(5)?.doubleValue ?? 0
        guard !title.isEmpty, !artist.isEmpty,
              id.hasPrefix("spotify:track:") || id.hasPrefix("spotify:local:") else { return .idle }
        let artworkURL = result.atIndex(7)?.stringValue.flatMap(URL.init(string:))
        return .track(Track(id: id, title: title, artist: artist, album: album, duration: duration, artworkURL: artworkURL),
                      playing: result.atIndex(6)?.booleanValue ?? false)
    }
}
