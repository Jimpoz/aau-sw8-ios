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

    enum LocalizationMode: String {
        case gps
        case gpsWifi
        case cameraLiDAR
        case cameraNoLiDAR
    }

    @Published var localizationMode: LocalizationMode = .gps

    var localizationModeLabel: String {
        switch localizationMode {
        case .gps: return "GPS" // still not available due to only it being an online service for now
        case .gpsWifi: return "GPS + Wi‑Fi"
        case .cameraLiDAR: return "GPS + Wi‑Fi + Camera (No LiDAR)" // to implement
        case .cameraNoLiDAR: return "GPS + Wi‑Fi + Camera (LiDAR)" // to implement
        }
    }

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "wifi.path.monitor")
    private var didUpgradeToWifiAccuracy = false
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1 // meters
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
        guard let loc = locations.last else { return }
        lastLocation = loc
    }

    func applyPreciseLocationFromCamera(_ location: CLLocation) {
        // Treat this as the best available location source.
        lastLocation = location
        localizationMode = .cameraLiDAR
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

            // This is a best-effort connectivity signal. CoreLocation still performs its own sensor fusion;
            // we use this flag to "upgrade" our CLLocation accuracy profile once Wi‑Fi is actually being used.
            let isOnWifi = path.status == .satisfied && path.usesInterfaceType(.wifi)

            // GPS-first: upgrade once, and never downgrade automatically.
            guard isOnWifi, !self.didUpgradeToWifiAccuracy else { return }
            self.didUpgradeToWifiAccuracy = true

            DispatchQueue.main.async {
                // Preserve the explicit camera-based mode if the user has switched to it.
                if self.localizationMode != .cameraLiDAR {
                    self.localizationMode = .gpsWifi
                }
                self.upgradeToGpsWifiAccuracy()
            }
        }

        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func upgradeToGpsWifiAccuracy() {
        // Higher-effort accuracy profile for navigation improves the odds that Wi‑Fi contributes.
        // (CoreLocation manages the actual fusion; we just request a better accuracy mode.)
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Restart to ensure the new accuracy profile is applied promptly.
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()
        isUpdating = true
    }

    deinit {
        pathMonitor.cancel()
    }
}
