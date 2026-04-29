//
//  AuthService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import Foundation
import Combine

struct AuthPrincipal: Equatable {
    let userId: String
    let email: String
    let organizationId: String?
    let role: String?
    let fullName: String?
    let mfaEnabled: Bool
}

enum AuthOutcome {
    case authenticated
    case mfaRequired(challengeToken: String, expiresAt: String?)
}

struct MfaEnrollment: Equatable {
    let secret: String
    let provisioningURI: String
    let recoveryCodes: [String]
}

struct MfaEmailEnrollment: Equatable {
    let challengeToken: String
    let challengeExpiresAt: String?
    let recoveryCodes: [String]
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

    func login(email: String, password: String, organizationId: String?) async throws -> AuthOutcome {
        isAuthenticating = true
        defer { isAuthenticating = false }
        var body: [String: Any] = ["email": email, "password": password]
        if let org = organizationId, !org.isEmpty { body["organization_id"] = org }

        let response: AuthResponseDTO = try await post(path: "auth/login", body: body)
        return try await consume(response: response)
    }

    func signup(email: String, password: String, fullName: String?, organizationId: String?) async throws -> AuthOutcome {
        isAuthenticating = true
        defer { isAuthenticating = false }
        var body: [String: Any] = ["email": email, "password": password]
        if let name = fullName, !name.isEmpty { body["full_name"] = name }
        if let org = organizationId, !org.isEmpty { body["organization_id"] = org }

        let response: AuthResponseDTO = try await post(path: "auth/signup", body: body)
        return try await consume(response: response)
    }

    func loginAsGuest() async throws -> AuthOutcome {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let response: AuthResponseDTO = try await post(path: "auth/guest", body: [:])
        return try await consume(response: response)
    }

    func completeMfaLogin(challengeToken: String, code: String) async throws -> AuthOutcome {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let body: [String: Any] = [
            "challenge_token": challengeToken,
            "code": code,
        ]
        let response: AuthResponseDTO = try await post(path: "auth/login/mfa", body: body)
        return try await consume(response: response)
    }

    func setupMfa() async throws -> MfaEnrollment {
        let token = try requireToken()
        let response: MfaSetupDTO = try await post(
            path: "auth/mfa/setup",
            body: [:],
            bearer: token
        )
        return MfaEnrollment(
            secret: response.secret,
            provisioningURI: response.provisioning_uri,
            recoveryCodes: response.recovery_codes
        )
    }

    func confirmMfa(code: String) async throws {
        let token = try requireToken()
        let _: MfaStateDTO = try await post(
            path: "auth/mfa/confirm",
            body: ["code": code],
            bearer: token
        )
        try? await refreshPrincipal()
    }

    func disableMfa(password: String) async throws {
        let token = try requireToken()
        let _: MfaStateDTO = try await post(
            path: "auth/mfa/disable",
            body: ["password": password],
            bearer: token
        )
        try? await refreshPrincipal()
    }

    func setupMfaEmail() async throws -> MfaEmailEnrollment {
        let token = try requireToken()
        let response: MfaEmailSetupDTO = try await post(
            path: "auth/mfa/email/setup",
            body: [:],
            bearer: token
        )
        return MfaEmailEnrollment(
            challengeToken: response.setup_challenge_token,
            challengeExpiresAt: response.challenge_expires_at,
            recoveryCodes: response.recovery_codes
        )
    }

    func confirmMfaEmail(challengeToken: String, code: String) async throws {
        let token = try requireToken()
        let _: MfaStateDTO = try await post(
            path: "auth/mfa/email/confirm",
            body: ["challenge_token": challengeToken, "code": code],
            bearer: token
        )
        try? await refreshPrincipal()
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        let token = try requireToken()
        try await postNoBody(
            path: "auth/password/change",
            body: ["current_password": currentPassword, "new_password": newPassword],
            bearer: token
        )
    }

    func requestPasswordReset(email: String) async throws {
        try await postNoBody(
            path: "auth/password/forgot",
            body: ["email": email]
        )
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        try await postNoBody(
            path: "auth/password/reset",
            body: ["email": email, "code": code, "new_password": newPassword]
        )
    }

    func logout() {
        Keychain.deleteJWT()
        self.principal = nil
    }

    private func requireToken() throws -> String {
        guard let token = Keychain.loadJWT() else {
            throw AuthError.unauthorized("Not signed in")
        }
        return token
    }

    private func consume(response: AuthResponseDTO) async throws -> AuthOutcome {
        if response.mfa_required == true {
            guard let challenge = response.challenge_token else {
                throw AuthError.decode
            }
            return .mfaRequired(
                challengeToken: challenge,
                expiresAt: response.challenge_expires_at
            )
        }
        guard let token = response.token, let user = response.user else {
            throw AuthError.decode
        }
        Keychain.saveJWT(token)

        self.principal = AuthPrincipal(
            userId: user.id,
            email: user.email,
            organizationId: response.organization_id,
            role: response.role,
            fullName: user.full_name,
            mfaEnabled: false
        )
        self.enforcementOn = true
        Task { try? await self.refreshPrincipal() }
        return .authenticated
    }
    
    func refreshPrincipal() async throws {
        guard let token = Keychain.loadJWT() else { return }
        let me = try await fetchMe(token: token)
        self.principal = me
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
            fullName: me.full_name,
            mfaEnabled: me.mfa_enabled ?? false
        )
    }

    private func postNoBody(
        path: String,
        body: [String: Any],
        bearer: String? = nil
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.decode }
        if (200...299).contains(http.statusCode) { return }
        let message = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.detail
            ?? "HTTP \(http.statusCode)"
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AuthError.unauthorized(message)
        }
        throw AuthError.server(http.statusCode, message)
    }

    private func post<T: Decodable>(
        path: String,
        body: [String: Any],
        bearer: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
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
    let mfa_required: Bool?
    let challenge_token: String?
    let challenge_expires_at: String?
    let token: String?
    let user: UserDTO?
    let organization_id: String?
    let role: String?
}

private struct MeResponseDTO: Decodable {
    let id: String
    let email: String
    let full_name: String?
    let organization_id: String?
    let role: String?
    let mfa_enabled: Bool?
}

private struct MfaSetupDTO: Decodable {
    let secret: String
    let provisioning_uri: String
    let recovery_codes: [String]
}

private struct MfaEmailSetupDTO: Decodable {
    let setup_challenge_token: String
    let challenge_expires_at: String?
    let recovery_codes: [String]
}

private struct MfaStateDTO: Decodable {
    let mfa_enabled: Bool
}

private struct ErrorDTO: Decodable {
    let detail: String?
}
