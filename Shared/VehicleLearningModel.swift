import Foundation

/// Per-vehicle online learning for GPS→dash calibration and tank range.
/// Deterministic EWMA — no ML black boxes. Unit-testable with golden cycles.
struct VehicleLearningState: Codable, Equatable {
    /// Multiplier applied to GPS km between anchors. 1.0 = trust GPS as-is.
    var gpsScale: Double
    /// Successful scale updates (clamped outliers don't count).
    var scaleSampleCount: Int
    /// Last accepted residual: dashDelta − (gpsTracked * previousScale).
    var lastResidualKm: Double
    /// EWMA of full-tank usable range (km).
    var fullTankRangeKm: Double?
    /// Successful full-tank range updates.
    var rangeSampleCount: Int
    /// EWMA of (actualRange − predictedBudget) for residual correction.
    var rangeResidualKm: Double
    var updatedAt: Date

    static let `default` = VehicleLearningState(
        gpsScale: 1.0,
        scaleSampleCount: 0,
        lastResidualKm: 0,
        fullTankRangeKm: nil,
        rangeSampleCount: 0,
        rangeResidualKm: 0,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    /// 0…1 — UI “learning” vs “calibrated”.
    var scaleConfidence: Double {
        min(Double(scaleSampleCount) / 5.0, 1.0)
    }

    var isCalibrated: Bool { scaleSampleCount >= 3 }

    var isLearning: Bool { scaleSampleCount > 0 && scaleSampleCount < 3 }

    var rangeConfidence: Double {
        min(Double(rangeSampleCount) / 4.0, 1.0)
    }
}

enum VehicleLearningModel {
    /// Minimum GPS km in a cycle before we trust a scale observation.
    static let minGpsKmForScale: Double = 40
    /// Reject absurd dash/GPS ratios (typos, missed trips).
    static let scaleClamp: ClosedRange<Double> = 0.85...1.15
    /// Minimum dash advance to treat as a real cycle.
    static let minDashKmForScale: Double = 30
    /// Minimum full-tank range sample.
    static let minRangeKm: Double = 40

    // MARK: - Live odometer

    /// Calibrated live reading: `verified + tracked * gpsScale`.
    static func estimatedKm(
        verifiedKm: Double,
        trackedKm: Double,
        gpsScale: Double
    ) -> Double {
        let scale = clampScale(gpsScale)
        return verifiedKm + max(0, trackedKm) * scale
    }

