//
//  OrganizationService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import Foundation
import Combine

struct OrganizationDTO: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let entity_type: String?
    let description: String?
}

struct CampusDTO: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let organization_id: String?
}

struct VisibleCampusDTO: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let organization_id: String?
    let organization_name: String?
    let is_public: Bool
}

struct BuildingDTO: Identifiable, Codable, Hashable {
    let id: String
    let campus_id: String
    let name: String
    let short_name: String?
    let address: String?
    let floor_count: Int?
}

@MainActor
final class OrganizationService: ObservableObject {
    @Published var organizations: [OrganizationDTO] = []
    @Published var campuses: [CampusDTO] = []
    @Published var visibleCampuses: [VisibleCampusDTO] = []
    @Published var buildings: [BuildingDTO] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    func loadOrganizations() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            organizations = try await get(path: "organizations", as: [OrganizationDTO].self)
        } catch {
            errorText = "Could not load organizations: \(error.localizedDescription)"
        }
    }

    func loadCampuses(forOrganization orgId: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            campuses = try await get(
                path: "organizations/\(orgId)/campuses",
                as: [CampusDTO].self
            )
        } catch {
            errorText = "Could not load campuses: \(error.localizedDescription)"
        }
    }

    func loadVisibleCampuses() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            visibleCampuses = try await get(
                path: "campuses/visible",
                as: [VisibleCampusDTO].self
            )
        } catch {
            errorText = "Could not load campuses: \(error.localizedDescription)"
        }
    }

    func loadBuildings(forCampus campusId: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let export = try await get(
                path: "campuses/\(campusId)/export",
                as: CampusExportDTO.self
            )
            buildings = export.campus.buildings.map {
                BuildingDTO(
                    id: $0.id,
                    campus_id: campusId,
                    name: $0.name,
                    short_name: $0.short_name,
                    address: $0.address,
                    floor_count: $0.floor_count ?? $0.floors?.count
                )
            }
        } catch {
            errorText = "Could not load buildings: \(error.localizedDescription)"
        }
    }

    private func get<T: Decodable>(path: String, as: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(
                domain: "OrganizationService",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP error fetching \(path)"]
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct CampusExportDTO: Decodable {
    let campus: CampusExportInner
}

private struct CampusExportInner: Decodable {
    let id: String
    let name: String
    let buildings: [BuildingExportDTO]
}

private struct BuildingExportDTO: Decodable {
    let id: String
    let name: String
    let short_name: String?
    let address: String?
    let floor_count: Int?
    let floors: [FloorExportDTO]?
}

private struct FloorExportDTO: Decodable {
    let id: String
    let floor_index: Int?
    let display_name: String?
}
