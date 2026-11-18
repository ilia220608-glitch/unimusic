import Foundation

/// Поиск в Spotify через Web API (Client Credentials).
/// Client ID и Secret бесплатно создаются на developer.spotify.com/dashboard.
actor SpotifySearch {
    static let shared = SpotifySearch()

    private var token: String?
    private var tokenExpiry = Date.distantPast

    struct TokenResponse: Decodable { let access_token: String; let expires_in: Int }
    struct Response: Decodable { let tracks: Tracks }
    struct Tracks: Decodable { let items: [Item] }
    struct Item: Decodable {
        let id: String
        let name: String
        let duration_ms: Int?
        let artists: [Artist]
        let album: Album?
        let external_urls: [String: String]
    }
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let name: String; let images: [Image] }
    struct Image: Decodable { let url: String }

    private func accessToken() async throws -> String {
        if let token, tokenExpiry > Date() { return token }
        guard let id = Keychain.get(.spotifyClientID), !id.isEmpty,
              let secret = Keychain.get(.spotifyClientSecret), !secret.isEmpty else {
            throw HTTPError.missingKey("Spotify")
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let basic = Data("\(id):\(secret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("grant_type=client_credentials".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw HTTPError.status(http.statusCode, "Spotify")
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        token = t.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(t.expires_in - 60))
        return t.access_token
    }

    func search(_ term: String) async throws -> [UnifiedTrack] {
        let token = try await accessToken()
        let url = HTTP.url("https://api.spotify.com/v1/search", ["q": term, "type": "track", "limit": "20"])
        let resp: Response = try await HTTP.get(url, headers: ["Authorization": "Bearer \(token)"], service: "Spotify")
        return resp.tracks.items.compactMap { item in
            guard let link = item.external_urls["spotify"].flatMap(URL.init(string:)) else { return nil }
            return UnifiedTrack(
                title: item.name,
                artist: item.artists.map(\.name).joined(separator: ", "),
                album: item.album?.name,
                artworkURL: item.album?.images.first.flatMap { URL(string: $0.url) },
                durationMs: item.duration_ms,
                links: [.spotify: ServiceLink(url: link, nativeID: item.id)]
            )
        }
    }

    func resetToken() { token = nil }
}
