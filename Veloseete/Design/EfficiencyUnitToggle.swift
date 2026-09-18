import SwiftUI

/// Segmented L/100km ↔ km/L control used on Fuels hero and Profile.
struct EfficiencyUnitToggle: View {
    @ObservedObject private var store = EfficiencyUnitStore.shared
    var compact: Bool = false
    var onAccent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EfficiencyUnit.allCases) { option in
                Button {
                    guard store.unit != option else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    store.set(option)
                } label: {
                    Text(compact ? option.shortLabel : option.fullLabel)
                        .font(VS.Typography.body(compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(labelColor(selected: store.unit == option))
                        .padding(.horizontal, compact ? 10 : 12)
                        .padding(.vertical, compact ? 6 : 8)
                        .background(chipBackground(selected: store.unit == option))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(store.unit == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(trackBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fuel efficiency unit")
    }

    private var trackBackground: some View {
        Capsule()
            .fill(onAccent ? VS.Color.navPill.opacity(0.14) : VS.Color.chip)
    }

    private func chipBackground(selected: Bool) -> some View {
        Capsule()
            .fill(selected
                ? (onAccent ? VS.Color.navPill : VS.Color.accent)
                : Color.clear)
    }

    private func labelColor(selected: Bool) -> Color {
        if onAccent {
            return selected ? VS.Color.accent : VS.Color.navPill.opacity(0.7)
        }
        return selected ? VS.Color.navPill : VS.Color.textSecondary
    }
}
