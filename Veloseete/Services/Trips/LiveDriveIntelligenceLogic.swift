import Foundation

/// Live fuel intelligence for the recording HUD — conservative range, human copy.
enum LiveDriveIntelligenceLogic {
    struct Snapshot: Equatable {
        /// 0 = efficient (right), 1 = thirsty / burning fuel (left).
        var burnPosition: Double
        /// 0…1 visual tank fill when we have enough signal; nil = unknown.
        var tankFillLevel: Double?
        var kmRemaining: Double?
        var timeRemainingSec: Double?
        var confidence: Double
        var showsRangeEstimate: Bool
        var headline: String
        var detail: String
        /// Compact twin-card title, e.g. "786–926 km left".
        var rangeCardTitle: String
        /// Relative fill age for the fuel card, e.g. "Filled 2 days ago".
        var filledAgo: String
    }

    private static let minConfidenceForRange = 0.68

    static func compute(
        logs: [FuelLog],
        estimatedOdometer: Double?,
        tankCapacityLiters: Double?,
        brochureL100km: Double?,
        personalBaselineL100: Double,
        liveEstL100: Double,
        thirst: Double,
        sessionAvgSpeedKmh: Double,
        distanceUnit: String,
        now: Date = Date()
    ) -> Snapshot {
        let burn = burnPosition(
            live: liveEstL100,
            baseline: personalBaselineL100,
            thirst: thirst
        )

        guard let odometer = estimatedOdometer else {
            return learningSnapshot(
                burn: burn,
                live: liveEstL100,
                baseline: personalBaselineL100,
                lastFill: nil,
                now: now
            )
        }

        let vehicleLogs = logs.sorted { $0.timestamp < $1.timestamp }
        guard let lastFill = vehicleLogs.last else {
            return learningSnapshot(
                burn: burn,
                live: liveEstL100,
                baseline: personalBaselineL100,
                lastFill: nil,
                now: now
            )
        }

        let prediction = FuelInsightLogic.predictNextFill(
            logs: vehicleLogs,
            estimatedOdometer: odometer,
            tankCapacityLiters: tankCapacityLiters,
            brochureL100km: brochureL100km,
            now: now
        )

        let fullTankCount = vehicleLogs.filter(\.isFullTank).count
        let canEstimateRange = (prediction?.confidence ?? 0) >= minConfidenceForRange
            && lastFill.isFullTank
            && fullTankCount >= 2
            && (prediction?.kmRemaining ?? 0) > 20

        guard let prediction, canEstimateRange, let baseKmLeft = prediction.kmRemaining else {
            return cautiousSnapshot(
                burn: burn,
                live: liveEstL100,
                baseline: personalBaselineL100,
                lastFill: lastFill,
                prediction: prediction,
                now: now
            )
        }

        let burnFactor = personalBaselineL100 > 0
            ? min(max(personalBaselineL100 / max(liveEstL100, 0.1), 0.6), 1.25)
            : 1.0
        let adjustedKmLeft = max(0, baseKmLeft * burnFactor)

        let tankFill = prediction.tankPercentRemaining.map {
            min(1, max(0, ($0 * burnFactor) / 100))
        }

        let paceKmh: Double = {
            if sessionAvgSpeedKmh >= 12 { return sessionAvgSpeedKmh }
            let kmSince = max(0, odometer - lastFill.odometerReading)
            let daysSince = max(now.timeIntervalSince(lastFill.timestamp) / 86_400, 0.25)
            return max(kmSince / daysSince / 3.5, 28)
        }()

        let timeSec = adjustedKmLeft > 0 ? (adjustedKmLeft / paceKmh) * 3600 : 0
        let showTime = prediction.confidence >= 0.72 && sessionAvgSpeedKmh >= 12 && timeSec >= 1_800

        return Snapshot(
            burnPosition: burn,
            tankFillLevel: tankFill,
            kmRemaining: adjustedKmLeft,
            timeRemainingSec: showTime ? timeSec : nil,
            confidence: prediction.confidence,
            showsRangeEstimate: true,
            headline: conservativeRangeHeadline(
                kmLeft: adjustedKmLeft,
                timeSec: showTime ? timeSec : nil,
                unit: distanceUnit
            ),
            detail: humanBurnDetail(
                live: liveEstL100,
                baseline: personalBaselineL100,
                lastFill: lastFill,
                thirstyNow: burn > 0.55
            ),
            rangeCardTitle: rangeCardTitle(kmLeft: adjustedKmLeft, unit: distanceUnit),
            filledAgo: filledAgoLabel(from: lastFill.timestamp, now: now)
        )
    }

    // MARK: - Private

