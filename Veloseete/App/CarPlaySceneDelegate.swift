import CarPlay
import Combine
import UIKit

enum CarPlayRefuelHandoff {
    static let draftCreated = CarPlayWidgetStateStore.refuelDraftCreated

    @discardableResult
    static func create(
        vehicleID: String,
        vehicleName: String,
        estimatedOdometer: Double
    ) -> CarPlayRefuelDraft {
        CarPlayWidgetStateStore.createRefuelDraft(
            vehicleID: vehicleID,
            vehicleName: vehicleName,
            estimatedOdometer: estimatedOdometer
        ) ?? CarPlayRefuelDraft(
            id: UUID(),
            vehicleID: vehicleID,
            vehicleName: vehicleName,
            createdAt: Date(),
            estimatedOdometer: estimatedOdometer
        )
    }

    static func consumePendingDraft() -> CarPlayRefuelDraft? {
        CarPlayWidgetStateStore.consumePendingRefuelDraft()
    }
}

/// The focused, glanceable version of Veloseete shown on the CarPlay display.
///
/// CarPlay renders these templates, so the app never depends on a particular
/// vehicle screen size or input method. Periodic metric updates intentionally
/// run every 10 seconds to stay within the driving-task app refresh limit.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var rootTemplate: CPListTemplate?
    private var refreshTimer: Timer?
    private var authCancellable: AnyCancellable?
    private var dataLoadTask: Task<Void, Never>?
    private var loadingUserID: String?
    private var isSavingTrip = false

    private lazy var auth = AuthService.shared
    private let store = DataStore.shared
    private let recorder = TripRecordingService.shared

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        // CarPlay can launch the app without first opening its iPhone scene.
        FirebaseBootstrap.configure()

        self.interfaceController = interfaceController

        let template = CPListTemplate(
            title: "Veloseete",
            sections: [messageSection(title: "Loading your drive data…")]
        )
        rootTemplate = template
        interfaceController.setRootTemplate(template, animated: false) { success, error in
            if !success, let error {
                print("[CarPlay] Could not set root template: \(error.localizedDescription)")
            }
        }

        observeAuthentication()
        startRefreshTimer()
        refreshTemplate()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        authCancellable = nil
        dataLoadTask?.cancel()
        dataLoadTask = nil
        loadingUserID = nil
        rootTemplate = nil
        self.interfaceController = nil
    }

    // MARK: - Lifecycle and data

    private func observeAuthentication() {
        authCancellable = Publishers.CombineLatest(auth.$user, auth.$isCheckingAuth)
            .sink { [weak self] user, isCheckingAuth in
                Task { @MainActor in
                    self?.authenticationDidChange(
                        userID: user?.uid,
                        isCheckingAuth: isCheckingAuth
                    )
                }
            }
    }

    private func authenticationDidChange(userID: String?, isCheckingAuth: Bool) {
        guard !isCheckingAuth else {
            refreshTemplate()
            return
        }

        guard let userID else {
            dataLoadTask?.cancel()
            dataLoadTask = nil
            loadingUserID = nil
            refreshTemplate()
            return
        }

        if store.isLoaded, store.userDocument?.userId == userID {
            configureRecorderIfPossible()
            refreshTemplate()
            return
        }

        guard loadingUserID != userID else { return }
        loadingUserID = userID
        dataLoadTask?.cancel()
        dataLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await store.loadAll(userId: userID)
            guard !Task.isCancelled else { return }
            loadingUserID = nil
            configureRecorderIfPossible()
            recorder.resumeBackgroundWatchingIfNeeded()
            refreshTemplate()
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTemplate()
            }
        }
    }

    private func configureRecorderIfPossible() {
        guard let vehicle = store.currentVehicle else { return }
        recorder.configure(
            vehicleId: vehicle.id,
            vehicleName: vehicle.nickname,
            currentOdometer: vehicle.currentOdometer,
            driverName: store.userName,
            baselineL100: DriveMoodBaseline.resolve(
                vehicle: vehicle,
                logs: store.fuelLogs,
                manufacturerStandard: store.manufacturerStandard
            )
        )
    }

    // MARK: - Root template

    private func refreshTemplate() {
        guard let rootTemplate else { return }

        if auth.isCheckingAuth {
            rootTemplate.updateSections([messageSection(title: "Checking your account…")])
            return
        }

        guard auth.isAuthenticated else {
            rootTemplate.updateSections([
                messageSection(
                    title: "Veloseete isn’t ready for CarPlay",
                    detail: "Complete sign-in and vehicle setup while parked before using CarPlay."
                )
            ])
            return
        }

        if store.isLoading || loadingUserID != nil, store.vehicles.isEmpty {
            rootTemplate.updateSections([messageSection(title: "Loading your drive data…")])
            return
        }

        guard let vehicle = store.currentVehicle else {
            rootTemplate.updateSections([
                messageSection(
                    title: "No vehicle selected",
                    detail: "Add or select a vehicle in Veloseete while parked."
                )
            ])
            return
        }

        configureRecorderIfPossible()

        var sections = [
            CPListSection(
                items: [driveStatusItem(vehicleName: vehicle.nickname)],
                header: "Current drive",
                sectionIndexTitle: nil
            ),
            CPListSection(
                items: driveActionItems(),
                header: "Actions",
                sectionIndexTitle: nil
            ),
        ]

        if let error = recorder.lastError {
            sections.append(errorSection(message: error))
        }

        let recent = recentDriveItems(vehicleID: vehicle.id)
        if !recent.isEmpty {
            sections.append(
                CPListSection(
                    items: recent,
                    header: "Recent drives",
                    sectionIndexTitle: nil
                )
            )
        }

        rootTemplate.updateSections(sections)
    }

    private func driveStatusItem(vehicleName: String) -> CPListItem {
        let text: String
        let detail: String
        let symbol: String

        switch recorder.phase {
        case .idle:
            text = "Ready to drive"
            detail = vehicleName
            symbol = "car.fill"
        case .watching:
            text = "Automatic tracking ready"
            detail = vehicleName
            symbol = "location.fill"
        case .recording:
            let snapshot = recorder.snapshot
            text = snapshot?.isPaused == true ? "Drive paused" : "Drive in progress"
            if let snapshot {
                let metrics = "\(distance(snapshot.distanceKm)) • \(duration(snapshot.durationSec))"
                detail = snapshot.isPaused
                    ? "\(metrics) • Paused"
                    : "\(metrics) • \(speed(snapshot.currentSpeedKmh))"
            } else {
                detail = vehicleName
            }
            symbol = snapshot?.isPaused == true ? "pause.circle.fill" : "gauge.with.dots.needle.67percent"
        case .confirming:
            text = "Drive ready to save"
            if let pending = recorder.pendingSave {
                detail = "\(distance(pending.distanceKm)) • \(duration(pending.durationSec))"
            } else {
                detail = vehicleName
            }
            symbol = "checkmark.circle.fill"
        }

        let image = routeThumbnail(points: recorder.liveRoute)
            ?? UIImage(systemName: symbol)
        return CPListItem(
            text: text,
            detailText: detail,
            image: image
        )
    }

    private func driveActionItems() -> [CPListItem] {
        switch recorder.phase {
        case .idle, .watching:
            let start = CPListItem(
                text: "Start drive",
                detailText: "Track distance, time, and route",
                image: UIImage(systemName: "play.fill")
            )
            start.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    self.recorder.startManualTrip()
                    let error = self.recorder.lastError
                    if error != nil { self.recorder.clearError() }
                    self.refreshTemplate()
                    if let error { self.presentMessage(error) }
                    completion()
                }
            }

            let refuel = CPListItem(
                text: "Log refuel",
                detailText: "Continue exact entry on iPhone",
                image: UIImage(systemName: "fuelpump.fill")
            )
            refuel.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    self.beginRefuelHandoff()
                    completion()
                }
            }
            return [start, refuel]

        case .recording:
            let isPaused = recorder.snapshot?.isPaused == true
            let pauseResume = CPListItem(
                text: isPaused ? "Resume drive" : "Pause drive",
                detailText: isPaused ? "Continue trip tracking" : "Temporarily stop trip tracking",
                image: UIImage(systemName: isPaused ? "play.fill" : "pause.fill")
            )
            pauseResume.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    if isPaused {
                        self.recorder.resumeTrip()
                    } else {
                        self.recorder.pauseTrip()
                    }
                    self.refreshTemplate()
                    completion()
                }
            }

            let end = CPListItem(
                text: "End drive",
                detailText: "Stop tracking this trip",
                image: UIImage(systemName: "stop.fill")
            )
            end.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    self.presentEndConfirmation(completion: completion)
                }
            }
            return [pauseResume, end]

        case .confirming:
            guard recorder.pendingSave != nil else { return [] }

            if isSavingTrip {
                return [
                    CPListItem(
                        text: "Saving drive…",
                        detailText: "Please wait",
                        image: UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    )
                ]
            }

            let save = CPListItem(
                text: "Save drive",
                detailText: "Add this trip to your history",
                image: UIImage(systemName: "checkmark.circle.fill")
            )
            save.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    await self.savePendingTrip()
                    completion()
                }
            }

            let discard = CPListItem(
                text: "Discard drive",
                detailText: "Delete the unsaved trip",
                image: UIImage(systemName: "trash.fill")
            )
            discard.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else {
                        completion()
                        return
                    }
                    self.presentDiscardConfirmation(completion: completion)
                }
            }
            return [save, discard]
        }
    }

    private func recentDriveItems(vehicleID: String) -> [CPListItem] {
        store.trips
            .filter { $0.vehicleId == vehicleID }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(4)
            .map { trip in
                CPListItem(
                    text: trip.endedAt.formatted(date: .abbreviated, time: .shortened),
                    detailText: "\(distance(trip.distanceKm)) • \(duration(trip.durationSec)) • \(speed(trip.avgSpeedKmh)) avg",
                    image: routeThumbnail(points: trip.route) ?? UIImage(systemName: "road.lanes")
                )
            }
    }

    private func routeThumbnail(points: [TripCoordinate]) -> UIImage? {
        guard points.count >= 2 else { return nil }
        let size = CGSize(width: 52, height: 52)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: 10).fill()

            let road = UIBezierPath()
            road.move(to: CGPoint(x: 0, y: size.height * 0.30))
            road.addLine(to: CGPoint(x: size.width, y: size.height * 0.12))
            road.move(to: CGPoint(x: size.width * 0.16, y: size.height))
            road.addLine(to: CGPoint(x: size.width * 0.72, y: 0))
            road.move(to: CGPoint(x: 0, y: size.height * 0.76))
            road.addLine(to: CGPoint(x: size.width, y: size.height * 0.58))
            UIColor.white.withAlphaComponent(0.12).setStroke()
            road.lineWidth = 1
            road.stroke()

            let latitudes = points.map(\.latitude)
            let longitudes = points.map(\.longitude)
            guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
                  let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
            let latSpan = max(maxLat - minLat, 0.000_001)
            let lonSpan = max(maxLon - minLon, 0.000_001)
            let inset: CGFloat = 7

            func position(_ point: TripCoordinate) -> CGPoint {
                let x = inset + CGFloat((point.longitude - minLon) / lonSpan) * (size.width - inset * 2)
                let y = inset + CGFloat((maxLat - point.latitude) / latSpan) * (size.height - inset * 2)
                return CGPoint(x: x, y: y)
            }

            let route = UIBezierPath()
            route.move(to: position(points[0]))
            for point in points.dropFirst() {
                route.addLine(to: position(point))
            }
            route.lineCapStyle = .round
            route.lineJoinStyle = .round
            UIColor.black.withAlphaComponent(0.45).setStroke()
            route.lineWidth = 5
            route.stroke()
            UIColor(red: 0.84, green: 0.98, blue: 0.31, alpha: 1).setStroke()
            route.lineWidth = 2.5
            route.stroke()

            UIColor(red: 0.84, green: 0.98, blue: 0.31, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: position(points[0]).x - 3, y: position(points[0]).y - 3, width: 6, height: 6)).fill()
            UIColor.orange.setFill()
            let end = position(points[points.count - 1])
            UIBezierPath(ovalIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)).fill()

            context.cgContext.setBlendMode(.normal)
        }
    }

    private func errorSection(message: String) -> CPListSection {
        let error = CPListItem(
            text: "Drive needs attention",
            detailText: message,
            image: UIImage(systemName: "exclamationmark.triangle.fill")
        )
        let dismiss = CPListItem(
            text: "Dismiss",
            detailText: nil,
            image: UIImage(systemName: "xmark.circle")
        )
        dismiss.handler = { [weak self] _, completion in
            Task { @MainActor in
                self?.recorder.clearError()
                self?.refreshTemplate()
                completion()
            }
        }
        return CPListSection(items: [error, dismiss], header: "Attention", sectionIndexTitle: nil)
    }

    private func messageSection(title: String, detail: String? = nil) -> CPListSection {
        let item = CPListItem(
            text: title,
            detailText: detail,
            image: UIImage(systemName: "car.fill")
        )
        return CPListSection(items: [item])
    }

    // MARK: - Actions and alerts

    private func beginRefuelHandoff() {
        guard let vehicle = store.currentVehicle else {
            presentMessage("Select a vehicle in Veloseete on your iPhone first.")
            return
        }

        let estimatedOdometer = store.odometerEstimate(vehicleId: vehicle.id)?.estimatedKm
            ?? vehicle.currentOdometer
        CarPlayRefuelHandoff.create(
            vehicleID: vehicle.id,
            vehicleName: vehicle.nickname,
            estimatedOdometer: estimatedOdometer
        )
        presentMessage(
            "Refuel ready on iPhone. Enter the receipt amount, liters, and dashboard odometer while parked."
        )
    }

    private func presentEndConfirmation(completion: @escaping () -> Void) {
        guard let interfaceController else {
            completion()
            return
        }

        let end = CPAlertAction(title: "End drive", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dismissPresentedTemplate {
                    self.recorder.endTrip()
                    let error = self.recorder.lastError
                    if error != nil { self.recorder.clearError() }
                    self.refreshTemplate()
                    if let error { self.presentMessage(error) }
                }
            }
        }
        let cancel = CPAlertAction(title: "Keep driving", style: .cancel) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPresentedTemplate()
            }
        }
        let alert = CPAlertTemplate(
            titleVariants: ["End this drive?", "End drive?"],
            actions: [end, cancel]
        )
        interfaceController.presentTemplate(alert, animated: true) { success, error in
            if !success, let error {
                print("[CarPlay] Could not present end confirmation: \(error.localizedDescription)")
            }
            completion()
        }
    }

    private func presentDiscardConfirmation(completion: @escaping () -> Void) {
        guard let interfaceController else {
            completion()
            return
        }

        let discard = CPAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.dismissPresentedTemplate {
                    self.recorder.discardPending()
                    self.refreshTemplate()
                }
            }
        }
        let cancel = CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPresentedTemplate()
            }
        }
        let alert = CPAlertTemplate(
            titleVariants: ["Discard this unsaved drive?", "Discard drive?"],
            actions: [discard, cancel]
        )
        interfaceController.presentTemplate(alert, animated: true) { success, error in
            if !success, let error {
                print("[CarPlay] Could not present discard confirmation: \(error.localizedDescription)")
            }
            completion()
        }
    }

    private func savePendingTrip() async {
        guard let pending = recorder.pendingSave, !isSavingTrip else { return }
        isSavingTrip = true
        refreshTemplate()

        do {
            _ = try await store.saveTrip(
                pending,
                odometer: pending.suggestedOdometer,
                applyOdometer: false
            )
            recorder.discardPending()
        } catch {
            presentMessage("The drive couldn’t be saved. Check your connection and try again.")
        }

        isSavingTrip = false
        refreshTemplate()
    }

    private func presentMessage(_ message: String) {
        guard let interfaceController, interfaceController.presentedTemplate == nil else { return }

        let ok = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPresentedTemplate()
            }
        }
        let alert = CPAlertTemplate(
            titleVariants: [message, "Unable to complete that action"],
            actions: [ok]
        )
        interfaceController.presentTemplate(alert, animated: true) { success, error in
            if !success, let error {
                print("[CarPlay] Could not present message: \(error.localizedDescription)")
            }
        }
    }

    private func dismissPresentedTemplate(completion: (() -> Void)? = nil) {
        guard let interfaceController, interfaceController.presentedTemplate != nil else {
            completion?()
            return
        }
        interfaceController.dismissTemplate(animated: true) { _, _ in
            completion?()
        }
    }

    // MARK: - Formatting

    private func distance(_ kilometers: Double) -> String {
        String(format: "%.1f km", kilometers)
    }

    private func speed(_ kilometersPerHour: Double) -> String {
        String(format: "%.0f km/h", kilometersPerHour)
    }

    private func duration(_ seconds: Double) -> String {
        let totalMinutes = max(1, Int(seconds / 60))
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        return "\(totalMinutes / 60) hr \(totalMinutes % 60) min"
    }
}
