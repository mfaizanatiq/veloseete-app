import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    /// Fraction of the screen the video occupies. Lower = smaller logo.
    private let scale: CGFloat = 0.6

    /// Match the splash mp4 plate (#050505) — not brand green — so no letterbox mask.
    private static let plate = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.plate.ignoresSafeArea()

                SplashVideoPlayer(resourceName: "VeloseeteSplash", onFinished: onFinished)
                    .frame(
                        width: proxy.size.width * scale,
                        height: proxy.size.height * scale
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Self.plate.ignoresSafeArea())
        .ignoresSafeArea()
        .accessibilityHidden(true)
        // Hard ceiling so a stalled AVPlayer never leaves a black screen.
        .task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            onFinished()
        }
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
        // Same plate as SplashView so aspect-fit bars don't show green.
        view.backgroundColor = UIColor(red: 5 / 255, green: 5 / 255, blue: 5 / 255, alpha: 1)
        view.playerLayer.backgroundColor = UIColor(red: 5 / 255, green: 5 / 255, blue: 5 / 255, alpha: 1).cgColor

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4", subdirectory: "Media")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            DispatchQueue.main.async { context.coordinator.finish() }
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
        private var failObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?
        private var didFinish = false

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func finish() {
            guard !didFinish else { return }
            didFinish = true
            onFinished()
        }

        func observe(player: AVPlayer) {
            guard let item = player.currentItem else {
                finish()
                return
            }

            playbackObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.finish()
            }

            failObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.finish()
            }

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .failed {
                    DispatchQueue.main.async { self?.finish() }
                }
            }
        }

        func stopObserving() {
            if let playbackObserver {
                NotificationCenter.default.removeObserver(playbackObserver)
                self.playbackObserver = nil
            }
            if let failObserver {
                NotificationCenter.default.removeObserver(failObserver)
                self.failObserver = nil
            }
            statusObservation?.invalidate()
            statusObservation = nil
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
