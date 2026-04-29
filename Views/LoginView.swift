//
//  LoginView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var fullName: String = ""
    @State private var organizationId: String = ""
    @State private var errorText: String?

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp && password.count < 8 { return false }
        return true
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue500, .blue700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Ariadne")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(mode == .signIn ? "Sign in to continue" : "Create your account")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.bottom, 12)

                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in errorText = nil }

                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))

                        SecureField(
                            mode == .signUp ? "Password (min 8 characters)" : "Password",
                            text: $password
                        )
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                        if mode == .signUp {
                            TextField("Full name (optional)", text: $fullName)
                                .textContentType(.name)
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }

                        TextField(
                            mode == .signUp ? "Organization ID" : "Organization ID (optional)",
                            text: $organizationId
                        )
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if authService.isAuthenticating {
                                    ProgressView().tint(.blue700)
                                }
                                Text(buttonLabel)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(Color.blue700)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(authService.isAuthenticating || !canSubmit)
                        .opacity(canSubmit ? 1.0 : 0.6)
                    }
                    .padding(20)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2)))

                    Button {
                        mode = (mode == .signIn) ? .signUp : .signIn
                        errorText = nil
                    } label: {
                        Text(mode == .signIn
                             ? "Don't have an account? Sign up"
                             : "Already have an account? Sign in")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
            }
        }
    }

    private var buttonLabel: String {
        if authService.isAuthenticating {
            return mode == .signIn ? "Signing in…" : "Creating account…"
        }
        return mode.rawValue
    }

    private func submit() async {
        errorText = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedOrg = organizationId.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .signIn:
                try await authService.login(
                    email: trimmedEmail,
                    password: password,
                    organizationId: trimmedOrg
                )
            case .signUp:
                try await authService.signup(
                    email: trimmedEmail,
                    password: password,
                    fullName: fullName.trimmingCharacters(in: .whitespaces),
                    organizationId: trimmedOrg
                )
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
                ?? (mode == .signIn ? "Sign-in failed" : "Sign-up failed")
        }
    }
}
