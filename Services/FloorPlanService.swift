//
//  FloorPlanService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import CoreLocation
import Combine

struct BuildingLocator: Identifiable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let organizationName: String?
    let isPublic: Bool

    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        address: String? = nil,
        organizationName: String? = nil,
        isPublic: Bool = false
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.address = address
        self.organizationName = organizationName
        self.isPublic = isPublic
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: BuildingLocator, b: BuildingLocator) -> Bool { a.id == b.id }
}

struct FloorSummary: Identifiable, Hashable {
    let id: String
    let floorIndex: Int
    let displayName: String?
}

/// Service for fetching floor plan geometry and building data
class FloorPlanService: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var buildings: [BuildingLocator] = []
    @Published var floors: [FloorSummary] = []
    @Published var suggestions: [SpaceSuggestion] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    func fetchBuildingLocators(campusId: String) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("campuses/\(campusId)/buildings"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "FloorPlanService", code: -1)
            }
            let items = try JSONDecoder().decode([BuildingLocatorItem].self, from: data)
            let locators = items.compactMap { item -> BuildingLocator? in
                guard let lat = item.origin_lat, let lng = item.origin_lng else { return nil }
                return BuildingLocator(
                    id: item.id,
                    name: item.name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    address: item.address
                )
            }
            await MainActor.run { self.buildings = locators }
        } catch {
            await MainActor.run {
                self.error = "Failed to load buildings: \(error.localizedDescription)"
            }
        }
    }

    func fetchVisibleBuildings() async {
        var request = URLRequest(url: baseURL.appendingPathComponent("buildings/visible"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "FloorPlanService", code: -1)
            }
            let items = try JSONDecoder().decode([VisibleBuildingItem].self, from: data)
            let locators = items.map { item in
                BuildingLocator(
                    id: item.id,
                    name: item.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: item.origin_lat,
                        longitude: item.origin_lng
                    ),
                    address: item.address,
                    organizationName: item.organization_name,
                    isPublic: item.is_public
                )
            }
            await MainActor.run { self.buildings = locators }
        } catch {
            await MainActor.run {
                self.error = "Failed to load buildings: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func fetchFloorList(buildingId: String) async -> [FloorSummary] {
        var request = URLRequest(url: baseURL.appendingPathComponent("buildings/\(buildingId)/floors"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "FloorPlanService", code: -1)
            }
            let items = try JSONDecoder().decode([FloorListItem].self, from: data)
            let summaries = items
                .sorted { $0.floor_index < $1.floor_index }
                .map { FloorSummary(id: $0.id, floorIndex: $0.floor_index, displayName: $0.display_name) }
            await MainActor.run { self.floors = summaries }
            return summaries
        } catch {
            await MainActor.run {
                self.error = "Failed to load floors: \(error.localizedDescription)"
                self.floors = []
            }
            return []
        }
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
            let withGlobal = decoded.filter { ($0.polygonGlobal?.count ?? 0) >= 3 }.count
            print("[GEOM] floor \(floorId): \(items.count) spaces from API → \(decoded.count) rooms, \(withGlobal) with polygon_global")

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

    func searchGlobal(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            await MainActor.run { self.suggestions = [] }
            return
        }

        let url = baseURL.appendingPathComponent("search/spaces")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20")]
        guard let final = comps.url else { return }

        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let items = try JSONDecoder().decode([SpaceSearchItem].self, from: data)
            let sugg = items.map { SpaceSuggestion(id: $0.id, name: $0.display_name ?? $0.id, buildingId: $0.building_id, floorId: $0.floor_id, campusId: $0.campus_id, lat: $0.centroid_lat, lon: $0.centroid_lon) }
            await MainActor.run { self.suggestions = sugg }
        } catch {
            await MainActor.run { self.suggestions = [] }
        }
    }

    func nearestSpace(lat: Double, lon: Double) async -> SpaceSuggestion? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("search/nearest-space"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "lat", value: "\(lat)"), URLQueryItem(name: "lon", value: "\(lon)"), URLQueryItem(name: "limit", value: "1")]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let items = try JSONDecoder().decode([SpaceSearchItem].self, from: data)
            if let s = items.first {
                return SpaceSuggestion(id: s.id, name: s.display_name ?? s.id, buildingId: s.building_id, floorId: s.floor_id, campusId: s.campus_id, lat: s.centroid_lat, lon: s.centroid_lon)
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Backend Response Models

private struct BuildingLocatorItem: Decodable {
    let id: String
    let name: String
    let address: String?
    let origin_lat: Double?
    let origin_lng: Double?
}

private struct FloorListItem: Decodable {
    let id: String
    let floor_index: Int
    let display_name: String?
}

private struct VisibleBuildingItem: Decodable {
    let id: String
    let name: String
    let address: String?
    let organization_id: String?
    let organization_name: String?
    let is_public: Bool
    let origin_lat: Double
    let origin_lng: Double
}

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

// Lightweight search item returned by the backend search endpoints
private struct SpaceSearchItem: Decodable {
    let id: String
    let display_name: String?
    let building_id: String?
    let floor_id: String?
    let campus_id: String?
    let centroid_lat: Double?
    let centroid_lon: Double?
}

struct SpaceSuggestion: Identifiable, Hashable {
    let id: String
    let name: String
    let buildingId: String?
    let floorId: String?
    let campusId: String?
    let lat: Double?
    let lon: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let la = lat, let lo = lon else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
}
