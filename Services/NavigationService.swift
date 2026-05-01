//
//  NavigationService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import Combine
import CoreLocation

/// Service for computing routes and navigation
class NavigationService: ObservableObject {
    @Published var currentRoute: NavigationRoute?
    @Published var isLoading = false
    @Published var error: String?
    
    private let baseURL: URL
    private let session: URLSession
    
    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }
    
    /// Compute fastest path between two spaces
    func computeRoute(from startSpaceId: String, to endSpaceId: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        let endpoint = baseURL.appendingPathComponent("navigate")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "from", value: startSpaceId),
            URLQueryItem(name: "to", value: endSpaceId)
        ]
        
        guard let url = components?.url else {
            DispatchQueue.main.async {
                self.error = "Invalid URL"
                self.isLoading = false
            }
            return
        }

        var navRequest = URLRequest(url: url)
        navRequest.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        navRequest.attachBearer()

        do {
            let (data, response) = try await session.data(for: navRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "Invalid response", code: -1)
            }
            
            let decoder = JSONDecoder()
            let serverRoute = try decoder.decode(ServerRoute.self, from: data)

            // Map server steps into local NavigationStep objects with coordinates when available
            let navSteps: [NavigationStep] = serverRoute.steps.enumerated().map { idx, s in
                let instr = s.instruction ?? (idx == 0 ? "Start at \(s.display_name ?? s.space_id)" : "Go to \(s.display_name ?? s.space_id)")
                return NavigationStep(instruction: instr, spaceId: s.space_id, stepNumber: idx + 1, lat: s.centroid_lat, lon: s.centroid_lng)
            }

            DispatchQueue.main.async {
                self.currentRoute = NavigationRoute(
                    from: serverRoute.from_space_id,
                    to: serverRoute.to_space_id,
                    path: serverRoute.steps.map { $0.space_id },
                    totalDistance: serverRoute.total_cost,
                    steps: navSteps
                )
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to compute route: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func computeRoute(fromLatitude lat: Double, longitude lon: Double, to endSpaceId: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }

        var comps = URLComponents(url: baseURL.appendingPathComponent("search/nearest-space"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lon", value: "\(lon)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = comps?.url else {
            DispatchQueue.main.async {
                self.error = "Invalid URL for nearest-space"
                self.isLoading = false
            }
            return
        }

        var req = URLRequest(url: url)
        req.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        req.attachBearer()

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "Invalid response", code: -1)
            }
            let decoder = JSONDecoder()
            let items = try decoder.decode([NearestSpaceItem].self, from: data)
            guard let first = items.first else {
                DispatchQueue.main.async {
                    self.error = "No nearby navigable space found"
                    self.isLoading = false
                }
                return
            }
            await computeRoute(from: first.id, to: endSpaceId)
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to resolve nearest space: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    /// Get route visualization as SVG
    func getRouteVisualization(from startSpaceId: String, to endSpaceId: String) async -> String? {
        let endpoint = baseURL.appendingPathComponent("navigation/map")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start", value: startSpaceId),
            URLQueryItem(name: "end", value: endSpaceId)
        ]
        
        guard let url = components?.url else { return nil }

        var vizRequest = URLRequest(url: url)
        vizRequest.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        vizRequest.attachBearer()

        do {
            let (data, response) = try await session.data(for: vizRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error fetching route visualization: \(error)")
            return nil
        }
    }
    
    // Legacy helper removed; server returns detailed steps with instructions and coordinates.
    
    private func inferInstruction(from prev: String?, current: String, to next: String?) -> String {
        if prev == nil {
            return "Start at \(current)"
        }
        if next == nil {
            return "Arrive at \(current)"
        }
        return "Go to \(current)"
    }
}

// MARK: - Models

// Server route decoding
private struct ServerRouteStep: Decodable {
    let space_id: String
    let display_name: String?
    let space_type: String?
    let floor_index: Int?
    let building_id: String?
    let centroid_x: Double?
    let centroid_y: Double?
    let centroid_lat: Double?
    let centroid_lng: Double?
    let instruction: String?
    let cost: Double?
}

private struct ServerRoute: Decodable {
    let from_space_id: String
    let to_space_id: String
    let total_cost: Double
    let steps: [ServerRouteStep]
}

struct NavigationRoute {
    let from: String
    let to: String
    let path: [String]
    let totalDistance: Double
    let steps: [NavigationStep]
}

struct NavigationStep {
    let instruction: String
    let spaceId: String
    let stepNumber: Int
    let lat: Double?
    let lon: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let la = lat, let lo = lon else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
}

private struct NearestSpaceItem: Decodable {
    let id: String
    let display_name: String?
    let building_id: String?
    let floor_id: String?
    let campus_id: String?
    let centroid_lat: Double?
    let centroid_lon: Double?
}
