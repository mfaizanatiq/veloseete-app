import Foundation

/// On-device drive quality from GPS speed deltas — no extra hardware.
enum DriveMoodLogic {
    struct SpeedSample: Equatable {
        var at: Date
        var speedKmh: Double
    }

    struct Snapshot: Equatable {
        var driveScore: Int
        var estL100: Double
        var moodRaw: String
        var lastEvent: String
        var thirst: Double
        /// Session efficiency cushion — starts full, drains with throttle, slowly recovers when calm.
        var efficiencyReserve: Double
        var statusLabel: String
        /// Recent GPS speeds for the live HUD waveform (last ~45s).
        var speedSamplesKmh: [Double]
    }

    struct State: Equatable {
        var score: Double = 78
        var harshCount: Int = 0
        var smoothSeconds: Double = 0
        var fastCruiseSeconds: Double = 0
        var lastEvent: String = ""
        var lastEventAt: Date?
        var samples: [SpeedSample] = []
        var efficiencyReserve: Double = 1
        var lastReserveUpdate: Date?
    }

    /// Harsh accel / brake thresholds (km/h per second).
    private static let harshAccelKmhPerSec = 11.0
    private static let heavyThrottleKmhPerSec = 6.5
    private static let harshBrakeKmhPerSec = -14.0
    private static let fastCruiseKmh = 95.0
    private static let sampleWindow: TimeInterval = 45
    private static let eventCooldown: TimeInterval = 4

    static func ingest(
        state: inout State,
        speedKmh: Double,
        at: Date = Date(),
        isPaused: Bool,
        baselineL100: Double
    ) -> Snapshot {
        if isPaused {
            return snapshot(
                score: state.score,
                baselineL100: baselineL100,
                isPaused: true,
                lastEvent: state.lastEvent,
                lastEventAt: state.lastEventAt,
                now: at,
                efficiencyReserve: state.efficiencyReserve,
                speedSamplesKmh: state.samples.map(\.speedKmh)
            )
        }

        let clampedSpeed = max(0, speedKmh.isFinite ? speedKmh : 0)
        state.samples.append(SpeedSample(at: at, speedKmh: clampedSpeed))
        state.samples.removeAll { at.timeIntervalSince($0.at) > sampleWindow }
        if state.samples.count > 40 {
            state.samples.removeFirst(state.samples.count - 40)
        }

        if let previous = state.samples.dropLast().last {
            let dt = at.timeIntervalSince(previous.at)
            if dt >= 0.8, dt <= 6 {
                let delta = (clampedSpeed - previous.speedKmh) / dt
                let inTraffic = clampedSpeed < 8 && previous.speedKmh < 8

                if !inTraffic, delta >= harshAccelKmhPerSec {
                    registerHarsh(&state, event: TrackyVoice.Calm.hardAccel, at: at, penalty: 7)
                } else if !inTraffic, delta >= heavyThrottleKmhPerSec {
                    registerHarsh(&state, event: TrackyVoice.Calm.heavyThrottle, at: at, penalty: 4)
                } else if !inTraffic, delta <= harshBrakeKmhPerSec {
                    registerHarsh(&state, event: TrackyVoice.Calm.hardBrake, at: at, penalty: 5)
                } else if abs(delta) < 3.5 || inTraffic {
                    state.smoothSeconds += dt
                    state.score = min(100, state.score + dt * 0.045)
                    if state.smoothSeconds >= 45, state.lastEvent.isEmpty == false {
                        if at.timeIntervalSince(state.lastEventAt ?? .distantPast) > 20 {
                            state.lastEvent = "Smooth \(Int(state.smoothSeconds / 60))m"
                            if state.smoothSeconds < 60 {
                                state.lastEvent = "Smooth streak"
                            }
                        }
                    }
                }
            }

            // Sustained fast cruise burns more fuel even without harsh spikes.
            if clampedSpeed >= fastCruiseKmh {
                state.fastCruiseSeconds += min(dt, 3)
                state.score = max(35, state.score - dt * 0.14)
                if state.fastCruiseSeconds >= 18 {
                    registerHarsh(
                        &state,
                        event: TrackyVoice.Calm.fastCruise,
                        at: at,
                        penalty: 2,
                        cooldown: 12
                    )
                }
            } else {
                state.fastCruiseSeconds = max(0, state.fastCruiseSeconds - dt * 0.6)
            }
        }

        if clampedSpeed > 120 {
            state.score = max(35, state.score - 0.08)
        }

        let thirst = thirstValue(score: state.score, baselineL100: baselineL100)
        updateEfficiencyReserve(
            state: &state,
            thirst: thirst,
            speedKmh: clampedSpeed,
            at: at,
            isPaused: false
        )

        return snapshot(
            score: state.score,
            baselineL100: baselineL100,
            isPaused: false,
            lastEvent: state.lastEvent,
            lastEventAt: state.lastEventAt,
            now: at,
            efficiencyReserve: displayedEfficiency(
                reserve: state.efficiencyReserve,
                speedKmh: clampedSpeed,
                thirst: thirst
            ),
            speedSamplesKmh: state.samples.map(\.speedKmh)
        )
    }

    static func finalSnapshot(
        state: State,
        baselineL100: Double,
        saved: Bool
    ) -> Snapshot {
        snapshot(
            score: state.score,
            baselineL100: baselineL100,
            isPaused: false,
            lastEvent: saved ? "Nice drive" : state.lastEvent,
            lastEventAt: state.lastEventAt,
            now: Date(),
            forcedMood: saved ? "saved" : nil,
            forcedLabel: saved ? "Saved" : nil,
            efficiencyReserve: state.efficiencyReserve,
            speedSamplesKmh: state.samples.map(\.speedKmh)
        )
    }

