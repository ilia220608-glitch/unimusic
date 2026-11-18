import SwiftUI

/// Вставьте ссылку на трек из любого сервиса (друг скинул Spotify, а у вас Apple Music) —
/// приложение найдёт этот трек во всех остальных сервисах.
struct ImportLinkView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player

    @State private var text = ""
    @State private var result: UnifiedTrack?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("https://open.spotify.com/track/…", text: $text)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(resolve)
                HStack {
                    Button("Вставить из буфера") { if let s = Clipboard.string { text = s; resolve() } }
                    Spacer()
                    Button("Найти", action: resolve).disabled(loading || URL(string: text) == nil)
                }
            } footer: {
                Text("Spotify, Apple Music, YouTube, YouTube Music, SoundCloud, Яндекс Музыка, Deezer, Tidal…")
            }

            if loading { ProgressView("Ищу трек во всех сервисах…") }
            if let error { Text(error).foregroundStyle(.red) }

            if let t = result {
                Section("Найдено") {
                    HStack(spacing: 12) {
                        ArtworkView(url: t.artworkURL, size: 64)
                        VStack(alignment: .leading) {
                            Text(t.title).font(.headline)
                            Text(t.artist).foregroundStyle(.secondary)
                        }
                    }
                    Button { player.play(t) } label: { Label("Слушать (по приоритету)", systemImage: "play.fill") }
                    Button { library.toggleFavorite(t) } label: {
                        Label(library.isFavorite(t) ? "В избранном" : "В избранное",
                              systemImage: library.isFavorite(t) ? "heart.fill" : "heart")
                    }
                    if !library.playlists.isEmpty {
                        Menu {
                            ForEach(library.playlists) { p in Button(p.name) { library.add(t, to: p.id) } }
                        } label: { Label("Добавить в плейлист", systemImage: "text.badge.plus") }
                    }
                }
                Section("Доступен в") {
                    ForEach(MusicService.allCases) { s in
                        HStack {
                            Image(systemName: s.symbol).foregroundStyle(s.color).frame(width: 24)
                            Text(s.title)
                            Spacer()
                            if t.links[s] != nil {
                                Button("Включить") { player.play(t, on: s) }
                            } else {
                                Text("нет").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("По ссылке")
    }

    private func resolve() {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            error = "Это не похоже на ссылку"
            return
        }
        loading = true; error = nil; result = nil
        Task {
            do { result = try await Odesli().resolve(url, country: settings.country) }
            catch { self.error = "Не удалось найти трек: \(error.localizedDescription)" }
            loading = false
        }
    }
}

enum Clipboard {
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
