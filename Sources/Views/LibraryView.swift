import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    FavoritesView()
                } label: {
                    Label("Избранное (\(library.favorites.count))", systemImage: "heart.fill")
                }
            }
            Section {
                NavigationLink {
                    ImportPlaylistsView()
                } label: {
                    Label("Импорт из Spotify и Apple Music", systemImage: "square.and.arrow.down")
                }
            }
            Section("Плейлисты") {
                ForEach(library.playlists) { p in
                    NavigationLink(value: p.id) {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(summary(p)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { library.playlists.remove(atOffsets: $0) }

                Button { showNewPlaylist = true } label: {
                    Label("Новый плейлист", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Медиатека")
        .navigationDestination(for: Playlist.ID.self) { PlaylistView(playlistID: $0) }
        .alert("Новый плейлист", isPresented: $showNewPlaylist) {
            TextField("Название", text: $newName)
            Button("Создать") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { library.playlists.append(Playlist(name: name)) }
                newName = ""
            }
            Button("Отмена", role: .cancel) { newName = "" }
        }
    }

    /// «12 треков · Apple 9 · Spotify 3»
    private func summary(_ p: Playlist) -> String {
        var counts: [MusicService: Int] = [:]
        for t in p.tracks { for s in t.availableServices { counts[s, default: 0] += 1 } }
        let parts = MusicService.allCases.compactMap { s in counts[s].map { "\(s.shortTitle) \($0)" } }
        return (["\(p.tracks.count) треков"] + parts).joined(separator: " · ")
    }
}

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        List {
            ForEach(library.favorites) { TrackRow(track: $0, list: library.favorites) }
                .onDelete { library.favorites.remove(atOffsets: $0) }
                .onMove { library.favorites.move(fromOffsets: $0, toOffset: $1) }
        }
        .overlay {
            if library.favorites.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "heart",
                                       description: Text("Добавляйте треки через меню (долгое нажатие / правый клик)."))
            }
        }
        .navigationTitle("Избранное")
        .toolbar {
            if let first = library.favorites.first {
                Button { player.play(first, in: library.favorites) } label: { Label("Слушать всё", systemImage: "play.fill") }
            }
        }
    }
}

struct PlaylistView: View {
    let playlistID: Playlist.ID
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    private var index: Int? { library.playlists.firstIndex { $0.id == playlistID } }

    var body: some View {
        if let i = index {
            let tracks = library.playlists[i].tracks
            List {
                ForEach(tracks) { TrackRow(track: $0, list: tracks) }
                    .onDelete { library.playlists[i].tracks.remove(atOffsets: $0) }
                    .onMove { library.playlists[i].tracks.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if tracks.isEmpty {
                    ContentUnavailableView("Плейлист пуст", systemImage: "music.note.list",
                                           description: Text("Найдите трек в Поиске или вставьте ссылку и добавьте его сюда."))
                }
            }
            .navigationTitle(library.playlists[i].name)
            .toolbar {
                if let first = tracks.first {
                    Button { player.play(first, in: tracks) } label: { Label("Слушать", systemImage: "play.fill") }
                    Button { player.play(tracks.randomElement() ?? first, in: tracks.shuffled()) } label: {
                        Label("Перемешать", systemImage: "shuffle")
                    }
                }
            }
        } else {
            Text("Плейлист удалён")
        }
    }
}