    private static func thirstValue(score: Double, baselineL100: Double) -> Double {
        let safeBaseline = max(baselineL100.isFinite ? baselineL100 : 0, 0)
        let clamped = Int(score.rounded().clamped(to: 0...100))
        let factor = 1.0 + ((70.0 - Double(clamped)) / 100.0) * 0.55
        let est = max(3.5, max(safeBaseline, 0.1) * factor)

        let scoreThirst = 1.0 - (Double(clamped) / 100.0)
        let burnRatio = est / max(safeBaseline, 4.5)
        let burnThirst = min(1.0, max(0, (burnRatio - 0.9) / 0.38))
        let rawThirst = max(scoreThirst, burnThirst)
        return ((rawThirst * 20).rounded() / 20).clamped(to: 0...1)
    }

    private static func updateEfficiencyReserve(
        state: inout State,
        thirst: Double,
        speedKmh: Double,
        at: Date,
        isPaused: Bool
    ) {
        guard !isPaused else { return }

        let dt: Double
        if let last = state.lastReserveUpdate {
            dt = min(max(at.timeIntervalSince(last), 0), 4)
        } else {
            state.efficiencyReserve = 1
            state.lastReserveUpdate = at
            return
        }
        state.lastReserveUpdate = at
        guard dt > 0 else { return }

        // Faster cruise pulls the cushion down even without harsh spikes.
        let speedPressure = speedPressure(speedKmh)
        let drain = (thirst * 0.034 + speedPressure * 0.03) * dt
        let recover = (1 - thirst) * (1 - speedPressure * 0.9) * dt * 0.009
        state.efficiencyReserve = min(1, max(0, state.efficiencyReserve - drain + recover))
    }

    /// Instant HUD response: higher speed / thirst pulls the arc tip toward the pump.
    private static func displayedEfficiency(
        reserve: Double,
        speedKmh: Double,
        thirst: Double
    ) -> Double {
        let speed = speedPressure(speedKmh)
        let livePull = speed * (0.38 + thirst * 0.22)
        return min(1, max(0, reserve * (1 - livePull)))
    }

    /// 0 around city cruise, 1 at hard highway pace.
    private static func speedPressure(_ speedKmh: Double) -> Double {
        min(1, max(0, (speedKmh - 45) / 70))
    }

    private static func registerHarsh(
        _ state: inout State,
        event: String,
        at: Date,
        penalty: Double,
        cooldown: TimeInterval = eventCooldown
    ) {
        if let last = state.lastEventAt, at.timeIntervalSince(last) < cooldown {
            return
        }
        state.harshCount += 1
        state.smoothSeconds = 0
        state.score = max(18, state.score - penalty)
        // Throttle events punch the efficiency cushion immediately.
        state.efficiencyReserve = max(0, state.efficiencyReserve - penalty * 0.022)
        state.lastEvent = event
        state.lastEventAt = at
    }

    private static func snapshot(
        score: Double,
        baselineL100: Double,
        isPaused: Bool,
        lastEvent: String,
        lastEventAt: Date?,
        now: Date,
        forcedMood: String? = nil,
        forcedLabel: String? = nil,
        efficiencyReserve: Double = 1,
        speedSamplesKmh: [Double] = []
    ) -> Snapshot {
        let safeBaseline = max(baselineL100.isFinite ? baselineL100 : 0, 0)
        let clamped = Int(score.rounded().clamped(to: 0...100))
        let factor = 1.0 + ((70.0 - Double(clamped)) / 100.0) * 0.55
        let est = max(3.5, max(safeBaseline, 0.1) * factor)
        let thirst = thirstValue(score: score, baselineL100: baselineL100)

        let mood: String
        let label: String
        if let forcedMood {
            mood = forcedMood
            label = forcedLabel ?? "Recording"
        } else if isPaused {
            mood = "paused"
            label = "Paused"
        } else if clamped >= 72 {
            mood = "smooth"
            label = "Smooth"
        } else if clamped >= 48 {
            mood = "watch"
            label = "Steady"
        } else {
            mood = "heavy"
            label = "Heavy"
        }

        var event = lastEvent
        if let lastEventAt, now.timeIntervalSince(lastEventAt) > 25, mood != "saved" {
            if event.hasPrefix("Harsh") || event.hasPrefix("Hard") || event.hasPrefix("Heavy") {
                event = ""
            }
        }

        return Snapshot(
            driveScore: clamped,
            estL100: (est * 10).rounded() / 10,
            moodRaw: mood,
            lastEvent: event,
            thirst: thirst,
            efficiencyReserve: min(1, max(0, efficiencyReserve)),
            statusLabel: label,
            speedSamplesKmh: speedSamplesKmh
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Picks a sensible L/100 baseline for live trip efficiency estimates.
enum DriveMoodBaseline {
    static func resolve(
        vehicle: Vehicle,
        logs: [FuelLog],
        manufacturerStandard: Double?,
        fallback: Double = 8.0
    ) -> Double {
        let metrics = MetricsCalculator.compute(vehicle: vehicle, logs: logs)
        if let avg = metrics.avgEfficiency ?? metrics.current, avg > 0 {
            return avg
        }
        if let manufacturerStandard, manufacturerStandard > 0 {
            return manufacturerStandard
        }
        return fallback
    }
}
