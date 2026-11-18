import Foundation

/// Поиск по каталогу Apple Music через публичный iTunes Search API.
/// Ключ и платный аккаунт разработчика не нужны.
struct AppleMusicSearch {
    struct Response: Decodable { let results: [Item] }
    struct Item: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let trackViewUrl: String?
        let trackTimeMillis: Int?
    }

    func search(_ term: String, country: String) async throws -> [UnifiedTrack] {
        let url = HTTP.url("https://itunes.apple.com/search", [
            "term": term, "entity": "song", "limit": "25", "country": country.lowercased()
        ])
        let resp: Response = try await HTTP.get(url, service: "Apple Music")
        return resp.results.compactMap { item in
            guard let id = item.trackId, let name = item.trackName,
                  let link = item.trackViewUrl.flatMap(URL.init(string:)) else { return nil }
            let art = item.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600")
            return UnifiedTrack(
                title: name,
                artist: item.artistName ?? "",
                album: item.collectionName,
                artworkURL: art.flatMap(URL.init(string:)),
                durationMs: item.trackTimeMillis,
                links: [.appleMusic: ServiceLink(url: link, nativeID: String(id))]
            )
        }
    }
}
