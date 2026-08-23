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
        var statusLabel: String
    }

    struct State: Equatable {
        var score: Double = 78
        var harshCount: Int = 0
        var smoothSeconds: Double = 0
        var fastCruiseSeconds: Double = 0
        var lastEvent: String = ""
        var lastEventAt: Date?
        var samples: [SpeedSample] = []
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
                now: at
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

        return snapshot(
            score: state.score,
            baselineL100: baselineL100,
            isPaused: false,
            lastEvent: state.lastEvent,
            lastEventAt: state.lastEventAt,
            now: at
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
            forcedLabel: saved ? "Saved" : nil
        )
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
        forcedLabel: String? = nil
    ) -> Snapshot {
        let safeBaseline = max(baselineL100.isFinite ? baselineL100 : 0, 0)
        let clamped = Int(score.rounded().clamped(to: 0...100))
        let factor = 1.0 + ((70.0 - Double(clamped)) / 100.0) * 0.55
        let est = max(3.5, max(safeBaseline, 0.1) * factor)

        let scoreThirst = 1.0 - (Double(clamped) / 100.0)
        let burnRatio = est / max(safeBaseline, 4.5)
        let burnThirst = min(1.0, max(0, (burnRatio - 0.9) / 0.38))
        let rawThirst = max(scoreThirst, burnThirst)
        let thirst = ((rawThirst * 20).rounded() / 20).clamped(to: 0...1)

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
            statusLabel: label
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
