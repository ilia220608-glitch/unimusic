import Foundation
import Observation
#if os(iOS)
import MediaPlayer
#endif

/// Как именно включить трек
enum PlayAction: Equatable {
    /// iPhone: системный плеер Apple Music по store id
    case appleMusicNative(storeID: String)
    /// Встроенный плеер YouTube внутри приложения
    case youtubeEmbedded(videoID: String)
    /// Открыть приложение / сайт сервиса
    case openExternal(URL)
}

/// Единый плеер: выбирает сервис по приоритету и ведёт очередь,
/// в которой треки могут быть из РАЗНЫХ сервисов.
@MainActor @Observable
final class PlayerController {
    var queue: [UnifiedTrack] = []
    var index: Int = 0
    var currentService: MusicService?
    var youtubeVideoID: String?
    var isPlaying = false
    var statusMessage: String?

    /// Устанавливается из SwiftUI (openURL из Environment)
    @ObservationIgnored var openURL: (URL) -> Void = { _ in }
    @ObservationIgnored private var appleStarted = false

    private let settings: AppSettings
    private let search: SearchEngine
    private let library: LibraryStore

    var current: UnifiedTrack? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }

    init(settings: AppSettings, search: SearchEngine, library: LibraryStore) {
        self.settings = settings
        self.search = search
        self.library = library
        #if os(iOS)
        observeSystemPlayer()
        #endif
    }

    // MARK: - Очередь

    func play(_ track: UnifiedTrack, in list: [UnifiedTrack]? = nil) {
        let list = list ?? [track]
        queue = list
        index = list.firstIndex(where: { $0.id == track.id }) ?? 0
        Task { await startCurrent() }
    }

    /// Принудительно включить в конкретном сервисе
    func play(_ track: UnifiedTrack, on service: MusicService) {
        queue = [track]
        index = 0
        Task { await start(track, forced: service) }
    }

    func next() {
        guard hasNext else { stop(); return }
        index += 1
        Task { await startCurrent() }
    }

    func previous() {
        guard hasPrevious else { return }
        index -= 1
        Task { await startCurrent() }
    }

    func togglePause() {
        #if os(iOS)
        if currentService == .appleMusic {
            let p = MPMusicPlayerController.systemMusicPlayer
            if p.playbackState == .playing { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
            return
        }
        #endif
        if youtubeVideoID != nil {
            isPlaying.toggle()
            YouTubeCommandBus.shared.send(isPlaying ? "playVideo" : "pauseVideo")
        }
    }

    func stop() {
        #if os(iOS)
        if currentService == .appleMusic { MPMusicPlayerController.systemMusicPlayer.stop() }
        #endif
        youtubeVideoID = nil
        isPlaying = false
        currentService = nil
        queue = []
        index = 0
    }

    /// Вызывается встроенным YouTube-плеером, когда видео закончилось
    func youtubeEnded() { if hasNext { next() } else { isPlaying = false } }

    // MARK: - Выбор сервиса

    private func startCurrent() async {
        guard let track = current else { return }
        await start(track, forced: nil)
    }

    private func start(_ original: UnifiedTrack, forced: MusicService?) async {
        var track = original
        statusMessage = nil

        // Если нет ссылки на нужный/приоритетный сервис — ищем трек в остальных через song.link
        let wanted = forced ?? settings.priority.first
        if let wanted, track.links[wanted] == nil, !track.enriched {
            statusMessage = "Ищу трек в других сервисах…"
            if let enriched = try? await search.enrich(track) {
                track = enriched
                if queue.indices.contains(index) { queue[index] = enriched }
                library.update(enriched)
            }
            statusMessage = nil
        }
        guard current?.id == original.id else { return } // пользователь уже переключил трек

        let services = forced.map { [$0] } ?? settings.priority
        for service in services {
            guard let link = track.links[service] else { continue }
            perform(action(for: service, link: link), service: service)
            return
        }
        // нигде нет точной ссылки — открываем поиск в первом сервисе
        if let fallback = (forced ?? settings.priority.first)?.searchURL(for: track.searchQuery) {
            statusMessage = "Точного совпадения нет — открываю поиск"
            perform(.openExternal(fallback), service: forced ?? settings.priority.first!)
        }
    }

    private func action(for service: MusicService, link: ServiceLink) -> PlayAction {
        switch service {
        case .appleMusic:
            #if os(iOS)
            if let id = link.nativeID { return .appleMusicNative(storeID: id) }
            #endif
            return .openExternal(Self.appleMusicAppURL(link.url))
        case .youtube:
            if let id = link.nativeID { return .youtubeEmbedded(videoID: id) }
            return .openExternal(link.url)
        case .spotify:
            if let id = link.nativeID, let u = URL(string: "spotify:track:\(id)") { return .openExternal(u) }
            return .openExternal(link.url)
        default:
            return .openExternal(link.url)
        }
    }

    private func perform(_ action: PlayAction, service: MusicService) {
        // глушим предыдущий источник
        if service != .youtube { youtubeVideoID = nil }
        #if os(iOS)
        if service != .appleMusic, currentService == .appleMusic {
            MPMusicPlayerController.systemMusicPlayer.pause()
        }
        #endif
        currentService = service

        switch action {
        case .appleMusicNative(let storeID):
            #if os(iOS)
            playAppleMusic(storeID: storeID)
            #else
            _ = storeID
            #endif
        case .youtubeEmbedded(let id):
            youtubeVideoID = id
            isPlaying = true
        case .openExternal(let url):
            isPlaying = false
            openURL(url)
        }
    }

    /// На Mac ссылку music.apple.com открываем сразу в приложении «Музыка»
    private static func appleMusicAppURL(_ url: URL) -> URL {
        #if os(macOS)
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "music"
        return c?.url ?? url
        #else
        return url
        #endif
    }

    // MARK: - Apple Music на iPhone

    #if os(iOS)
    private func playAppleMusic(storeID: String) {
        MPMediaLibrary.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.statusMessage = "Разрешите доступ к Apple Music в Настройках iPhone"
                    return
                }
                let player = MPMusicPlayerController.systemMusicPlayer
                player.repeatMode = .none
                player.setQueue(with: [storeID])
                player.prepareToPlay { error in
                    Task { @MainActor in
                        if let error {
                            self.statusMessage = "Apple Music: \(error.localizedDescription)"
                            return
                        }
                        player.play()
                        self.isPlaying = true
                        self.appleStarted = true
                    }
                }
            }
        }
    }

    private func observeSystemPlayer() {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemPlayerStateChanged() }
        }
    }

    /// Трек Apple Music закончился → переходим к следующему в смешанной очереди
    private func systemPlayerStateChanged() {
        guard currentService == .appleMusic, appleStarted else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        switch player.playbackState {
        case .playing: isPlaying = true
        case .stopped:
            appleStarted = false
            isPlaying = false
            if hasNext { next() }
        case .paused:
            isPlaying = false
            // при окончании очереди плеер часто уходит в paused с позицией 0
            if player.currentPlaybackTime < 0.5, player.nowPlayingItem == nil || player.indexOfNowPlayingItem == NSNotFound {
                appleStarted = false
                if hasNext { next() }
            }
        default: break
        }
    }
    #endif
}
