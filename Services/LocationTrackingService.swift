//
//  LocationTrackingService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import CoreLocation
import Combine

/// Service for tracking user's location within the building
class LocationTrackingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentFloor: Int?
    @Published var isTrackingEnabled = false
    @Published var accuracy: CLLocationAccuracy?
    @Published var error: String?
    
    private let locationManager = CLLocationManager()
    private let beaconManager = CLBeaconRegionMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        setupLocationMonitoring()
    }
    
    /// Request permission and start tracking user location
    func startTracking() {
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
            isTrackingEnabled = true
        } else {
            error = "Location services are disabled"
        }
    }
    
    /// Stop tracking user location
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTrackingEnabled = false
    }
    
    /// Detect current floor using beacon signals (requires BLE beacons on each floor)
    func detectFloor(from beacons: [CLBeacon]) {
        // Group beacons by proximity UUID (one per floor)
        let floorMap: [String: Int] = [
            "F1-UUID": 1,
            "F2-UUID": 2,
            "F3-UUID": 3,
            "G-UUID": 0,
            "B1-UUID": -1,
        ]
        
        // Find the closest beacon
        if let closest = beacons.min(by: { $0.accuracy < $1.accuracy }) {
            let uuidString = closest.proximityUUID.uuidString
            if let floor = floorMap[uuidString] {
                DispatchQueue.main.async {
                    self.currentFloor = floor
                }
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location.coordinate
            self.accuracy = location.horizontalAccuracy
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.error = "Location error: \(error.localizedDescription)"
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            error = "Location permission denied"
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Private
    
    private func setupLocationMonitoring() {
        // In a real app, you'd set up beacon region monitoring for each floor
        // This is a placeholder for demonstrating the architecture
    }
}

/// Placeholder for beacon region monitoring
class CLBeaconRegionMonitor {
    // Implementation would go here
}
