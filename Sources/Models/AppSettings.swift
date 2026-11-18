import Foundation
import Observation

@MainActor @Observable
final class AppSettings {
    /// Порядок, в котором выбирается сервис для воспроизведения.
    var priority: [MusicService] { didSet { save() } }
    /// Страна магазина Apple Music / Spotify (ISO код)
    var country: String { didSet { save() } }

    var spotifyClientID: String { didSet { Keychain.set(spotifyClientID, for: .spotifyClientID); Self.resetSpotify() } }
    var spotifyClientSecret: String { didSet { Keychain.set(spotifyClientSecret, for: .spotifyClientSecret); Self.resetSpotify() } }
    var youtubeAPIKey: String { didSet { Keychain.set(youtubeAPIKey, for: .youtubeAPIKey) } }

    var hasSpotify: Bool { !spotifyClientID.isEmpty && !spotifyClientSecret.isEmpty }
    var hasYouTube: Bool { !youtubeAPIKey.isEmpty }

    static let defaultPriority: [MusicService] = [.appleMusic, .spotify, .youtubeMusic, .youtube, .soundcloud, .yandex, .vk]

    init() {
        let d = UserDefaults.standard
        if let raw = d.stringArray(forKey: "priority") {
            var p = raw.compactMap(MusicService.init(rawValue:))
            // добавляем сервисы, появившиеся в новых версиях
            for s in MusicService.allCases where !p.contains(s) { p.append(s) }
            priority = p
        } else {
            priority = Self.defaultPriority
        }
        country = d.string(forKey: "country") ?? (Locale.current.region?.identifier ?? "US")
        spotifyClientID = Keychain.get(.spotifyClientID) ?? ""
        spotifyClientSecret = Keychain.get(.spotifyClientSecret) ?? ""
        youtubeAPIKey = Keychain.get(.youtubeAPIKey) ?? ""
    }

    private static func resetSpotify() { Task { await SpotifySearch.shared.resetToken() } }

    private func save() {
        UserDefaults.standard.set(priority.map(\.rawValue), forKey: "priority")
        UserDefaults.standard.set(country, forKey: "country")
    }
}
