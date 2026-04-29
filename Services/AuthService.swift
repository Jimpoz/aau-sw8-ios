//
//  AuthService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import Foundation

struct AuthPrincipal: Equatable {
    let userId: String
    let email: String
    let organizationId: String?
    let role: String?
    let fullName: String?
}

enum AuthError: Error, LocalizedError {
    case network(String)
    case unauthorized(String)
    case server(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .unauthorized(let m): return m
        case .server(_, let m): return m
        case .decode: return "Could not decode server response"
        }
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var principal: AuthPrincipal?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var enforcementOn = false
    @Published private(set) var didProbe = false

    private let baseURL: URL
    private let session: URLSession

    var isAuthenticated: Bool { principal != nil }
    var token: String? { Keychain.loadJWT() }

    init(baseURL: URL = URL(string: AppSecrets.backendURL + "/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    /// Probe /auth/me on launch. Resolves enforcementOn so the UI knows
    /// whether to gate the app behind a login screen.
    func probe() async {
        defer { didProbe = true }
        guard let token = Keychain.loadJWT() else {
            await detectEnforcement()
            return
        }
        do {
            let me = try await fetchMe(token: token)
            self.principal = me
            self.enforcementOn = true
        } catch AuthError.unauthorized {
            Keychain.deleteJWT()
            self.principal = nil
            self.enforcementOn = true
        } catch AuthError.server(let code, _) where code == 404 {
            self.enforcementOn = false
        } catch {
            await detectEnforcement()
        }
    }

    private func detectEnforcement() async {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                self.enforcementOn = http.statusCode != 404
            }
        } catch {
            self.enforcementOn = false
        }
    }

    func login(email: String, password: String, organizationId: String?) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        var body: [String: Any] = ["email": email, "password": password]
        if let org = organizationId, !org.isEmpty { body["organization_id"] = org }

        let response: AuthResponseDTO = try await post(path: "auth/login", body: body)
        Keychain.saveJWT(response.token)
        self.principal = AuthPrincipal(
            userId: response.user.id,
            email: response.user.email,
            organizationId: response.organization_id,
            role: response.role,
            fullName: response.user.full_name
        )
        self.enforcementOn = true
    }

    func signup(email: String, password: String, fullName: String?, organizationId: String?) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        var body: [String: Any] = ["email": email, "password": password]
        if let name = fullName, !name.isEmpty { body["full_name"] = name }
        if let org = organizationId, !org.isEmpty { body["organization_id"] = org }

        let response: AuthResponseDTO = try await post(path: "auth/signup", body: body)
        Keychain.saveJWT(response.token)
        self.principal = AuthPrincipal(
            userId: response.user.id,
            email: response.user.email,
            organizationId: response.organization_id,
            role: response.role,
            fullName: response.user.full_name
        )
        self.enforcementOn = true
    }

    func logout() {
        Keychain.deleteJWT()
        self.principal = nil
    }

    private func fetchMe(token: String) async throws -> AuthPrincipal {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.decode }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AuthError.unauthorized("Session expired")
        }
        if !(200...299).contains(http.statusCode) {
            throw AuthError.server(http.statusCode, "HTTP \(http.statusCode)")
        }
        guard let me = try? JSONDecoder().decode(MeResponseDTO.self, from: data) else {
            throw AuthError.decode
        }
        return AuthPrincipal(
            userId: me.id,
            email: me.email,
            organizationId: me.organization_id,
            role: me.role,
            fullName: me.full_name
        )
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.decode }
        if !(200...299).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.detail
                ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AuthError.unauthorized(message)
            }
            throw AuthError.server(http.statusCode, message)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw AuthError.decode
        }
        return decoded
    }
}

// MARK: - Wire DTOs

private struct UserDTO: Decodable {
    let id: String
    let email: String
    let full_name: String?
}

private struct AuthResponseDTO: Decodable {
    let token: String
    let user: UserDTO
    let organization_id: String?
    let role: String?
}

private struct MeResponseDTO: Decodable {
    let id: String
    let email: String
    let full_name: String?
    let organization_id: String?
    let role: String?
}

private struct ErrorDTO: Decodable {
    let detail: String?
}
