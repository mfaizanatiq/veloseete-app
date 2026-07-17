import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    /// Fraction of the screen the video occupies. Lower = smaller logo.
    private let scale: CGFloat = 0.6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)
                    .ignoresSafeArea()

                SplashVideoPlayer(resourceName: "VeloseeteSplash", onFinished: onFinished)
                    .frame(
                        width: proxy.size.width * scale,
                        height: proxy.size.height * scale
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct SplashVideoPlayer: UIViewRepresentable {
    let resourceName: String
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = UIColor(red: 5 / 255, green: 5 / 255, blue: 5 / 255, alpha: 1)

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4", subdirectory: "Media")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            DispatchQueue.main.async { onFinished() }
            return view
        }

        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        context.coordinator.observe(player: player)
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        coordinator.stopObserving()
    }

    final class Coordinator {
        private let onFinished: () -> Void
        private var playbackObserver: NSObjectProtocol?

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func observe(player: AVPlayer) {
            guard let item = player.currentItem else { return }
            playbackObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.onFinished()
            }
        }

        func stopObserving() {
            if let playbackObserver {
                NotificationCenter.default.removeObserver(playbackObserver)
                self.playbackObserver = nil
            }
        }

        deinit {
            stopObserving()
        }
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
    }
}
