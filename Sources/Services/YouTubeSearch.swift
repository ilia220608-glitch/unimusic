import Foundation

/// Поиск музыки на YouTube через YouTube Data API v3.
/// Ключ бесплатно создаётся в console.cloud.google.com (YouTube Data API v3).
struct YouTubeSearch {
    struct Response: Decodable { let items: [Item] }
    struct Item: Decodable { let id: ID; let snippet: Snippet }
    struct ID: Decodable { let videoId: String? }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let thumbnails: [String: Thumb]
    }
    struct Thumb: Decodable { let url: String }

    func search(_ term: String) async throws -> [UnifiedTrack] {
        guard let key = Keychain.get(.youtubeAPIKey), !key.isEmpty else {
            throw HTTPError.missingKey("YouTube")
        }
        let url = HTTP.url("https://www.googleapis.com/youtube/v3/search", [
            "part": "snippet", "type": "video", "videoCategoryId": "10",
            "maxResults": "15", "q": term, "key": key
        ])
        let resp: Response = try await HTTP.get(url, service: "YouTube")
        return resp.items.compactMap { item in
            guard let vid = item.id.videoId,
                  let link = URL(string: "https://www.youtube.com/watch?v=\(vid)") else { return nil }
            let title = item.snippet.title.htmlDecoded
            let parts = Normalizer.splitYouTubeTitle(title, channel: item.snippet.channelTitle)
            let thumb = item.snippet.thumbnails["high"] ?? item.snippet.thumbnails["default"]
            return UnifiedTrack(
                title: parts.title.trimmingCharacters(in: .whitespaces),
                artist: parts.artist.trimmingCharacters(in: .whitespaces),
                artworkURL: thumb.flatMap { URL(string: $0.url) },
                links: [.youtube: ServiceLink(url: link, nativeID: vid)]
            )
        }
    }
}

extension String {
    /// YouTube возвращает заголовки с HTML-сущностями (&amp; &#39;)
    var htmlDecoded: String {
        var s = self
        let map = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&#039;": "'"]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
