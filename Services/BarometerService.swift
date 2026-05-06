//
//  BarometerService.swift
//  aau-sw8-ios
//  Created by jimpo on 17/02/26.
// 

import Foundation
import Combine
import CoreMotion

@MainActor
final class BarometerService: ObservableObject {
    @Published private(set) var currentFloorIndex: Int?
    @Published private(set) var relativeAltitudeMeters: Double?
    @Published private(set) var isAvailable: Bool = false

    private let altimeter = CMAltimeter()
    private var floors: [FloorSummary] = []
    private var baselineRelativeAltitude: Double?
    private var baselineFloorElevation: Double?
    private let hysteresisMeters: Double = 1.5

    private var motionUsageDescriptionConfigured: Bool {
        let key = "NSMotionUsageDescription"
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return value?.isEmpty == false
    }

    func start(floors: [FloorSummary], baselineFloorIndex: Int = 0) {
        guard motionUsageDescriptionConfigured else {
            print("[BAROMETER] NSMotionUsageDescription missing — skipping start to avoid SIGTERM")
            return
        }
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("[BAROMETER] device has no barometer — disabling")
            isAvailable = false
            return
        }
        altimeter.stopRelativeAltitudeUpdates()

        self.floors = floors
        let anchor = floors.first(where: { $0.floorIndex == baselineFloorIndex })
                  ?? floors.first
        self.baselineFloorElevation = anchor?.elevationMeters ?? 0
        self.baselineRelativeAltitude = nil   // captured on the first sample
        self.currentFloorIndex = anchor?.floorIndex
        self.isAvailable = true

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            if let error {
                print("[BAROMETER] update error: \(error.localizedDescription)")
                return
            }
            guard let data else { return }
            let r = data.relativeAltitude.doubleValue
            self.relativeAltitudeMeters = r
            if self.baselineRelativeAltitude == nil {
                self.baselineRelativeAltitude = r
                return
            }
            self.recomputeFloorIndex(currentRelativeAltitude: r)
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        baselineRelativeAltitude = nil
        baselineFloorElevation = nil
        currentFloorIndex = nil
        relativeAltitudeMeters = nil
    }

    func recalibrate(toFloorIndex newIndex: Int) {
        guard isAvailable, let r = relativeAltitudeMeters else { return }
        guard let anchor = floors.first(where: { $0.floorIndex == newIndex }) else { return }
        baselineRelativeAltitude = r
        baselineFloorElevation = anchor.elevationMeters ?? 0
        currentFloorIndex = newIndex
        print("[BAROMETER] recalibrated to floor \(newIndex) at relative altitude \(String(format: "%.2f", r))m")
    }

    private func recomputeFloorIndex(currentRelativeAltitude r: Double) {
        guard let r0 = baselineRelativeAltitude,
              let e0 = baselineFloorElevation else { return }
        let userElevation = e0 + (r - r0)

        // Pick the floor whose elevation is closest to the user's current
        // estimated elevation.
        let scored = floors.compactMap { f -> (FloorSummary, Double)? in
            guard let e = f.elevationMeters else { return nil }
            return (f, abs(e - userElevation))
        }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return }

        if let cur = currentFloorIndex,
           let curFloor = floors.first(where: { $0.floorIndex == cur }),
           let curElevation = curFloor.elevationMeters {
            let curDelta = abs(curElevation - userElevation)
            if curDelta - best.1 < hysteresisMeters { return }
        }

        if best.0.floorIndex != currentFloorIndex {
            print("[BAROMETER] floor change: \(currentFloorIndex.map(String.init) ?? "nil") → \(best.0.floorIndex) (user at ~\(String(format: "%.1f", userElevation))m)")
            currentFloorIndex = best.0.floorIndex
        }
    }
}
