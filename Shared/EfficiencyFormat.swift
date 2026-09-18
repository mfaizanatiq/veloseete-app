import Foundation

/// Display unit for fuel economy. Canonical metrics stay in L/100km; this only
/// changes how values are shown.
enum EfficiencyUnit: String, CaseIterable, Identifiable, Codable {
    case litersPer100km = "L100"
    case kmPerLiter = "kmL"

    var id: String { rawValue }

    /// Compact unit chip — hero / HUD / widgets.
    var shortLabel: String {
        switch self {
        case .litersPer100km: return "L/100"
        case .kmPerLiter: return "km/L"
        }
    }

    /// Full label for cards and settings.
    var fullLabel: String {
        switch self {
        case .litersPer100km: return "L/100km"
        case .kmPerLiter: return "km/L"
        }
    }

    var settingsTitle: String {
        switch self {
        case .litersPer100km: return "Litres / 100 km"
        case .kmPerLiter: return "Kilometres / litre"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .litersPer100km: return "Litres per 100 kilometres"
        case .kmPerLiter: return "Kilometres per litre"
        }
    }

    /// Higher display numbers are better for km/L; lower for L/100km.
    var higherIsBetter: Bool { self == .kmPerLiter }
}

/// Format + convert fuel efficiency. Storage/math always use L/100km.
///
/// Exact identities (when distance & fuel are the same totals):
/// - `L/100km = (litres / km) × 100`
/// - `km/L    = km / litres`
/// - `km/L    = 100 / (L/100km)`
enum EfficiencyFormat {
    static let storageKey = "veloseete.efficiencyUnit"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: CarPlayWidgetStateStore.appGroupID) ?? .standard
    }

    static var current: EfficiencyUnit {
        get {
            let raw = defaults.string(forKey: storageKey) ?? EfficiencyUnit.litersPer100km.rawValue
            return EfficiencyUnit(rawValue: raw) ?? .litersPer100km
        }
        set {
            defaults.set(newValue.rawValue, forKey: storageKey)
        }
    }

    // MARK: Canonical formulas (from distance + fuel)

    static func litersPer100km(distanceKm: Double, fuelLiters: Double) -> Double? {
        guard distanceKm.isFinite, fuelLiters.isFinite,
              distanceKm > 0, fuelLiters > 0 else { return nil }
        return (fuelLiters / distanceKm) * 100.0
    }

    static func kmPerLiter(distanceKm: Double, fuelLiters: Double) -> Double? {
        guard distanceKm.isFinite, fuelLiters.isFinite,
              distanceKm > 0, fuelLiters > 0 else { return nil }
        return distanceKm / fuelLiters
    }

    static func litersPer100km(totalDistanceKm: Double, totalFuelLiters: Double) -> Double? {
        litersPer100km(distanceKm: totalDistanceKm, fuelLiters: totalFuelLiters)
    }

    static func kmPerLiter(totalDistanceKm: Double, totalFuelLiters: Double) -> Double? {
        kmPerLiter(distanceKm: totalDistanceKm, fuelLiters: totalFuelLiters)
    }

    // MARK: Unit conversion (from canonical L/100km)

    /// `Total km / Total L` when converting from L/100km: `100 / L100`.
    static func toDisplay(_ litersPer100km: Double, unit: EfficiencyUnit = current) -> Double? {
        guard litersPer100km.isFinite, litersPer100km > 0 else { return nil }
        switch unit {
        case .litersPer100km:
            return litersPer100km
        case .kmPerLiter:
            return 100.0 / litersPer100km
        }
    }

    /// Inverse — useful if a UI ever edits display values.
    static func toLitersPer100km(_ displayValue: Double, unit: EfficiencyUnit) -> Double? {
        guard displayValue.isFinite, displayValue > 0 else { return nil }
        switch unit {
        case .litersPer100km:
            return displayValue
        case .kmPerLiter:
            return 100.0 / displayValue
        }
    }

    static func displayNumber(
        _ litersPer100km: Double?,
        unit: EfficiencyUnit = current,
        decimals: Int = 1
    ) -> String {
        guard let litersPer100km, let value = toDisplay(litersPer100km, unit: unit) else {
            return "–.–"
        }
        return String(format: "%.\(decimals)f", value)
    }

    static func format(
        _ litersPer100km: Double?,
        unit: EfficiencyUnit = current,
        decimals: Int = 1,
        style: LabelStyle = .full
    ) -> String {
        guard let litersPer100km, let value = toDisplay(litersPer100km, unit: unit) else {
            return "–.–"
        }
        let label = style == .short ? unit.shortLabel : unit.fullLabel
        return String(format: "%.\(decimals)f %@", value, label)
    }

    enum LabelStyle {
        case short
        case full
    }

    /// Comparisons stay in L/100km — lower consumption always wins.
    static func isBetterThanSpec(currentL100: Double, standardL100: Double) -> Bool {
        currentL100 <= standardL100
    }

    /// Signed % vs brochure in L/100km space. Negative = better (uses less fuel).
    static func deviationPercent(currentL100: Double, standardL100: Double) -> Double {
        guard standardL100 > 0 else { return 0 }
        return ((currentL100 - standardL100) / standardL100) * 100
    }
}
