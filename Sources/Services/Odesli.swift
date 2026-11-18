import Foundation

/// song.link (Odesli) — по ссылке на трек в ЛЮБОМ сервисе возвращает ссылки
/// на этот же трек во всех остальных. Это и есть «синхронизация» сервисов.
/// Бесплатно, без ключа (лимит ~10 запросов в минуту).
struct Odesli {
    struct Response: Decodable {
        let entityUniqueId: String
        let pageUrl: String?
        let entitiesByUniqueId: [String: Entity]
        let linksByPlatform: [String: PlatformLink]
    }
    struct Entity: Decodable {
        let id: String?
        let type: String?
        let title: String?
        let artistName: String?
        let thumbnailUrl: String?
    }
    struct PlatformLink: Decodable {
        let url: String
        let entityUniqueId: String?
    }

    func resolve(_ link: URL, country: String) async throws -> UnifiedTrack {
        let url = HTTP.url("https://api.song.link/v1-alpha.1/links", [
            "url": link.absoluteString, "userCountry": country.uppercased()
        ])
        let resp: Response = try await HTTP.get(url, service: "song.link")
        let main = resp.entitiesByUniqueId[resp.entityUniqueId]

        var links: [MusicService: ServiceLink] = [:]
        for service in MusicService.allCases {
            guard let key = service.odesliKey, let p = resp.linksByPlatform[key],
                  let u = URL(string: p.url) else { continue }
            // "SPOTIFY_SONG::4uLU6hMCjMI75M1A2tKUQC" → "4uLU6hMCjMI75M1A2tKUQC"
            let native = p.entityUniqueId?.components(separatedBy: "::").last
            links[service] = ServiceLink(url: u, nativeID: native)
        }
        // предпочитаем метаданные Apple/Spotify — они чище, чем у YouTube
        let best = ["appleMusic", "itunes", "spotify"]
            .compactMap { resp.linksByPlatform[$0]?.entityUniqueId }
            .compactMap { resp.entitiesByUniqueId[$0] }
            .first ?? main

        return UnifiedTrack(
            title: best?.title ?? "Без названия",
            artist: best?.artistName ?? "",
            artworkURL: best?.thumbnailUrl.flatMap(URL.init(string:)),
            links: links,
            enriched: true
        )
    }
}
