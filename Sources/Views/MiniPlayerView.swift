import SwiftUI

struct MiniPlayerView: View {
    static let height: CGFloat = 84

    @Environment(PlayerController.self) private var player

    var body: some View {
        if let track = player.current {
            HStack(spacing: 12) {
                if let vid = player.youtubeVideoID {
                    YouTubePlayerView(
                        videoID: vid,
                        onEnded: { player.youtubeEnded() },
                        onError: { code in
                            // 101/150 — владелец запретил встраивание → открываем в YouTube
                            if code == 101 || code == 150 || code == 153,
                               let u = URL(string: "https://www.youtube.com/watch?v=\(vid)") {
                                player.statusMessage = "Видео нельзя встроить — открываю YouTube"
                                player.openURL(u)
                            }
                        }
                    )
                    .frame(width: 112, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ArtworkView(url: track.artworkURL, size: 52)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let msg = player.statusMessage {
                        Text(msg).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    } else if let s = player.currentService {
                        HStack(spacing: 4) {
                            ServiceBadge(service: s)
                            if player.queue.count > 1 {
                                Text("\(player.index + 1) из \(player.queue.count)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 4)

                HStack(spacing: 16) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        .disabled(!player.hasPrevious)
                    Button { player.togglePause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                        .disabled(!player.hasNext)
                    Button { player.stop() } label: { Image(systemName: "xmark").font(.caption) }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.height - 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }
}
