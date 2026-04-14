//
//  NavigationService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import Combine

/// Service for computing routes and navigation
class NavigationService: ObservableObject {
    @Published var currentRoute: NavigationRoute?
    @Published var isLoading = false
    @Published var error: String?
    
    private let baseURL: URL
    private let session: URLSession
    
    init(baseURL: URL = URL(string: "http://localhost:8000/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }
    
    /// Compute fastest path between two spaces
    func computeRoute(from startSpaceId: String, to endSpaceId: String) async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        let endpoint = baseURL.appendingPathComponent("navigation/navigate")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start", value: startSpaceId),
            URLQueryItem(name: "end", value: endSpaceId)
        ]
        
        guard let url = components?.url else {
            DispatchQueue.main.async {
                self.error = "Invalid URL"
                self.isLoading = false
            }
            return
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NSError(domain: "Invalid response", code: -1)
            }
            
            let decoder = JSONDecoder()
            let routeResult = try decoder.decode(NavigationResult.self, from: data)
            
            DispatchQueue.main.async {
                self.currentRoute = NavigationRoute(
                    from: routeResult.start,
                    to: routeResult.end,
                    path: routeResult.path,
                    totalDistance: routeResult.cost,
                    steps: self.generateSteps(from: routeResult)
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
    
    /// Get route visualization as SVG
    func getRouteVisualization(from startSpaceId: String, to endSpaceId: String) async -> String? {
        let endpoint = baseURL.appendingPathComponent("navigation/map")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start", value: startSpaceId),
            URLQueryItem(name: "end", value: endSpaceId)
        ]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await session.data(from: url)
            
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
    
    private func generateSteps(from result: NavigationResult) -> [NavigationStep] {
        var steps: [NavigationStep] = []
        
        // Turn path nodes into navigation steps
        for (index, nodeId) in result.path.enumerated() {
            let instruction = inferInstruction(
                from: index == 0 ? nil : result.path[index - 1],
                current: nodeId,
                to: index < result.path.count - 1 ? result.path[index + 1] : nil
            )
            
            steps.append(NavigationStep(
                instruction: instruction,
                spaceId: nodeId,
                stepNumber: index + 1
            ))
        }
        
        return steps
    }
    
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

struct NavigationResult: Decodable {
    let start: String
    let end: String
    let path: [String]
    let cost: Double
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
}
