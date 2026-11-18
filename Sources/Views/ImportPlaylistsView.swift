import SwiftUI
import AuthenticationServices

/// Импорт плейлистов из Spotify и медиатеки Apple Music.
/// Повторный импорт того же плейлиста обновляет его (синхронизация).
struct ImportPlaylistsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(SpotifyAccount.self) private var spotify
    @Environment(\.webAuthenticationSession) private var webAuth

    @State private var spotifyLists: [SpotifyAccount.PlaylistInfo] = []
    @State private var appleLists: [LocalPlaylist] = []
    @State private var busy: String?          // что сейчас загружается
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Form {
            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }

            spotifySection
            appleSection

            Section {
                Text("Импортированный плейлист появляется в Медиатеке. Треки при воспроизведении сами находятся в других сервисах по вашему приоритету. Импорт того же плейлиста ещё раз обновит его.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Импорт плейлистов")
        .task {
            if spotify.isLoggedIn && spotifyLists.isEmpty { await loadSpotify() }
        }
    }

    // MARK: Spotify

    @ViewBuilder private var spotifySection: some View {
        Section {
            if settings.spotifyClientID.isEmpty {
                Text("Сначала укажите Spotify Client ID в Настройках.")
                    .foregroundStyle(.secondary)
            } else if !spotify.isLoggedIn {
                Button {
                    run("login") {
                        try await spotify.login(using: webAuth)
                        await loadSpotify()
                    }
                } label: { Label("Войти в Spotify", systemImage: "person.crop.circle.badge.checkmark") }
            } else {
                HStack {
                    Text("Аккаунт: \(spotify.userName ?? "Spotify")")
                    Spacer()
                    Button("Выйти", role: .destructive) { spotify.logout(); spotifyLists = [] }
                        .buttonStyle(.borderless)
                }
                importRow(name: "Любимые треки", count: nil, key: "sp-liked", target: "Любимые треки · Spotify") {
                    try await spotify.tracks(playlistID: nil)
                }
                ForEach(spotifyLists) { p in
                    importRow(name: p.name, count: p.total, key: "sp-\(p.id)", target: "\(p.name) · Spotify") {
                        try await spotify.tracks(playlistID: p.id)
                    }
                }
                if spotifyLists.isEmpty && busy == nil {
                    Button("Загрузить плейлисты") { Task { await loadSpotify() } }
                }
            }
        } header: {
            Label("Spotify", systemImage: MusicService.spotify.symbol)
        } footer: {
            Text("В developer.spotify.com → ваше приложение → Settings → Redirect URIs добавьте:  \(SpotifyAccount.redirectURI)")
        }
    }

    private func loadSpotify() async {
        busy = "sp-list"
        do {
            if spotify.userName == nil { await spotify.loadProfile() }
            spotifyLists = try await spotify.playlists()
        } catch { self.error = error.localizedDescription }
        busy = nil
    }

    // MARK: Apple Music

    @ViewBuilder private var appleSection: some View {
        Section {
            if appleLists.isEmpty {
                Button {
                    run("apple-list") {
                        appleLists = try await AppleLibraryImporter.playlists(country: settings.country)
                    }
                } label: { Label("Показать плейлисты медиатеки", systemImage: "music.note.list") }
            }
            ForEach(appleLists) { p in
                importRow(name: p.name, count: p.count, key: "am-\(p.id)", target: "\(p.name) · Apple Music") {
                    p.load()
                }
            }
        } header: {
            Label("Apple Music", systemImage: MusicService.appleMusic.symbol)
        } footer: {
            #if os(macOS)
            Text("Берутся плейлисты из приложения «Музыка» на этом Mac.")
            #else
            Text("Берутся плейлисты из медиатеки «Музыки» на этом iPhone.")
            #endif
        }
    }

    // MARK: Общее

    private func importRow(name: String, count: Int?, key: String, target: String,
                           load: @escaping () async throws -> [UnifiedTrack]) -> some View {
        let existing = library.playlists.contains { $0.name == target }
        return HStack {
            VStack(alignment: .leading) {
                Text(name).lineLimit(1)
                if let count { Text("\(count) треков").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if busy == key {
                ProgressView().controlSize(.small)
            } else {
                Button(existing ? "Обновить" : "Импорт") {
                    run(key) {
                        let tracks = try await load()
                        save(tracks, as: target)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(busy != nil)
            }
        }
    }

    private func save(_ tracks: [UnifiedTrack], as name: String) {
        if let i = library.playlists.firstIndex(where: { $0.name == name }) {
            // сохраняем уже найденные ссылки в других сервисах
            let old = library.playlists[i].tracks
            library.playlists[i].tracks = tracks.map { t in
                guard let prev = old.first(where: { $0.matches(t) }) else { return t }
                var merged = prev
                merged.merge(t)
                return merged
            }
        } else {
            library.playlists.append(Playlist(name: name, tracks: tracks))
        }
        message = "«\(name)»: \(tracks.count) треков"
    }

    private func run(_ key: String, _ body: @escaping () async throws -> Void) {
        busy = key; error = nil; message = nil
        Task {
            do { try await body() }
            catch is CancellationError {}
            catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {}
            catch { self.error = error.localizedDescription }
            busy = nil
        }
    }
}
