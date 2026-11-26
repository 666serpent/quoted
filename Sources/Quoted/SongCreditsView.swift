import SwiftUI
import QuotedCore

struct SongCreditsView: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .center, spacing: 15) {
                AsyncImage(url: model.track?.artworkURL ?? model.credits?.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.05))
                        .overlay { Image(systemName: "music.note").font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary) }
                }
                .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Song artwork")
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.credits?.title ?? model.track?.title ?? "")
                        .font(.system(size: 17, weight: .bold)).lineLimit(4)
                    if model.credits == nil {
                        Text(model.track?.artist ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .vertical) {
                details.fixedSize(horizontal: false, vertical: true)
                ScrollView { details }.scrollIndicators(.never)
            }
        }
        .padding(24)
        .overlay(alignment: .topTrailing) {
            Button { model.showCredits = false } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            .padding(6).help("Close credits").accessibilityLabel("Close credits")
        }
        .onAppear(perform: model.loadCredits)
    }

    @ViewBuilder private var details: some View {
        if model.isPreview {
            VStack(alignment: .leading, spacing: 23) {
                previewSection("ARTISTS", names: ["Example artist"])
                previewSection("PRODUCERS", names: ["Example producer", "Example co-producer"])
                Text("DEMONSTRATION DATA").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if model.creditsLoading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .accessibilityLabel("Loading credits")
        } else if let credits = model.credits {
            VStack(alignment: .leading, spacing: 23) {
                creditSection("ARTISTS", people: credits.artists, empty: "No artists listed on Genius.")
                creditSection("PRODUCERS", people: credits.producers, empty: "No producers listed on Genius.")
                Link(destination: credits.songURL) {
                    Text("GENIUS  ↗").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = model.creditsError {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20) {
                    Button("Try again", action: model.loadCredits)
                    Button("Search Genius ↗", action: model.searchGenius)
                }.font(.system(size: 11)).buttonStyle(.plain)
            }
        }
    }

    private func previewSection(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(.secondary)
            ForEach(names, id: \.self) { name in
                HStack {
                    Text(name).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func creditSection(_ title: String, people: [GeniusPerson], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(.secondary)
            if people.isEmpty {
                Text(empty).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(people) { person in
                    Link(destination: person.url) {
                        HStack(spacing: 10) {
                            Text(person.name).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(person.name) on Genius")
                }
            }
        }
    }
}
