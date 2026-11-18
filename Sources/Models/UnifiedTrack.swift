import Foundation

struct ServiceLink: Codable, Hashable {
    var url: URL
    /// ID трека внутри сервиса (store id Apple, id Spotify, videoId YouTube)
    var nativeID: String?
}

/// Один трек, «склеенный» из нескольких сервисов.
struct UnifiedTrack: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var artist: String
    var album: String?
    var artworkURL: URL?
    var durationMs: Int?
    var links: [MusicService: ServiceLink] = [:]
    /// Уже искали трек во всех сервисах через song.link
    var enriched = false

    var availableServices: [MusicService] {
        MusicService.allCases.filter { links[$0] != nil }
    }

    var searchQuery: String { "\(artist) \(title)" }

    /// Подходит ли другой трек как «тот же самый»
    func matches(_ other: UnifiedTrack) -> Bool {
        let t1 = Normalizer.title(title), t2 = Normalizer.title(other.title)
        guard !t1.isEmpty, t1 == t2 else { return false }
        let a1 = Normalizer.artist(artist), a2 = Normalizer.artist(other.artist)
        if a1.isEmpty || a2.isEmpty { return true }
        return a1 == a2 || a1.contains(a2) || a2.contains(a1)
    }

    mutating func merge(_ other: UnifiedTrack) {
        for (service, link) in other.links where links[service] == nil {
            links[service] = link
        }
        if artworkURL == nil { artworkURL = other.artworkURL }
        if album == nil { album = other.album }
        if durationMs == nil { durationMs = other.durationMs }
    }
}

enum Normalizer {
    private static let junk = [
        "official music video", "official video", "official audio", "lyric video", "lyrics",
        "audio", "video", "hd", "hq", "4k", "remastered", "remaster", "explicit", "clean"
    ]

    static func title(_ s: String) -> String {
        var t = s.lowercased()
        // убираем содержимое скобок: (feat. X), [Official Video] ...
        t = t.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        // "Song - Remastered 2011"
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        t = t.replacingOccurrences(of: #"\b(feat|ft)\.?\s.*$"#, with: "", options: .regularExpression)
        for j in junk {
            t = t.replacingOccurrences(of: "\\b\(j)\\b", with: " ", options: .regularExpression)
        }
        return clean(t)
    }

    static func artist(_ s: String) -> String {
        var a = s.lowercased()
        for suffix in [" - topic", "vevo", " official"] { a = a.replacingOccurrences(of: suffix, with: "") }
        // берём только первого исполнителя
        a = a.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? a
        a = a.components(separatedBy: " feat").first ?? a
        a = a.components(separatedBy: " x ").first ?? a
        return clean(a)
    }

    private static func clean(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filtered = String(s.unicodeScalars.filter { allowed.contains($0) })
        return filtered.split(separator: " ").joined(separator: " ")
    }

    /// YouTube: "Artist - Title (Official Video)" → (artist, title)
    static func splitYouTubeTitle(_ title: String, channel: String) -> (artist: String, title: String) {
        for sep in [" - ", " – ", " — "] {
            if let r = title.range(of: sep) {
                return (String(title[..<r.lowerBound]), String(title[r.upperBound...]))
            }
        }
        let ch = channel.replacingOccurrences(of: " - Topic", with: "").replacingOccurrences(of: "VEVO", with: "")
        return (ch, title)
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var tracks: [UnifiedTrack] = []
}
