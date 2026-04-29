//
//  RoomSummaryService.swift
//  aau-sw8-ios
//

import Foundation
import UIKit

/// Service for the image_pipeline room-summary API.
///
/// Endpoints (proxied through the middleware under /api/v1/room-summary):
///   GET  /rooms                      → list of room display names
///   POST /room-objects/setup         → runs YOLO on 4 images and persists
///                                      the result onto the matched Space node
final class RoomSummaryService {
    enum CompassDirection: String, CaseIterable, Identifiable {
        case north, east, south, west
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ServiceError: LocalizedError {
        case badURL
        case encodingFailed(CompassDirection)
        case http(Int, String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid server URL."
            case .encodingFailed(let d):
                return "Could not encode the \(d.label) image as JPEG."
            case .http(let code, let body):
                return "Server error \(code): \(body)"
            case .invalidResponse:
                return "Unexpected response from the server."
            }
        }
    }

    struct RoomSetupResponse: Decodable {
        let room_name: String
        let room_objects: [String]?
        let room_object_counts: [String: Int]?
        let stored_image_count: Int?
        let stored_views: [String]?
    }

    private let baseURL: String
    private let session: URLSession

    init(
        baseURL: String = AppSecrets.backendURL,
        session: URLSession = {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 180
            return URLSession(configuration: cfg)
        }()
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Fetch the list of room display names available for room-summary setup.
    func listRooms() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/v1/room-summary/rooms") else {
            throw ServiceError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.http(http.statusCode, body)
        }

        struct RoomsResponse: Decodable { let names: [String] }
        return try JSONDecoder().decode(RoomsResponse.self, from: data).names
    }

    /// Upload four room images (one per compass direction) and persist the
    /// resulting summary onto the `Space` node whose name matches `roomName`.
    func uploadRoomPhotos(
        roomName: String,
        images: [CompassDirection: UIImage],
        jpegQuality: CGFloat = 0.85
    ) async throws -> RoomSetupResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/room-summary/room-objects/setup") else {
            throw ServiceError.badURL
        }

        let boundary = "ariadne-boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"room_name\"\r\n\r\n")
        append("\(roomName)\r\n")

        for direction in CompassDirection.allCases {
            guard let image = images[direction] else {
                throw ServiceError.encodingFailed(direction)
            }
            guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else {
                throw ServiceError.encodingFailed(direction)
            }
            let field = "\(direction.rawValue)_image"
            let filename = "\(direction.rawValue).jpg"
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(jpeg)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")

        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.http(http.statusCode, txt)
        }
        return try JSONDecoder().decode(RoomSetupResponse.self, from: data)
    }
}
