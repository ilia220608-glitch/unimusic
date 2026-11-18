import SwiftUI

struct ContentView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView {
            NavigationStack { SearchView() }
                .withMiniPlayer()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView() }
                .withMiniPlayer()
                .tabItem { Label("Медиатека", systemImage: "music.note.list") }
            NavigationStack { ImportLinkView() }
                .withMiniPlayer()
                .tabItem { Label("По ссылке", systemImage: "link") }
            #if os(iOS)
            NavigationStack { SettingsView() }
                .withMiniPlayer()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
            #endif
        }
        // ОДИН мини-плеер на всё приложение (иначе встроенный YouTube создавался бы в каждой вкладке)
        .overlay(alignment: .bottom) {
            if player.current != nil {
                MiniPlayerView()
                    #if os(iOS)
                    .padding(.bottom, 49) // над таб-баром
                    #endif
            }
        }
        .onAppear {
            let open = openURL
            player.openURL = { url in
                open(url) { accepted in
                    // нет приложения Spotify → открываем веб-версию
                    if !accepted, url.scheme == "spotify",
                       let id = url.absoluteString.components(separatedBy: ":").last,
                       let web = URL(string: "https://open.spotify.com/track/\(id)") {
                        open(web)
                    }
                }
            }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerController.self) private var player
    func body(content: Content) -> some View {
        // освобождаем место под мини-плеер, чтобы он не закрывал список
        content.safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: player.current != nil ? MiniPlayerView.height : 0)
        }
    }
}

extension View {
    func withMiniPlayer() -> some View { modifier(MiniPlayerInset()) }
}
