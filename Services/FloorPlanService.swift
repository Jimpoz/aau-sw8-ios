//
//  FloorPlanService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import CoreLocation
import Combine

/// Service for fetching floor plan geometry and building data
class FloorPlanService: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    /// Fetch floor display data (spaces with polygon_global) for a specific floor
    func fetchFloorGeometry(floorId: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("floors/\(floorId)/display"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "Invalid response", code: -1)
            }

            let items = try JSONDecoder().decode([SpaceDisplayItem].self, from: data)
            let decoded = items.compactMap { $0.toRoom() }

            DispatchQueue.main.async {
                self.rooms = decoded
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to load floor geometry: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    /// Fetch floor metadata
    func fetchFloor(floorId: String) async -> Floor? {
        let url = baseURL.appendingPathComponent("floors/\(floorId)")

        var floorRequest = URLRequest(url: url)
        floorRequest.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        floorRequest.attachBearer()

        do {
            let (data, response) = try await session.data(for: floorRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return try JSONDecoder().decode(Floor.self, from: data)
        } catch {
            print("Error fetching floor: \(error)")
            return nil
        }
    }
}

// MARK: - Backend Response Models

/// Matches the flat space object returned by GET /floors/{floor_id}/display
private struct SpaceDisplayItem: Decodable {
    let id: String
    let display_name: String?
    let space_type: String?
    let centroid_x: Double?
    let centroid_y: Double?
    let centroid_lat: Double?
    let centroid_lon: Double?
    let polygon: [[Double]]?
    let polygon_global: [[Double]]?   // [[lat, lng], ...]
    let is_accessible: Bool?
    let is_navigable: Bool?
    let capacity: Int?

    func toRoom() -> Room? {
        // Convert polygon_global [[lat,lng], ...] → [CLLocationCoordinate2D]
        var polygonGlobal: [CLLocationCoordinate2D]? = nil
        if let raw = polygon_global, raw.count >= 3 {
            let coords = raw.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
            if coords.count >= 3 { polygonGlobal = coords }
        }

        var centroidGlobal: CLLocationCoordinate2D? = nil
        if let lat = centroid_lat, let lon = centroid_lon {
            centroidGlobal = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        let centroidPoint: CGPoint? = (centroid_x != nil && centroid_y != nil)
            ? CGPoint(x: centroid_x!, y: centroid_y!) : nil
        let polygonPoints = polygon?.map { CGPoint(x: $0[0], y: $0[1]) }

        return Room(
            id: id,
            name: display_name ?? id,
            type: mapSpaceType(space_type ?? ""),
            centroid: centroidPoint,
            centroidGlobal: centroidGlobal,
            polygon: polygonPoints,
            polygonGlobal: polygonGlobal,
            metadata: nil
        )
    }

    private func mapSpaceType(_ t: String) -> RoomType {
        switch t {
        case "ROOM_CLASSROOM", "ROOM_LECTURE_HALL", "ROOM_LAB": return .classroom
        case "ROOM_OFFICE", "ROOM_STAFF": return .office
        case "ROOM_MEETING", "ROOM_SEMINAR": return .meetingRoom
        case "RESTROOM", "RESTROOM_ACCESSIBLE", "RESTROOM_MALE", "RESTROOM_FEMALE": return .restroom
        case "CORRIDOR", "CORRIDOR_SEGMENT": return .hallway
        case "ENTRANCE", "ENTRANCE_SECONDARY": return .entrance
        case "EXIT_EMERGENCY": return .exit
        case "CAFETERIA", "KITCHEN": return .restaurant
        case "SHOP": return .shop
        default: return .other
        }
    }
}
