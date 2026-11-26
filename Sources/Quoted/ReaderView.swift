import SwiftUI
import QuotedCore

struct ReaderView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.055), .clear, .black.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                if let document = model.document {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: 0).id("beginning")
                                LyricsText(text: document.text, fontSize: model.fontSize)
                            }
                            .padding(.horizontal, 38).padding(.top, 12).padding(.bottom, 40)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: model.track?.key) { _, _ in proxy.scrollTo("beginning", anchor: .top) }
                        .onChange(of: document.candidate.id) { _, _ in proxy.scrollTo("beginning", anchor: .top) }
                        .mask(alignment: .top) {
                            VStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                                Rectangle()
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 26)
                            }
                        }
                    }
                    .padding(.top, 44)
                } else {
                    switch model.phase {
                    case .loading:
                        ProgressView().controlSize(.regular)
                            .accessibilityLabel("Loading lyrics")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .choose, .failed, .waiting:
                        unavailableState
                    default:
                        emptyState
                    }
                }
            }
            .blur(radius: model.showCredits ? 4 : 0)
            .allowsHitTesting(!model.showCredits)
            .accessibilityHidden(model.showCredits)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.035), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if model.track != nil {
                Button { model.showCredits.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.trailing, 12).padding(.top, 4)
                .help("Song credits")
                .accessibilityLabel("Song credits")
                .disabled(model.showCredits)
            }
        }
        .contextMenu {
            Button("Song Credits…") { model.showCredits = true }.disabled(model.track == nil)
            Divider()
            Button("Choose Lyrics…") { model.showChooser = true }.disabled(model.track == nil)
            Button("Reload Lyrics", action: model.retry)
            Divider()
            Button("Larger Text") { model.changeSize(2) }
            Button("Smaller Text") { model.changeSize(-2) }
            Divider()
            Button("Open \(model.document?.candidate.source.rawValue ?? "Lyric") Source", action: model.openSource).disabled(model.document == nil)
        }
        .overlay {
            if model.showCredits {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.16).contentShape(Rectangle())
                            .onTapGesture { model.showCredits = false }
                        SongCreditsView(model: model)
                            .frame(width: min(348, geometry.size.width - 40))
                            .background(.regularMaterial, in: .rect(cornerRadius: 22))
                            .glassEffect(.regular, in: .rect(cornerRadius: 22))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 28, y: 12)
                            .frame(maxHeight: geometry.size.height - 64)
                            .accessibilityAddTraits(.isModal)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .transition(.opacity)
                .onExitCommand { model.showCredits = false }
            }
        }
        .sheet(isPresented: $model.showChooser) { MatchChooser(model: model) }
        .sheet(isPresented: $model.showLinkEntry) { GeniusLinkEntry(model: model) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.showCredits)
    }

    private var unavailableState: some View {
        Button {
            if model.phase == .waiting { model.openSpotify() }
            else if model.phase == .choose && !model.candidates.isEmpty { model.showChooser = true }
            else { model.retry() }
        } label: {
            Image(systemName: model.phase == .waiting ? "music.note" : "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.message)
        .accessibilityLabel(model.phase == .waiting ? "Open Spotify to play a song" : "Lyrics unavailable. Click to retry or choose a match.")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.track == nil {
                Text("QUOTED").font(.system(size: 10, weight: .medium)).tracking(4)
                    .foregroundStyle(.secondary).padding(.top, 66)
            }
            Spacer(minLength: 36)
            Text(headline)
                .font(.system(size: 41, weight: .bold))
                .lineSpacing(3).foregroundStyle(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text(description)
                .font(.system(size: 13)).lineSpacing(6)
                .foregroundStyle(.secondary).padding(.top, 23)
                .fixedSize(horizontal: false, vertical: true)
            if model.phase == .loading {
                ProgressView().controlSize(.small).padding(.top, 28).accessibilityLabel("Finding lyrics")
            } else {
                Button(action: primaryAction) {
                    Text(actionTitle).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.top, 20)
                if model.phase == .choose || (model.phase == .failed && model.track != nil) {
                    Button("Search on Genius ↗", action: model.searchGenius)
                        .font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain)
                        .padding(.top, 6)
                }
                if model.phase == .permission {
                    Button("I've allowed access →", action: model.connect)
                        .font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.top, 6)
                }
            }
            Spacer(minLength: 70)
            Text("JUST THE WORDS.")
                .font(.system(size: 8, weight: .medium)).tracking(2.5)
                .foregroundStyle(.tertiary).padding(.bottom, 35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 42)
    }

    private var headline: String {
        switch model.phase {
        case .welcome, .waiting: return "Your music,\nin words."
        case .loading: return "A moment\nfor the words."
        case .choose: return model.candidates.isEmpty ? "A little quiet\non this one." : "The right song.\nThe right words."
        case .permission: return "One small\nintroduction."
        case .failed: return "A pause\nbetween words."
        case .reading: return ""
        }
    }

    private var description: String {
        model.phase == .welcome ? "Connect to Spotify.\nRead along at your own pace." : model.message
    }
    private var actionTitle: String {
        switch model.phase {
        case .welcome: return "Connect Spotify  →"
        case .waiting: return "Open Spotify  ↗"
        case .permission: return "Open System Settings  ↗"
        case .choose where !model.candidates.isEmpty: return "Choose a match  →"
        default: return "Try again  →"
        }
    }
    private func primaryAction() {
        switch model.phase {
        case .welcome: model.connect()
        case .waiting: model.openSpotify()
        case .permission: model.openPrivacy()
        case .choose where !model.candidates.isEmpty: model.showChooser = true
        default: model.retry()
        }
    }
}

struct MatchChooser: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Choose the words").font(.system(size: 25, weight: .bold))
            Text("Check the artist and recording. Quoted will remember your choice.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if model.candidates.isEmpty {
                Text("No candidates yet. Search Genius and paste a song link instead.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.candidates) { candidate in
                            Button { model.choose(candidate) } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.title).font(.system(size: 13, weight: .medium))
                                        Text(candidate.artist).font(.system(size: 11)).foregroundStyle(.secondary)
                                        if let album = candidate.album, !album.isEmpty {
                                            Text(album).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if model.choosingID == candidate.id { ProgressView().controlSize(.small) }
                                    else {
                                        VStack(alignment: .trailing, spacing: 5) {
                                            Text(candidate.source.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                                            if let duration = candidate.duration {
                                                Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                                                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                }
                                .padding(12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            .disabled(model.choosingID != nil)
                        }
                    }
                }.frame(maxHeight: 300)
            }
            if let error = model.chooserError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Button("Genius link…") { dismiss(); model.chooserError = nil; model.showLinkEntry = true }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 425)
    }
}

struct GeniusLinkEntry: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Your Genius link").font(.system(size: 25, weight: .bold))
            Text("Choose the original song page on Genius, then paste its link here. This choice overrides automatic matching for this track.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("https://genius.com/Artist-song-lyrics", text: $model.linkText)
                .textFieldStyle(.roundedBorder).onSubmit(model.useGeniusLink)
            if let error = model.chooserError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Button("Search Genius ↗", action: model.searchGenius)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use link", action: model.useGeniusLink).keyboardShortcut(.defaultAction)
                    .disabled(model.choosingID != nil || model.linkText.isEmpty)
            }
        }.padding(28).frame(width: 425)
    }
}
