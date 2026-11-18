import Foundation
import Observation

/// Ищет одновременно во всех подключённых сервисах и склеивает одинаковые треки.
@MainActor @Observable
final class SearchEngine {
    var results: [UnifiedTrack] = []
    var isSearching = false
    var errors: [String] = []

    private let settings: AppSettings
    @ObservationIgnored private var currentTask: Task<Void, Never>?

    init(settings: AppSettings) { self.settings = settings }

    func search(_ query: String) {
        currentTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; errors = []; return }

        isSearching = true
        errors = []
        let country = settings.country
        let useSpotify = settings.hasSpotify
        let useYouTube = settings.hasYouTube
        let order = settings.priority

        currentTask = Task {
            var batches: [MusicService: [UnifiedTrack]] = [:]
            var errs: [String] = []

            await withTaskGroup(of: (MusicService, Result<[UnifiedTrack], Error>).self) { group in
                group.addTask { (.appleMusic, await Self.run { try await AppleMusicSearch().search(q, country: country) }) }
                if useSpotify {
                    group.addTask { (.spotify, await Self.run { try await SpotifySearch.shared.search(q) }) }
                }
                if useYouTube {
                    group.addTask { (.youtube, await Self.run { try await YouTubeSearch().search(q) }) }
                }
                for await (service, result) in group {
                    switch result {
                    case .success(let tracks): batches[service] = tracks
                    case .failure(let e): errs.append(e.localizedDescription)
                    }
                }
            }
            guard !Task.isCancelled else { return }

            // Склеиваем: сначала сервисы с высшим приоритетом — их метаданные главные.
            var merged: [UnifiedTrack] = []
            for service in order {
                for track in batches[service] ?? [] {
                    if let i = merged.firstIndex(where: { $0.matches(track) }) {
                        merged[i].merge(track)
                    } else {
                        merged.append(track)
                    }
                }
            }
            self.results = merged
            self.errors = errs
            self.isSearching = false
        }
    }

    nonisolated private static func run(_ body: () async throws -> [UnifiedTrack]) async -> Result<[UnifiedTrack], Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    /// Найти трек во ВСЕХ сервисах через song.link (по любой известной ссылке).
    func enrich(_ track: UnifiedTrack) async throws -> UnifiedTrack {
        guard !track.enriched else { return track }
        // Ссылки Apple/Spotify song.link распознаёт надёжнее, чем YouTube
        let pref: [MusicService] = [.appleMusic, .spotify, .youtubeMusic, .youtube, .soundcloud, .yandex]
        var t = track
        // Нет ни одной ссылки (например, трек из медиатеки Mac) — сначала находим его в Apple Music
        if t.links.isEmpty {
            let candidates = try await AppleMusicSearch().search(t.searchQuery, country: settings.country)
            if let match = candidates.first(where: { $0.matches(t) }) { t.merge(match) }
        }
        guard let link = pref.compactMap({ t.links[$0]?.url }).first else { return t }
        let found = try await Odesli().resolve(link, country: settings.country)
        t.merge(found)
        t.enriched = true
        if let i = results.firstIndex(where: { $0.id == track.id }) { results[i] = t }
        return t
    }
}
