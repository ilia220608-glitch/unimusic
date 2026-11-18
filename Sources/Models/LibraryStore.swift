import Foundation
import Observation

/// Локальная медиатека: избранное и плейлисты из треков любых сервисов.
@MainActor @Observable
final class LibraryStore {
    var favorites: [UnifiedTrack] = [] { didSet { save() } }
    var playlists: [Playlist] = [] { didSet { save() } }

    private struct Snapshot: Codable {
        var favorites: [UnifiedTrack]
        var playlists: [Playlist]
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UniMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    @ObservationIgnored private var loading = false

    init() {
        loading = true
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            favorites = snap.favorites
            playlists = snap.playlists
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let snap = Snapshot(favorites: favorites, playlists: playlists)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func isFavorite(_ t: UnifiedTrack) -> Bool { favorites.contains { $0.matches(t) } }

    func toggleFavorite(_ t: UnifiedTrack) {
        if let i = favorites.firstIndex(where: { $0.matches(t) }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(t, at: 0)
        }
    }

    func add(_ t: UnifiedTrack, to playlistID: Playlist.ID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var copy = t
        copy.id = UUID()
        playlists[i].tracks.append(copy)
    }

    /// Обновить трек везде, где он лежит (после поиска ссылок через song.link)
    func update(_ t: UnifiedTrack) {
        for i in favorites.indices where favorites[i].matches(t) {
            favorites[i].merge(t); favorites[i].enriched = true
        }
        for p in playlists.indices {
            for j in playlists[p].tracks.indices where playlists[p].tracks[j].matches(t) {
                playlists[p].tracks[j].merge(t); playlists[p].tracks[j].enriched = true
            }
        }
    }
}
