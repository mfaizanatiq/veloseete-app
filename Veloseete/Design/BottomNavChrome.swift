import SwiftUI

/// Drives bottom-nav compact/expanded state from scroll direction.
@MainActor
final class BottomNavChrome: ObservableObject {
    @Published private(set) var isCompact = false

    private var lastOffset: CGFloat = 0
    private var lastDirectionChange: Date = .distantPast

    func report(offset: CGFloat) {
        let delta = offset - lastOffset
        defer { lastOffset = offset }

        // Ignore tiny jitter
        guard abs(delta) > 4 else { return }

        // Near top → always expand
        if offset <= 24 {
            setCompact(false)
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDirectionChange) > 0.08 else { return }

        if delta > 6 {
            // Scrolling down
            setCompact(true)
            lastDirectionChange = now
        } else if delta < -6 {
            // Scrolling up
            setCompact(false)
            lastDirectionChange = now
        }
    }

    func reset() {
        lastOffset = 0
        setCompact(false)
    }

    private func setCompact(_ value: Bool) {
        guard isCompact != value else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            isCompact = value
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Reports vertical scroll offset to `BottomNavChrome` for pill shrink/expand.
    func tracksBottomNavScroll() -> some View {
        modifier(BottomNavScrollTracker())
    }
}

private struct BottomNavScrollTracker: ViewModifier {
    @EnvironmentObject private var navChrome: BottomNavChrome

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("bottomNavScroll")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                navChrome.report(offset: offset)
            }
    }
}
