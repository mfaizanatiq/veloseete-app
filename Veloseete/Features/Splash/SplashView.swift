import AVFoundation
import SwiftUI
import UIKit

/// How much of the splash a launch gets.
enum SplashMode: Equatable {
    /// First launch on this install or version — the whole animation.
    case full
    /// Every other cold launch — sped up, and gone as soon as the app is ready.
    case quick
    /// Opened from a notification, Live Activity or widget — straight to the app.
    case skip

    var playbackRate: Float { self == .full ? 1 : 2 }

    /// Hard ceiling so a stalled AVPlayer never leaves a black screen.
    var maximumSeconds: Double { self == .full ? 6 : 3 }

    /// Quick mode holds at least this long so it reads as a beat, not a flash.
    static let quickMinimumSeconds: Double = 0.8
}

/// Decides the splash for this launch and remembers which version saw the full one.
@MainActor
final class SplashCoordinator: ObservableObject {
    static let shared = SplashCoordinator()

    private static let lastFullVersionKey = "veloseete.splash.lastFullVersion"

    @Published private(set) var mode: SplashMode
    @Published private(set) var isShowing = true
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        let current = Self.versionString(bundle: bundle)
        mode = Self.mode(lastFullVersion: defaults.string(forKey: Self.lastFullVersionKey), currentVersion: current)
        if mode == .full {
            // Saved up front: killing the app mid-animation shouldn't replay it forever.
            defaults.set(current, forKey: Self.lastFullVersionKey)
        }
    }

    static func mode(lastFullVersion: String?, currentVersion: String) -> SplashMode {
        lastFullVersion == currentVersion ? .quick : .full
    }

    /// "1.4 (37)" — a new TestFlight build counts as an update too.
    static func versionString(bundle: Bundle) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// The launch came from something the person tapped — get out of the way.
    func skip() {
        guard isShowing else { return }
        mode = .skip
        finish()
    }

    func finish() {
        guard isShowing else { return }
        withAnimation(.easeOut(duration: mode == .skip ? 0.15 : 0.3)) {
            isShowing = false
        }
    }
}

struct SplashView: View {
    let mode: SplashMode
    /// Auth resolved and data on screen underneath — quick mode can leave.
    let isAppReady: Bool
    let onFinished: () -> Void

    /// Fraction of the screen the video occupies. Lower = smaller logo.
    private let scale: CGFloat = 0.6

    /// Match the splash mp4 plate (#050505) — not brand green — so no letterbox mask.
    static let plate = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)

    @State private var appeared = Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.plate.ignoresSafeArea()

                SplashVideoPlayer(
                    resourceName: "VeloseeteSplash",
                    rate: mode.playbackRate,
                    onFinished: onFinished
                )
                .frame(
                    width: proxy.size.width * scale,
                    height: proxy.size.height * scale
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Self.plate.ignoresSafeArea())
        .ignoresSafeArea()
        // Any tap skips — the animation is a greeting, not a gate.
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(mode.maximumSeconds * 1_000_000_000))
            onFinished()
        }
        .task(id: isAppReady) {
            guard mode == .quick, isAppReady else { return }
            let remaining = SplashMode.quickMinimumSeconds - Date().timeIntervalSince(appeared)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

private struct SplashVideoPlayer: UIViewRepresentable {
    let resourceName: String
    var rate: Float = 1
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
        player.playImmediately(atRate: rate)
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
