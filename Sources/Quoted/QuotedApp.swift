import AppKit
import SwiftUI

@main
@MainActor
enum QuotedApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var model: ReaderModel!
    private var dragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let documentationAppearance = DocumentationPreview.appearance
        model = ReaderModel(demo: args.contains("--preview") || documentationAppearance != nil)
        if let documentationAppearance {
            model.fontSize = 24
            model.appearance = documentationAppearance
            NSApp.appearance = NSAppearance(named: documentationAppearance == "light" ? .aqua : .darkAqua)
        } else {
            model.setAppearance(model.appearance)
        }
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Quoted"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 350, height: 440)
        window.maxSize = NSSize(width: 1000, height: 1600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        if documentationAppearance == nil { window.setFrameAutosaveName("VeilReader") }

        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 740))
        glass.cornerRadius = 24
        glass.style = .regular
        let host = NSHostingView(rootView: ReaderView(model: model).ignoresSafeArea())
        host.sizingOptions = []
        glass.contentView = host
        window.contentView = glass
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window,
                  !self.model.showCredits, !self.model.showChooser, !self.model.showLinkEntry,
                  self.model.document != nil || self.model.phase == .loading else { return event }
            // The title bar handles its own native controls and dragging.
            guard event.locationInWindow.y < self.window.frame.height - 32 else { return event }
            self.window.performDrag(with: event)
            return nil
        }
        if documentationAppearance != nil {
            window.center()
            window.backgroundColor = documentationAppearance == "light"
                ? NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1)
                : NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        } else if !UserDefaults.standard.bool(forKey: "hasPosition") {
            window.center(); UserDefaults.standard.set(true, forKey: "hasPosition")
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if args.contains("--show-credits") || Bundle.main.object(forInfoDictionaryKey: "QuotedDocumentationShowCredits") as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.model.track != nil else { return }
                self.model.showCredits = true
            }
        }
        if documentationAppearance != nil, let index = args.firstIndex(of: "--export-documentation"), index + 1 < args.count {
            let output = URL(fileURLWithPath: args[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [self] in
                do {
                    try DocumentationPreview.export(window: window, to: output)
                    print("Exported offline preview: \(output.lastPathComponent)")
                    NSApp.terminate(nil)
                } catch {
                    fputs("Documentation export failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
        if args.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
                guard NSApp.activationPolicy() == .regular,
                      window.contentView is NSGlassEffectView,
                      window.styleMask.contains(.resizable),
                      window.styleMask.contains(.closable),
                      applicationShouldTerminateAfterLastWindowClosed(NSApp) else {
                    fputs("Window lifecycle check failed\n", stderr); exit(1)
                }
                func readerScroll(in view: NSView) -> NSScrollView? {
                    if let scroll = view as? NSScrollView { return scroll }
                    return view.subviews.lazy.compactMap { readerScroll(in: $0) }.first
                }
                guard let scroll = readerScroll(in: window.contentView!),
                      !(scroll.hasVerticalScroller && scroll.verticalScroller?.isHiddenOrHasHiddenAncestor == false) else {
                    fputs("Reader scrollbar is visible\n", stderr); exit(1)
                }
                let origin = scroll.contentView.bounds.origin
                scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + 60))
                guard scroll.contentView.bounds.origin != origin else {
                    fputs("Reader cannot scroll\n", stderr); exit(1)
                }
                scroll.contentView.scroll(to: origin)
                let originalFrame = window.frame
                window.setContentSize(NSSize(width: 350, height: 440))
                window.contentView?.layoutSubtreeIfNeeded()
                window.setFrame(originalFrame, display: true)
                print("PASS: native glass, hidden scrollbar, working scroll, regular Dock app, resizing, quit-on-close policy")
                window.performClose(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                fputs("Window did not quit after closing\n", stderr); exit(2)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "Quoted")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        appMenu.addItem(item("About Quoted", #selector(about), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Quoted", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Quoted", #selector(NSApplication.terminate(_:)), "q", target: NSApp))

        let trackMenu = NSMenu(title: "Lyrics")
        let trackItem = NSMenuItem(title: "Lyrics", action: nil, keyEquivalent: ""); trackItem.submenu = trackMenu; main.addItem(trackItem)
        trackMenu.addItem(item("Song Credits…", #selector(credits), "i", shift: true))
        trackMenu.addItem(.separator())
        trackMenu.addItem(item("Choose Lyrics…", #selector(choose), "l", shift: true))
        trackMenu.addItem(item("Use a Genius Link…", #selector(useLink), "g", shift: true))
        trackMenu.addItem(item("Reload Lyrics", #selector(reload), "r"))
        trackMenu.addItem(.separator())
        trackMenu.addItem(item("Search on Genius", #selector(searchGenius), ""))
        trackMenu.addItem(item("Open Lyric Source", #selector(openSource), ""))

        let edit = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c", target: nil))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v", target: nil))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil))

        let view = NSMenu(title: "View")
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: ""); viewItem.submenu = view; main.addItem(viewItem)
        view.addItem(item("Larger Text", #selector(larger), "+"))
        view.addItem(item("Smaller Text", #selector(smaller), "-"))
        view.addItem(item("Actual Size", #selector(actualSize), "0"))
        view.addItem(.separator())
        view.addItem(item("Dark Glass", #selector(dark), ""))
        view.addItem(item("Light Glass", #selector(light), ""))
        view.addItem(item("Follow System Appearance", #selector(systemAppearance), ""))

        let windowMenu = NSMenu(title: "Window")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); windowItem.submenu = windowMenu; main.addItem(windowItem)
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), "", target: nil))
        windowMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w", target: nil))
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String, shift: Bool = false, target: AnyObject? = nil) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = target ?? (title == "Copy" || title == "Paste" || title == "Select All" || title == "Close" || title == "Zoom" || title == "Minimize" ? nil : self)
        result.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
        return result
    }

    @objc private func choose() { if model.track != nil { model.showChooser = true } }
    @objc private func credits() { if model.track != nil { model.showCredits = true } }
    @objc private func useLink() { if model.track != nil { model.chooserError = nil; model.showLinkEntry = true } }
    @objc private func reload() { model.retry() }
    @objc private func searchGenius() { model.searchGenius() }
    @objc private func openSource() { model.openSource() }
    @objc private func larger() { model.changeSize(2) }
    @objc private func smaller() { model.changeSize(-2) }
    @objc private func actualSize() { model.changeSize(26 - model.fontSize) }
    @objc private func dark() { model.setAppearance("dark") }
    @objc private func light() { model.setAppearance("light") }
    @objc private func systemAppearance() { model.setAppearance("system") }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Quoted", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0",
            .credits: NSAttributedString(string: "Your music, in words.\nA quiet Spotify lyrics reader.\nGenius first · LRCLIB fallback.")])
    }
}
