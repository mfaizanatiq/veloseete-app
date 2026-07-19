import Combine
import CoreLocation
import CoreMotion
import Foundation
import UIKit
import UserNotifications

enum TripLocationPermissionStatus: Equatable {
    case notDetermined
    case whenInUse
    case always
    case denied
    case restricted

    var isUsable: Bool {
        self == .whenInUse || self == .always
    }

    var needsSettings: Bool {
        self == .denied || self == .restricted
    }
}

enum TripMotionPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable

    var isReady: Bool {
        self == .authorized || self == .unavailable
    }

    var needsSettings: Bool {
        self == .denied || self == .restricted
    }
}

enum TripNotificationPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral

    var isReady: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        }
    }

    var needsSettings: Bool {
        self == .denied
    }
}

@MainActor
final class TripPermissionsManager: NSObject, ObservableObject {
    @Published private(set) var locationStatus: TripLocationPermissionStatus = .notDetermined
    @Published private(set) var motionStatus: TripMotionPermissionStatus = .notDetermined
    @Published private(set) var notificationStatus: TripNotificationPermissionStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .automotiveNavigation
        locationManager.allowsBackgroundLocationUpdates = false
        refreshStatuses()
    }

    func refreshStatuses() {
        refreshLocationStatus(from: locationManager.authorizationStatus)
        refreshMotionStatus()
        refreshNotificationStatus()
    }

    func requestWhenInUseLocation() {
        guard locationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysLocation() {
        guard locationStatus == .whenInUse else { return }
        locationManager.requestAlwaysAuthorization()
    }

    func requestMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionStatus = .unavailable
            return
        }

        guard motionStatus == .notDetermined else { return }
        motionManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { [weak self] _, _ in
            self?.refreshMotionStatus()
        }
    }

    func requestNotifications() {
        guard notificationStatus == .notDetermined else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshNotificationStatus()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshLocationStatus(from status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationStatus = .notDetermined
        case .authorizedWhenInUse:
            locationStatus = .whenInUse
        case .authorizedAlways:
            locationStatus = .always
        case .denied:
            locationStatus = .denied
        case .restricted:
            locationStatus = .restricted
        @unknown default:
            locationStatus = .notDetermined
        }
    }

    private func refreshMotionStatus() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionStatus = .unavailable
            return
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .notDetermined:
            motionStatus = .notDetermined
        case .authorized:
            motionStatus = .authorized
        case .denied:
            motionStatus = .denied
        case .restricted:
            motionStatus = .restricted
        @unknown default:
            motionStatus = .notDetermined
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .notDetermined:
                    self?.notificationStatus = .notDetermined
                case .denied:
                    self?.notificationStatus = .denied
                case .authorized:
                    self?.notificationStatus = .authorized
                case .provisional:
                    self?.notificationStatus = .provisional
                case .ephemeral:
                    self?.notificationStatus = .ephemeral
                @unknown default:
                    self?.notificationStatus = .notDetermined
                }
            }
        }
    }
}

extension TripPermissionsManager: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationStatus(from: manager.authorizationStatus)
    }
}
