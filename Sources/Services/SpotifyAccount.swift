import Foundation
import CryptoKit
import AuthenticationServices
import Observation
import SwiftUI

/// Вход в аккаунт Spotify (OAuth PKCE): нужен только Client ID, Secret не нужен.
/// В Spotify Dashboard надо добавить Redirect URI:  unimusic://spotify-callback
@MainActor @Observable
final class SpotifyAccount {
    static let redirectURI = "unimusic://spotify-callback"
    static let scopes = "playlist-read-private playlist-read-collaborative user-library-read"

    var isLoggedIn: Bool
    var userName: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var expiry = Date.distantPast
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        isLoggedIn = Keychain.get(.spotifyRefreshToken) != nil
    }

    // MARK: - Вход / выход

    func login(using session: WebAuthenticationSession) async throws {
        let clientID = settings.spotifyClientID.trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else { throw HTTPError.missingKey("Spotify") }

        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = UUID().uuidString

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state)
        ]
        let callback = try await session.authenticate(using: c.url!, callbackURLScheme: "unimusic")
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyError.auth(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.auth("нет кода авторизации")
        }
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        isLoggedIn = true
        await loadProfile()
    }

    func logout() {
        Keychain.set("", for: .spotifyRefreshToken)
        accessToken = nil
        isLoggedIn = false
        userName = nil
    }

    func loadProfile() async {
        struct Me: Decodable { let display_name: String?; let id: String }
        if let me: Me = try? await get(URL(string: "https://api.spotify.com/v1/me")!) {
            userName = me.display_name ?? me.id
        }
    }

    // MARK: - Токены

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private func requestToken(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(params.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw SpotifyError.auth(String(data: data, encoding: .utf8) ?? "ошибка токена")
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = t.access_token
        expiry = Date().addingTimeInterval(TimeInterval(t.expires_in - 60))
        if let r = t.refresh_token { Keychain.set(r, for: .spotifyRefreshToken) }
    }

    private func validToken() async throws -> String {
        if let accessToken, expiry > Date() { return accessToken }
        guard let refresh = Keychain.get(.spotifyRefreshToken) else {
            isLoggedIn = false
            throw SpotifyError.auth("войдите в Spotify")
        }
        do {
            try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": settings.spotifyClientID
            ])
        } catch {
            logout()
            throw error
        }
        return accessToken!
    }

    func get<T: Decodable>(_ url: URL) async throws -> T {
        let token = try await validToken()
        return try await HTTP.get(url, headers: ["Authorization": "Bearer \(token)"], service: "Spotify")
    }

    // MARK: - Медиатека

    struct PlaylistInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let total: Int?
    }

    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]
        let next: String?
    }
    private struct Count: Decodable { let total: Int? }
    private struct PlaylistDTO: Decodable {
        let id: String
        let name: String
        let tracks: Count?
        let items: Count?   // в новых версиях API поле называется items
    }
    private struct EntryDTO: Decodable {
        let track: TrackDTO?
        let item: TrackDTO?
    }
    private struct TrackDTO: Decodable {
        let id: String?
        let name: String?
        let type: String?
        let duration_ms: Int?
        let artists: [SpotifySearch.Artist]?
        let album: SpotifySearch.Album?
        let external_urls: [String: String]?
    }

    private func paged<Item: Decodable>(_ first: URL, max: Int = 5000) async throws -> [Item] {
        var url: URL? = first
        var all: [Item] = []
        while let u = url, all.count < max {
            let page: Page<Item> = try await get(u)
            all += page.items
            url = page.next.flatMap(URL.init(string:))
        }
        return all
    }

    func playlists() async throws -> [PlaylistInfo] {
        let dtos: [PlaylistDTO] = try await paged(URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!)
        return dtos.map { PlaylistInfo(id: $0.id, name: $0.name, total: $0.tracks?.total ?? $0.items?.total) }
    }

    /// id == nil → «Любимые треки»
    func tracks(playlistID: String?) async throws -> [UnifiedTrack] {
        let entries: [EntryDTO]
        if let id = playlistID {
            do {
                entries = try await paged(URL(string: "https://api.spotify.com/v1/playlists/\(id)/items?limit=50")!)
            } catch {
                // старый адрес того же метода
                entries = try await paged(URL(string: "https://api.spotify.com/v1/playlists/\(id)/tracks?limit=100")!)
            }
        } else {
            entries = try await paged(URL(string: "https://api.spotify.com/v1/me/tracks?limit=50")!)
        }
        return entries.compactMap { e in
            guard let t = e.track ?? e.item, let id = t.id, let name = t.name,
                  t.type == nil || t.type == "track",
                  let link = t.external_urls?["spotify"].flatMap(URL.init(string:)) else { return nil }
            return UnifiedTrack(
                title: name,
                artist: (t.artists ?? []).map(\.name).joined(separator: ", "),
                album: t.album?.name,
                artworkURL: t.album?.images.first.flatMap { URL(string: $0.url) },
                durationMs: t.duration_ms,
                links: [.spotify: ServiceLink(url: link, nativeID: id)]
            )
        }
    }

    // MARK: - Утилиты

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

enum SpotifyError: LocalizedError {
    case auth(String)
    var errorDescription: String? {
        switch self { case .auth(let m): "Spotify: \(m)" }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
