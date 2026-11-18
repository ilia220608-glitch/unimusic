import SwiftUI

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
    }
}

struct ServiceBadge: View {
    let service: MusicService
    var body: some View {
        Text(service.shortTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(service.color.opacity(0.18), in: Capsule())
            .foregroundStyle(service.color)
    }
}

/// Строка трека + меню действий (избранное, плейлисты, «включить в…», «найти везде»)
struct TrackRow: View {
    let track: UnifiedTrack
    var list: [UnifiedTrack]? = nil

    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(SearchEngine.self) private var search
    @Environment(\.openURL) private var openURL
    @State private var enriching = false

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        Button { player.play(track, in: list) } label: {
            HStack(spacing: 12) {
                ArtworkView(url: track.artworkURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.body.weight(isCurrent ? .bold : .regular)).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(track.availableServices) { ServiceBadge(service: $0) }
                        if enriching { ProgressView().controlSize(.mini) }
                    }
                }
                Spacer()
                if library.isFavorite(track) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .swipeActions(edge: .trailing) {
            Button { library.toggleFavorite(track) } label: { Label("Избранное", systemImage: "heart") }
                .tint(.pink)
        }
    }

    @ViewBuilder private var menu: some View {
        Button { library.toggleFavorite(track) } label: {
            Label(library.isFavorite(track) ? "Убрать из избранного" : "В избранное",
                  systemImage: library.isFavorite(track) ? "heart.slash" : "heart")
        }
        if !library.playlists.isEmpty {
            Menu("Добавить в плейлист") {
                ForEach(library.playlists) { p in
                    Button(p.name) { library.add(track, to: p.id) }
                }
            }
        }
        Divider()
        Menu("Включить в…") {
            ForEach(track.availableServices) { s in
                Button(s.title) { player.play(track, on: s) }
            }
        }
        Menu("Искать в…") {
            ForEach(MusicService.allCases) { s in
                Button(s.title) { if let u = s.searchURL(for: track.searchQuery) { openURL(u) } }
            }
        }
        if !track.enriched {
            Button {
                enriching = true
                Task {
                    if let t = try? await search.enrich(track) { library.update(t) }
                    enriching = false
                }
            } label: { Label("Найти во всех сервисах", systemImage: "arrow.triangle.2.circlepath") }
        }
    }
}
