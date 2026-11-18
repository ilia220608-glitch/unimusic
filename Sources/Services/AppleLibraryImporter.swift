import Foundation
#if os(iOS)
import MediaPlayer
#else
import iTunesLibrary
#endif

/// Плейлисты из медиатеки Apple Music на этом устройстве.
/// Работает без платного аккаунта разработчика:
///  • iPhone — через MediaPlayer (как в приложении «Музыка»)
///  • Mac — через iTunesLibrary (медиатека приложения «Музыка»)
struct LocalPlaylist: Identifiable {
    let id: String
    let name: String
    let count: Int
    let load: () -> [UnifiedTrack]
}

enum AppleLibraryError: LocalizedError {
    case denied, failed(String)
    var errorDescription: String? {
        switch self {
        case .denied: "Нет доступа к медиатеке. Разрешите его в Настройках → Конфиденциальность → Медиа и Apple Music."
        case .failed(let m): "Медиатека Apple Music: \(m)"
        }
    }
}

enum AppleLibraryImporter {
    #if os(iOS)
    @MainActor
    static func playlists(country: String) async throws -> [LocalPlaylist] {
        let status = await withCheckedContinuation { c in
            MPMediaLibrary.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw AppleLibraryError.denied }

        var result: [LocalPlaylist] = []
        for case let pl as MPMediaPlaylist in MPMediaQuery.playlists().collections ?? [] {
            result.append(LocalPlaylist(
                id: String(pl.persistentID),
                name: pl.name ?? "Плейлист",
                count: pl.count,
                load: { pl.items.map { convert($0, country: country) } }
            ))
        }
        let songs = MPMediaQuery.songs()
        result.insert(LocalPlaylist(
            id: "all-songs",
            name: "Вся медиатека",
            count: songs.items?.count ?? 0,
            load: { (songs.items ?? []).map { convert($0, country: country) } }
        ), at: 0)
        return result
    }

    private static func convert(_ item: MPMediaItem, country: String) -> UnifiedTrack {
        var links: [MusicService: ServiceLink] = [:]
        let sid = item.playbackStoreID
        if !sid.isEmpty, sid != "0",
           let u = URL(string: "https://music.apple.com/\(country.lowercased())/song/\(sid)") {
            links[.appleMusic] = ServiceLink(url: u, nativeID: sid)
        }
        return UnifiedTrack(
            title: item.title ?? "Без названия",
            artist: item.artist ?? "",
            album: item.albumTitle,
            durationMs: Int(item.playbackDuration * 1000),
            links: links
        )
    }
    #else
    @MainActor
    static func playlists(country: String) async throws -> [LocalPlaylist] {
        let lib: ITLibrary
        do { lib = try ITLibrary(apiVersion: "1.0") }
        catch { throw AppleLibraryError.failed(error.localizedDescription) }

        var result: [LocalPlaylist] = lib.allPlaylists
            .filter { !$0.isMaster && !$0.items.isEmpty }
            .map { pl in
                let items = pl.items
                return LocalPlaylist(
                    id: pl.persistentID.stringValue,
                    name: pl.name,
                    count: items.count,
                    load: { items.map(convert) }
                )
            }
        let all = lib.allMediaItems
        result.insert(LocalPlaylist(id: "all-songs", name: "Вся медиатека", count: all.count,
                                    load: { all.map(convert) }), at: 0)
        return result
    }

    /// На Mac у трека нет ID магазина — ссылки найдутся при первом воспроизведении
    private static func convert(_ item: ITLibMediaItem) -> UnifiedTrack {
        UnifiedTrack(
            title: item.title,
            artist: item.artist?.name ?? "",
            album: item.album.title,
            durationMs: item.totalTime > 0 ? item.totalTime : nil
        )
    }
    #endif
}
