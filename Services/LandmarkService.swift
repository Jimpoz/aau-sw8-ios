//
//  LandmarkService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/05/26.
//

import CoreLocation
import Foundation
import UIKit

struct RegisteredLandmark: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let space_id: String
    let building_id: String?
    let campus_id: String?
    let image_width: Int?
    let image_height: Int?
    let centroid_x: Double?
    let centroid_y: Double?
    let centroid_lat: Double?
    let centroid_lng: Double?
    let created_by: String?
    let created_at: String?
}

enum LandmarkServiceError: LocalizedError {
    case badImage
    case http(Int, String?)
    case decode(Error)
    case forbidden

    var errorDescription: String? {
        switch self {
        case .badImage:
            return "Could not encode the captured image. Try again."
        case .forbidden:
            return "Only owners and editors can register landmarks."
        case .http(let status, let body):
            return "Server error \(status)\(body.map { ": \($0)" } ?? "")"
        case .decode(let err):
            return "Decoder failed: \(err.localizedDescription)"
        }
    }
}

final class LandmarkService {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }


    func register(
        image: UIImage,
        name: String,
        spaceId: String,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws -> RegisteredLandmark {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw LandmarkServiceError.badImage
        }
        let url = baseURL.appendingPathComponent("landmarks")
        let boundary = "ariadne-boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"name\"\r\n\r\n")
        append("\(name)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"space_id\"\r\n\r\n")
        append("\(spaceId)\r\n")

        if let coordinate {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"centroid_lat\"\r\n\r\n")
            append("\(coordinate.latitude)\r\n")
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"centroid_lng\"\r\n\r\n")
            append("\(coordinate.longitude)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"landmark.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n")

        append("--\(boundary)--\r\n")

        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else {
            throw LandmarkServiceError.http(0, nil)
        }
        if http.statusCode == 403 { throw LandmarkServiceError.forbidden }
        guard (200..<300).contains(http.statusCode) else {
            throw LandmarkServiceError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(RegisteredLandmark.self, from: data)
        } catch {
            throw LandmarkServiceError.decode(error)
        }
    }

    /// GET /landmarks?space_id=...  or  ?building_id=...
    func list(spaceId: String? = nil, buildingId: String? = nil) async throws -> [RegisteredLandmark] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("landmarks"),
            resolvingAgainstBaseURL: false
        )!
        var qs: [URLQueryItem] = []
        if let spaceId { qs.append(URLQueryItem(name: "space_id", value: spaceId)) }
        if let buildingId { qs.append(URLQueryItem(name: "building_id", value: buildingId)) }
        comps.queryItems = qs

        var request = URLRequest(url: comps.url!)
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LandmarkServiceError.http(status, String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode([RegisteredLandmark].self, from: data)
        } catch {
            throw LandmarkServiceError.decode(error)
        }
    }

    /// DELETE /landmarks/{id}. Owner-or-editor only.
    func delete(id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("landmarks/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 { throw LandmarkServiceError.forbidden }
            throw LandmarkServiceError.http(status, String(data: data, encoding: .utf8))
        }
    }
}
