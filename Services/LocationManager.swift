//
//  LocationManager.swift
//  aau-sw8-ios
//
//  Created by jimpo on 05/03/26.
//

import Foundation
import CoreLocation
import Combine
import Network

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isUpdating: Bool = false
    @Published var horizontalAccuracyMeters: Double? = nil
    @Published var isOnWifi: Bool = false

    enum LocalizationMode: String {
        case gps
        case gpsWifi
    }

    @Published var localizationMode: LocalizationMode = .gps

    var localizationModeLabel: String {
        switch localizationMode {
        case .gps: return "GPS"
        case .gpsWifi: return "GPS + Wi‑Fi"
        }
    }

    // Max tolerance, otherwise it would just be as precise as the GPS
    private var maxAcceptableAgeSeconds: TimeInterval = 8
    private var maxAcceptableHorizontalAccuracyMeters: Double = 65

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "wifi.path.monitor")

    override init() {
        super.init()
        manager.delegate = self
        // Indoor pedestrian navigation — hints the system to prioritise Wi‑Fi/GPS
        // fusion over dead-reckoning, and keeps the indoor positioning pipeline warm.
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        startLocationIfAuthorized()
        startWifiMonitoring()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationIfAuthorized()
            isUpdating = true
        default:
            manager.stopUpdatingLocation()
            isUpdating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Pick the best sample in the batch
        let now = Date()
        let fresh = locations.filter { now.timeIntervalSince($0.timestamp) <= maxAcceptableAgeSeconds }
        let accurate = fresh.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= maxAcceptableHorizontalAccuracyMeters }
        guard let best = (accurate.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
                          ?? fresh.last
                          ?? locations.last) else { return }

        // Keep only the best sample
        if let previous = lastLocation,
           now.timeIntervalSince(previous.timestamp) < 5,
           best.horizontalAccuracy > previous.horizontalAccuracy * 2.5,
           best.horizontalAccuracy > 30 {
            return
        }

        lastLocation = best
        horizontalAccuracyMeters = best.horizontalAccuracy
    }

    private func startLocationIfAuthorized() {
        authorizationStatus = manager.authorizationStatus
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    private func startWifiMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowOnWifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            DispatchQueue.main.async {
                let changed = self.isOnWifi != nowOnWifi
                self.isOnWifi = nowOnWifi
                if changed { self.applyWifiAwareAccuracyProfile(onWifi: nowOnWifi) }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func applyWifiAwareAccuracyProfile(onWifi: Bool) {
        if onWifi {
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            maxAcceptableHorizontalAccuracyMeters = 25
            maxAcceptableAgeSeconds = 5
            localizationMode = .gpsWifi
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 2
            maxAcceptableHorizontalAccuracyMeters = 65
            maxAcceptableAgeSeconds = 8
            if localizationMode == .gpsWifi { localizationMode = .gps }
        }
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
            isUpdating = true
        }
    }

    deinit {
        pathMonitor.cancel()
    }
}
