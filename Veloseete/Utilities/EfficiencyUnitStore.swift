import Combine
import Foundation
import WidgetKit

/// Persisted efficiency display preference (App Group → widgets stay in sync).
@MainActor
final class EfficiencyUnitStore: ObservableObject {
    static let shared = EfficiencyUnitStore()

    @Published var unit: EfficiencyUnit {
        didSet {
            guard unit != oldValue else { return }
            EfficiencyFormat.current = unit
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private init() {
        unit = EfficiencyFormat.current
    }

    func set(_ next: EfficiencyUnit) {
        unit = next
    }

    func toggle() {
        unit = unit == .litersPer100km ? .kmPerLiter : .litersPer100km
    }
}
