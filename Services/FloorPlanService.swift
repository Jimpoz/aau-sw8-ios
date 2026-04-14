//
//  FloorPlanService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import Combine

/// Service for fetching floor plan geometry and building data
class FloorPlanService: ObservableObject {
    @Published var floorGeometry: FloorGeometry?
    @Published var rooms: [Room] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let baseURL: URL
    private let session: URLSession
    
    init(baseURL: URL = URL(string: "http://localhost:8000/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }
    
    /// Fetch floor plan geometry for a specific floor
    func fetchFloorGeometry(floorId: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        let url = baseURL.appendingPathComponent("floors/\(floorId)/geometry")
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "Invalid response", code: -1)
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(FloorGeometryResponse.self, from: data)
            
            DispatchQueue.main.async {
                self.rooms = result.rooms
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to load floor geometry: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    /// Fetch floor data (metadata)
    func fetchFloor(floorId: String) async -> Floor? {
        let url = baseURL.appendingPathComponent("floors/\(floorId)")
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let floor = try decoder.decode(Floor.self, from: data)
            return floor
        } catch {
            print("Error fetching floor: \(error)")
            return nil
        }
    }
}

// MARK: - Response Models

struct FloorGeometryResponse: Decodable {
    let floor: Floor
    let rooms: [Room]
    let count: Int
}
