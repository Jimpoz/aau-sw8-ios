//
//  LoginView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var organizationId: String = ""
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue500, .blue700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Ariadne")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Sign in to continue")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, 12)

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    TextField("Organization ID (optional)", text: $organizationId)
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
                            Text(authService.isAuthenticating ? "Signing in…" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(Color.blue700)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(authService.isAuthenticating || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                }
                .padding(20)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2)))

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        }
    }

    private func submit() async {
        errorText = nil
        do {
            try await authService.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                organizationId: organizationId.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
                ?? "Sign-in failed"
        }
    }
}
