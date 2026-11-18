import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach(settings.priority) { s in
                        HStack {
                            Image(systemName: s.symbol).foregroundStyle(s.color).frame(width: 24)
                            Text(s.title)
                            Spacer()
                            #if os(macOS)
                            Button { move(s, -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                            Button { move(s, 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                            #endif
                        }
                    }
                .onMove { settings.priority.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Порядок сервисов")
            } footer: {
                Text("Трек включается в первом сервисе из списка, где он есть. Если его нет — во втором и так далее.")
            }

            Section {
                TextField("Страна (RU, US, KZ…)", text: $settings.country)
            } header: { Text("Регион магазина") }

            Section {
                TextField("Client ID", text: $settings.spotifyClientID)
                SecureField("Client Secret", text: $settings.spotifyClientSecret)
                Link("Получить ключи на developer.spotify.com", destination: URL(string: "https://developer.spotify.com/dashboard")!)
            } header: { Text("Spotify (поиск)") } footer: {
                Text("Create app → Redirect URI: unimusic://spotify-callback → API: Web API. Скопируйте Client ID и Secret. Для импорта плейлистов достаточно Client ID.")
            }

            Section {
                SecureField("API key", text: $settings.youtubeAPIKey)
                Link("Получить ключ в Google Cloud", destination: URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!)
            } header: { Text("YouTube (поиск)") } footer: {
                Text("Включите YouTube Data API v3 → Credentials → Create API key. Бесплатно ~100 поисков в день.")
            }

            Section("О сервисах") {
                Text("Apple Music — поиск без ключа. На iPhone играет прямо из приложения (нужна подписка), на Mac открывается в «Музыке».")
                Text("SoundCloud, Яндекс Музыка, YouTube Music — находятся через song.link по ссылке и открываются в своём приложении.")
                Text("VK Музыка — открытого API нет, доступен только переход к поиску в VK.")
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .autocorrectionDisabled()
        #if os(iOS)
        .environment(\.editMode, .constant(.active)) // перетаскивание порядка сервисов
        #endif
        .navigationTitle("Настройки")
    }

    private func move(_ s: MusicService, _ delta: Int) {
        guard let i = settings.priority.firstIndex(of: s) else { return }
        let j = i + delta
        guard settings.priority.indices.contains(j) else { return }
        settings.priority.swapAt(i, j)
    }
}
