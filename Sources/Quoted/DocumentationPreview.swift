import AppKit

/// Opt-in, offline presentation used by the documentation app copies.
@MainActor
enum DocumentationPreview {
    static var appearance: String? {
        Bundle.main.object(forInfoDictionaryKey: "QuotedDocumentationAppearance") as? String
    }

    static func export(window: NSWindow, to url: URL) throws {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let frame = window.contentView?.superview,
              let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