    private static func burnPosition(live: Double, baseline: Double, thirst: Double) -> Double {
        let safeBaseline = max(baseline, 4)
        let efficientFloor = safeBaseline * 0.82
        let thirstyCeiling = safeBaseline * 1.38
        let fromLive = (live - efficientFloor) / max(thirstyCeiling - efficientFloor, 0.1)
        let blended = fromLive * 0.62 + thirst * 0.38
        return min(max(blended, 0), 1)
    }

    private static func learningSnapshot(
        burn: Double,
        live: Double,
        baseline: Double,
        lastFill: FuelLog?,
        now: Date
    ) -> Snapshot {
        let headline = humanHeadlineWithoutRange(burn: burn, live: live, baseline: baseline)
        return Snapshot(
            burnPosition: burn,
            tankFillLevel: nil,
            kmRemaining: nil,
            timeRemainingSec: nil,
            confidence: 0.2,
            showsRangeEstimate: false,
            headline: headline,
            detail: lastFill == nil
                ? "Log a fill and I’ll learn your tank."
                : "Need one more full tank to trust the range.",
            rangeCardTitle: headline,
            filledAgo: lastFill.map { filledAgoLabel(from: $0.timestamp, now: now) } ?? "No fills yet"
        )
    }

    private static func cautiousSnapshot(
        burn: Double,
        live: Double,
        baseline: Double,
        lastFill: FuelLog,
        prediction: FuelInsightLogic.FuelPrediction?,
        now: Date
    ) -> Snapshot {
        let softFill = prediction?.tankPercentRemaining.map { min(1, max(0, $0 / 100)) }
        let headline = humanHeadlineWithoutRange(burn: burn, live: live, baseline: baseline)
        return Snapshot(
            burnPosition: burn,
            tankFillLevel: softFill,
            kmRemaining: nil,
            timeRemainingSec: nil,
            confidence: prediction?.confidence ?? 0.35,
            showsRangeEstimate: false,
            headline: headline,
            detail: humanBurnDetail(
                live: live,
                baseline: baseline,
                lastFill: lastFill,
                thirstyNow: burn > 0.55
            ),
            rangeCardTitle: headline,
            filledAgo: filledAgoLabel(from: lastFill.timestamp, now: now)
        )
    }

    private static func humanHeadlineWithoutRange(burn: Double, live: Double, baseline: Double) -> String {
        if burn <= 0.35 { return "Easy on fuel right now" }
        if burn >= 0.65 { return "Burning more than usual" }
        if baseline > 0, live <= baseline * 0.95 { return "Sipping fuel nicely" }
        return "Steady burn — watching your tank"
    }

    private static func rangeCardTitle(kmLeft: Double, unit: String) -> String {
        let low = kmLeft * 0.9
        let high = kmLeft * 1.06
        let band = "\(DistanceFormat.formatDistance(low, unit: unit))–\(DistanceFormat.formatDistance(high, unit: unit))"
        return "\(band) left"
    }

    private static func filledAgoLabel(from date: Date, now: Date) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        if days == 0 { return "Filled today" }
        if days == 1 { return "Filled yesterday" }
        return "Filled \(days) days ago"
    }

    private static func conservativeRangeHeadline(kmLeft: Double, timeSec: Double?, unit: String) -> String {
        let band = rangeCardTitle(kmLeft: kmLeft, unit: unit)
            .replacingOccurrences(of: " left", with: "")
        guard let timeSec, timeSec >= 1_800 else {
            return "About \(band) left on this tank"
        }
        let hours = Int(timeSec) / 3600
        let minutes = (Int(timeSec) % 3600) / 60
        if hours > 0 {
            return "About \(band) left · ~\(hours)h \(minutes)m driving"
        }
        return "About \(band) left · ~\(minutes)m driving"
    }

    private static func humanBurnDetail(
        live: Double,
        baseline: Double,
        lastFill: FuelLog,
        thirstyNow: Bool
    ) -> String {
        let fillAge = lastFill.timestamp.formatted(date: .abbreviated, time: .omitted)
        guard baseline > 0 else {
            return "Live \(String(format: "%.1f", live)) L/100 · filled \(fillAge)"
        }
        let deltaPct = Int((((live - baseline) / baseline) * 100).rounded())
        if thirstyNow && deltaPct >= 10 {
            return "This drive is running hotter — filled \(fillAge)"
        }
        if deltaPct <= -8 {
            return "You’re beating your usual · filled \(fillAge)"
        }
        if deltaPct >= 8 {
            return "A touch thirstier than norm · filled \(fillAge)"
        }
        return "On your usual rhythm · filled \(fillAge)"
    }
}
