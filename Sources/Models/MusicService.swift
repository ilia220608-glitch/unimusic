import SwiftUI

/// Все сервисы, которые знает приложение.
enum MusicService: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case appleMusic, spotify, youtube, youtubeMusic, soundcloud, yandex, vk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtube: "YouTube"
        case .youtubeMusic: "YouTube Music"
        case .soundcloud: "SoundCloud"
        case .yandex: "Яндекс Музыка"
        case .vk: "VK Музыка"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleMusic: "Apple"
        case .spotify: "Spotify"
        case .youtube: "YT"
        case .youtubeMusic: "YT Music"
        case .soundcloud: "SC"
        case .yandex: "Яндекс"
        case .vk: "VK"
        }
    }

    var color: Color {
        switch self {
        case .appleMusic: Color(red: 0.98, green: 0.24, blue: 0.33)
        case .spotify: Color(red: 0.11, green: 0.73, blue: 0.33)
        case .youtube: Color(red: 0.93, green: 0.11, blue: 0.14)
        case .youtubeMusic: Color(red: 0.80, green: 0.10, blue: 0.10)
        case .soundcloud: Color(red: 1.0, green: 0.45, blue: 0.0)
        case .yandex: Color(red: 0.98, green: 0.75, blue: 0.0)
        case .vk: Color(red: 0.0, green: 0.47, blue: 1.0)
        }
    }

    var symbol: String {
        switch self {
        case .appleMusic: "applelogo"
        case .spotify: "dot.radiowaves.left.and.right"
        case .youtube, .youtubeMusic: "play.rectangle.fill"
        case .soundcloud: "cloud.fill"
        case .yandex: "music.note"
        case .vk: "music.quarternote.3"
        }
    }

    /// Ключ сервиса в ответе song.link (Odesli)
    var odesliKey: String? {
        switch self {
        case .appleMusic: "appleMusic"
        case .spotify: "spotify"
        case .youtube: "youtube"
        case .youtubeMusic: "youtubeMusic"
        case .soundcloud: "soundcloud"
        case .yandex: "yandex"
        case .vk: nil
        }
    }

    /// Ссылка на поиск внутри сервиса — запасной вариант, если точной ссылки нет.
    func searchURL(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .appleMusic: return URL(string: "https://music.apple.com/search?term=\(q)")
        case .spotify: return URL(string: "https://open.spotify.com/search/\(q)")
        case .youtube: return URL(string: "https://www.youtube.com/results?search_query=\(q)")
        case .youtubeMusic: return URL(string: "https://music.youtube.com/search?q=\(q)")
        case .soundcloud: return URL(string: "https://soundcloud.com/search/sounds?q=\(q)")
        case .yandex: return URL(string: "https://music.yandex.ru/search?text=\(q)")
        case .vk: return URL(string: "https://vk.com/audio?q=\(q)")
        }
    }
}
