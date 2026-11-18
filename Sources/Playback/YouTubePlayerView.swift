import SwiftUI
import WebKit

/// Позволяет плееру отправлять команды (пауза/play) во встроенный YouTube
@MainActor
final class YouTubeCommandBus {
    static let shared = YouTubeCommandBus()
    weak var webView: WKWebView?
    func send(_ command: String) {
        webView?.evaluateJavaScript("player && player.\(command)();", completionHandler: nil)
    }
}

/// Встроенный плеер YouTube (IFrame API). Сообщает, когда видео закончилось,
/// чтобы автоматически перейти к следующему треку очереди.
struct YouTubePlayerView {
    let videoID: String
    let onEnded: () -> Void
    let onError: (Int) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubePlayerView
        var loadedID: String?
        init(_ parent: YouTubePlayerView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
            switch event {
            case "ended": parent.onEnded()
            case "error": parent.onError(body["code"] as? Int ?? -1)
            default: break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func makeWebView(_ context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "yt")
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #endif
        let web = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        #endif
        YouTubeCommandBus.shared.webView = web
        return web
    }

    fileprivate func load(_ web: WKWebView, _ context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        // baseURL обязателен: без «origin» YouTube отказывается проигрывать встроенное видео
        web.loadHTMLString(Self.html(videoID), baseURL: URL(string: "https://unimusic.local/"))
    }

    private static func html(_ id: String) -> String {
        """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p', {
            videoId: '\(id)',
            playerVars: { autoplay: 1, playsinline: 1, rel: 0, modestbranding: 1, origin: 'https://unimusic.local' },
            events: {
              onReady: function(e){ e.target.playVideo(); },
              onStateChange: function(e){ if(e.data === 0){ window.webkit.messageHandlers.yt.postMessage({event:'ended'}); } },
              onError: function(e){ window.webkit.messageHandlers.yt.postMessage({event:'error', code:e.data}); }
            }
          });
        }
        </script></body></html>
        """
    }
}

#if os(iOS)
extension YouTubePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context) }
    func updateUIView(_ web: WKWebView, context: Context) { load(web, context) }
}
#else
extension YouTubePlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context) }
    func updateNSView(_ web: WKWebView, context: Context) { load(web, context) }
}
#endif