    static func clampScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1.0 }
        return min(max(scale, scaleClamp.lowerBound), scaleClamp.upperBound)
    }

    static func alpha(forSampleCount count: Int) -> Double {
        count >= 5 ? 0.20 : 0.35
    }

    // MARK: - Scale update

    struct ScaleObservation {
        /// Dash odometer at previous fuel/service anchor.
        var previousDashKm: Double
        /// Dash odometer entered at this refill.
        var newDashKm: Double
        /// Raw GPS (+ pending) km accumulated since previous anchor (unscaled).
        var gpsTrackedKm: Double
    }

    enum ScaleUpdateResult: Equatable {
        case applied(observedScale: Double, newState: VehicleLearningState)
        case rejected(reason: RejectReason, state: VehicleLearningState)

        enum RejectReason: String, Equatable {
            case insufficientGps
            case insufficientDash
            case nonPositiveGps
            case outOfClamp
        }
    }

    static func observeScale(
        _ observation: ScaleObservation,
        state: VehicleLearningState,
        now: Date = Date()
    ) -> ScaleUpdateResult {
        let dashDelta = observation.newDashKm - observation.previousDashKm
        let gps = observation.gpsTrackedKm

        guard gps > 0 else {
            return .rejected(reason: .nonPositiveGps, state: state)
        }
        guard gps >= minGpsKmForScale else {
            return .rejected(reason: .insufficientGps, state: state)
        }
        guard dashDelta >= minDashKmForScale else {
            return .rejected(reason: .insufficientDash, state: state)
        }

        let observed = dashDelta / gps
        guard scaleClamp.contains(observed) else {
            return .rejected(reason: .outOfClamp, state: state)
        }

        let a = alpha(forSampleCount: state.scaleSampleCount)
        let previousScale = clampScale(state.gpsScale)
        let newScale = clampScale(a * observed + (1 - a) * previousScale)
        let residual = dashDelta - (gps * previousScale)

        var next = state
        next.gpsScale = newScale
        next.scaleSampleCount += 1
        next.lastResidualKm = residual
        next.updatedAt = now
        return .applied(observedScale: observed, newState: next)
    }

    // MARK: - Range update

    struct RangeObservation {
        var actualRangeKm: Double
        var fuelLiters: Double
        var isFullTankCycle: Bool
        /// Budget that was predicted for this cycle (if any).
        var predictedBudgetKm: Double?
    }

    static func observeRange(
        _ observation: RangeObservation,
        state: VehicleLearningState,
        now: Date = Date()
    ) -> VehicleLearningState {
        guard observation.isFullTankCycle,
              observation.actualRangeKm >= minRangeKm,
              observation.fuelLiters > 0 else {
            return state
        }

        var next = state
        let a = alpha(forSampleCount: state.rangeSampleCount)
        if let existing = state.fullTankRangeKm {
            next.fullTankRangeKm = a * observation.actualRangeKm + (1 - a) * existing
        } else {
            next.fullTankRangeKm = observation.actualRangeKm
        }
        next.rangeSampleCount += 1

        if let predicted = observation.predictedBudgetKm, predicted > 0 {
            let error = observation.actualRangeKm - predicted
            next.rangeResidualKm = a * error + (1 - a) * state.rangeResidualKm
        }
        next.updatedAt = now
        return next
    }

    /// Blend learned full-tank range with volume/efficiency/pattern candidates.
    static func rangeBudgetKm(
        state: VehicleLearningState,
        lastFillLiters: Double,
        isFullTank: Bool,
        litersPer100km: Double,
        patternTypicalRangeKm: Double?,
        patternSampleCount: Int = 0,
        tankCapacityLiters: Double?
    ) -> (km: Double, confidence: Double) {
        let efficiency = max(litersPer100km, 1)
        let volumeRange = lastFillLiters / efficiency * 100

        var candidates: [(km: Double, weight: Double)] = []
        var confidence = 0.35

        if let learned = state.fullTankRangeKm, state.rangeSampleCount > 0, learned > 30 {
            if isFullTank {
                let learnedWeight = state.rangeSampleCount >= 3 ? 2.8 : 1.4
                candidates.append((learned + state.rangeResidualKm * 0.5, learnedWeight))
                confidence = max(confidence, 0.55 + 0.35 * state.rangeConfidence)
            } else {
                // Scale learned full-tank range by fill fraction when tank known.
                if let tank = tankCapacityLiters, tank > 5 {
                    let fraction = min(max(lastFillLiters / tank, 0.15), 1.0)
                    candidates.append((learned * fraction, 1.0))
                    confidence = max(confidence, 0.5 + 0.25 * state.rangeConfidence)
                }
            }
        }

        if let typical = patternTypicalRangeKm, typical > 30 {
            if isFullTank {
                let patternWeight = state.rangeSampleCount >= 3 ? 0.45 : 1.0
                candidates.append((typical, patternWeight))
                if patternSampleCount >= 3 {
                    confidence = max(confidence, 0.85)
                } else if patternSampleCount >= 2 {
                    confidence = max(confidence, 0.7)
                } else {
                    confidence = max(confidence, 0.65)
                }
            } else {
                candidates.append((min(typical, volumeRange), 1.0))
                confidence = max(confidence, patternSampleCount >= 3 ? 0.7 : 0.55)
            }
        } else if state.rangeSampleCount == 0 {
            candidates.append((volumeRange, 0.8))
        }

        if isFullTank, let tank = tankCapacityLiters, tank > 5 {
            let tankRange = tank / efficiency * 100
            let tankWeight = state.rangeSampleCount >= 3 ? 0.35 : 0.7
            candidates.append((tankRange, tankWeight))
            confidence = max(confidence, 0.7)
        } else if !isFullTank, let tank = tankCapacityLiters, tank > 5 {
            let capped = min(volumeRange, tank / efficiency * 100)
            candidates.append((capped, 1.0))
        }

        let volumeWeight: Double = {
            if isFullTank {
                return state.rangeSampleCount >= 3 ? 0.25 : 0.5
            }
            return 1.0
        }()
        candidates.append((volumeRange, volumeWeight))

        let weighted = candidates.reduce(0.0) { $0 + $1.km * $1.weight }
        let weightSum = candidates.reduce(0.0) { $0 + $1.weight }
        let km = weightSum > 0 ? weighted / weightSum : volumeRange

        if state.rangeSampleCount < 2 && patternSampleCount < 2 {
            confidence = min(confidence, 0.5)
        }

        return (max(km, 20), confidence)
    }
}
