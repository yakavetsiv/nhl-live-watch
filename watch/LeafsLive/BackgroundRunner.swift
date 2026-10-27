import HealthKit
import WatchKit

/// Keeps the app running with the screen off for the length of a game.
///
/// watchOS suspends a normal app seconds after the wrist goes down. A workout session is the only
/// way to keep polling and tapping the wrist for a full game, so Live mode starts one. No workout
/// builder is attached, so nothing is recorded to Health and no workout is saved. If HealthKit is
/// unavailable or declined, it falls back to an extended runtime session, which watchOS caps at
/// about an hour.
@MainActor
final class BackgroundRunner: NSObject, ObservableObject {
    enum Mode: String { case off = "Off", workout = "Workout session", extended = "Extended runtime (≈1 h)" }

    @Published private(set) var mode: Mode = .off
    @Published private(set) var lastError: String?

    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var extended: WKExtendedRuntimeSession?

    var isRunning: Bool { mode != .off }

    func start() async {
        guard mode == .off else { return }
        lastError = nil
        if await startWorkout() { return }
        startExtended()
    }

    func stop() {
        workout?.end()
        workout = nil
        extended?.invalidate()
        extended = nil
        mode = .off
    }

    private func startWorkout() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            session.delegate = self
            session.startActivity(with: Date())
            workout = session
            mode = .workout
            return true
        } catch {
            lastError = "Workout: \(error.localizedDescription)"
            return false
        }
    }

    private func startExtended() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extended = session
        mode = .extended
    }
}

extension BackgroundRunner: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in
            if self.workout === workoutSession { self.workout = nil; self.mode = .off }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Workout: \(error.localizedDescription)"
            if self.workout === workoutSession { self.workout = nil; self.mode = .off }
        }
    }
}

extension BackgroundRunner: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            Notifier.post(title: "Hockey Live paused", body: "Background time ran out. Open the app to keep tracking.")
        }
    }

    nonisolated func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in
            if let error { self.lastError = "Runtime: \(error.localizedDescription)" }
            if self.extended === session { self.extended = nil; self.mode = .off }
        }
    }
}
