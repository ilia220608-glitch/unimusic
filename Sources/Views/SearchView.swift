import SwiftUI

struct SearchView: View {
    @Environment(SearchEngine.self) private var search
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    var body: some View {
        List {
            if !settings.hasSpotify || !settings.hasYouTube {
                Section {
                    Label("Сейчас поиск идёт только по Apple Music. Добавьте ключи Spotify и YouTube в Настройках, чтобы искать везде.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(search.errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            ForEach(search.results) { track in
                TrackRow(track: track, list: search.results)
            }
        }
        .overlay {
            if search.isSearching && search.results.isEmpty {
                ProgressView("Ищу во всех сервисах…")
            } else if !query.isEmpty && search.results.isEmpty && !search.isSearching {
                ContentUnavailableView.search(text: query)
            } else if query.isEmpty && search.results.isEmpty {
                ContentUnavailableView("Один поиск — все сервисы",
                                       systemImage: "music.magnifyingglass",
                                       description: Text("Apple Music, Spotify и YouTube сразу. Одинаковые треки объединяются."))
            }
        }
        .navigationTitle("Поиск")
        .searchable(text: $query, prompt: "Исполнитель или трек")
        .onSubmit(of: .search) { search.search(query) }
        .task(id: query) {
            // поиск во время набора, с небольшой задержкой
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            search.search(query)
        }
    }
}
