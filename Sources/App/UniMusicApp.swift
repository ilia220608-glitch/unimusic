import SwiftUI

@main
struct UniMusicApp: App {
    @State private var settings: AppSettings
    @State private var library: LibraryStore
    @State private var search: SearchEngine
    @State private var player: PlayerController
    @State private var spotify: SpotifyAccount

    init() {
        let settings = AppSettings()
        let library = LibraryStore()
        let search = SearchEngine(settings: settings)
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _search = State(initialValue: search)
        _spotify = State(initialValue: SpotifyAccount(settings: settings))
        _player = State(initialValue: PlayerController(settings: settings, search: search, library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(library)
                .environment(search)
                .environment(player)
                .environment(spotify)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
                #endif
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settings)
                .frame(width: 520, height: 560)
        }
        #endif
    }
}
