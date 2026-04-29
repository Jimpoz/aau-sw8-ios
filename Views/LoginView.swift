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

    private enum SignUpKind: String, CaseIterable, Identifiable {
        case member = "Member of organization"
        case personal = "Personal account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var signUpKind: SignUpKind = .member
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var fullName: String = ""
    @State private var organizationId: String = ""
    @State private var errorText: String?

    @State private var pendingChallenge: String?
    @State private var showForgotPassword: Bool = false

    private var canSubmit: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            if password.count < 8 { return false }
            if signUpKind == .member && organizationId.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
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
                    header

                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in errorText = nil }

                    formCard

                    if mode == .signIn {
                        Button {
                            showForgotPassword = true
                        } label: {
                            Text("Forgot password?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }

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

                    guestDivider

                    Button {
                        Task { await submitGuest() }
                    } label: {
                        HStack(spacing: 8) {
                            if authService.isAuthenticating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "person.crop.circle.dashed")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text("Continue as guest")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.35)))
                    }
                    .disabled(authService.isAuthenticating)

                    Text("Browse public places like malls and airports without creating an account.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
            }
        }
        .sheet(item: Binding(
            get: { pendingChallenge.map(MfaChallenge.init) },
            set: { pendingChallenge = $0?.token }
        )) { challenge in
            MfaChallengeView(challengeToken: challenge.token) { ok in
                pendingChallenge = nil
                if !ok { errorText = "MFA verification cancelled." }
            }
            .environmentObject(authService)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefillEmail: email)
                .environmentObject(authService)
        }
    }

    private var guestDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(height: 1)
            Text("or")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
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
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            if mode == .signUp {
                Picker("", selection: $signUpKind) {
                    ForEach(SignUpKind.allCases) { k in Text(k.rawValue).tag(k) }
                }
                .pickerStyle(.segmented)

                Text(signUpKind == .member
                     ? "Use your organization ID to join your campus, company, or institution."
                     : "Sign up without joining an organization. You'll see public places like malls and airports.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

            if shouldShowOrgField {
                TextField(orgFieldLabel, text: $organizationId)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }

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
    }

    private var shouldShowOrgField: Bool {
        mode == .signIn || (mode == .signUp && signUpKind == .member)
    }

    private var orgFieldLabel: String {
        if mode == .signIn { return "Organization ID (optional)" }
        return "Organization ID"
    }

    private var buttonLabel: String {
        if authService.isAuthenticating {
            return mode == .signIn ? "Signing in…" : "Creating account…"
        }
        return mode.rawValue
    }

    private func submitGuest() async {
        errorText = nil
        do {
            _ = try await authService.loginAsGuest()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
                ?? "Could not continue as guest"
        }
    }

    private func submit() async {
        errorText = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedOrg = organizationId.trimmingCharacters(in: .whitespaces)
        do {
            let outcome: AuthOutcome
            switch mode {
            case .signIn:
                outcome = try await authService.login(
                    email: trimmedEmail,
                    password: password,
                    organizationId: trimmedOrg
                )
            case .signUp:
                let orgForSignup = signUpKind == .member ? trimmedOrg : ""
                outcome = try await authService.signup(
                    email: trimmedEmail,
                    password: password,
                    fullName: fullName.trimmingCharacters(in: .whitespaces),
                    organizationId: orgForSignup
                )
            }
            switch outcome {
            case .authenticated:
                break
            case .mfaRequired(let challengeToken, _):
                pendingChallenge = challengeToken
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription
                ?? (mode == .signIn ? "Sign-in failed" : "Sign-up failed")
        }
    }
}

private struct MfaChallenge: Identifiable {
    let token: String
    var id: String { token }
}

private struct ForgotPasswordSheet: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case requestCode, redeemCode, done }

    let prefillEmail: String

    @State private var stage: Stage = .requestCode
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var newPassword: String = ""
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.blue500)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    switch stage {
                    case .requestCode: requestCodeView
                    case .redeemCode: redeemCodeView
                    case .done: doneView
                    }

                    if let infoText {
                        Text(infoText).font(.system(size: 13)).foregroundStyle(.green)
                    }
                    if let errorText {
                        Text(errorText).font(.system(size: 13)).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { if email.isEmpty { email = prefillEmail } }
        }
    }

    private var requestCodeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset by email")
                .font(.system(size: 18, weight: .bold))
            Text("Enter your email and we'll send a 6-digit code you can use to set a new password.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            input(title: "Email", text: $email, secure: false, content: .emailAddress, keyboard: .emailAddress)

            primary(title: submitting ? "Sending…" : "Send reset code",
                    enabled: !submitting && !email.isEmpty) {
                Task { await submitRequestCode() }
            }
        }
    }

    private var redeemCodeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your code")
                .font(.system(size: 18, weight: .bold))
            Text("If your email is registered, a 6-digit code is on its way. Enter it here with a new password.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            input(title: "Email", text: $email, secure: false, content: .emailAddress, keyboard: .emailAddress)
            input(title: "6-digit code", text: $code, secure: false, content: .oneTimeCode, keyboard: .numberPad)
            input(title: "New password (min 8 chars)", text: $newPassword, secure: true, content: .newPassword)

            primary(title: submitting ? "Resetting…" : "Reset password",
                    enabled: !submitting && code.count >= 6 && newPassword.count >= 8) {
                Task { await submitRedeemCode() }
            }

            Button("Use a different email") {
                stage = .requestCode
                errorText = nil
                infoText = nil
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.blue500)
        }
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Password reset")
                .font(.system(size: 18, weight: .bold))
            Text("You can now sign in with your new password.")
                .font(.system(size: 14))
                .foregroundStyle(Color.slate500)
            Button("Back to sign in") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 30)
    }

    private func input(
        title: String,
        text: Binding<String>,
        secure: Bool,
        content: UITextContentType,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.slate500)
            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                        .keyboardType(keyboard)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .textContentType(content)
            .padding(14)
            .background(Color.slate50, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate100))
        }
    }

    private func primary(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if submitting { ProgressView().tint(.white) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.6)
    }

    private func submitRequestCode() async {
        errorText = nil
        infoText = nil
        submitting = true
        defer { submitting = false }
        do {
            try await authService.requestPasswordReset(
                email: email.trimmingCharacters(in: .whitespaces)
            )
            infoText = "If that email is registered, a 6-digit code is on its way."
            stage = .redeemCode
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not send reset email"
        }
    }

    private func submitRedeemCode() async {
        errorText = nil
        infoText = nil
        submitting = true
        defer { submitting = false }
        do {
            try await authService.resetPassword(
                email: email.trimmingCharacters(in: .whitespaces),
                code: code.trimmingCharacters(in: .whitespaces),
                newPassword: newPassword
            )
            stage = .done
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Invalid or expired code"
        }
    }
}

private struct MfaChallengeView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    let challengeToken: String
    let onFinish: (Bool) -> Void

    @State private var code: String = ""
    @State private var useRecovery: Bool = false
    @State private var errorText: String?
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.blue500)
                    .padding(.top, 8)

                Text(useRecovery ? "Enter a recovery code" : "Two-factor authentication")
                    .font(.system(size: 20, weight: .bold))

                Text(useRecovery
                     ? "Use one of the one-time recovery codes you saved when enabling MFA."
                     : "Open your authenticator app and enter the 6-digit code.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.slate500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                TextField(useRecovery ? "Recovery code" : "123456", text: $code)
                    .keyboardType(useRecovery ? .asciiCapable : .numberPad)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .padding(14)
                    .background(Color.slate50, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate100))
                    .padding(.horizontal, 24)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if submitting { ProgressView().tint(.white) }
                        Text(submitting ? "Verifying…" : "Verify")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(submitting || code.count < 6)
                .opacity(code.count < 6 ? 0.6 : 1.0)
                .padding(.horizontal, 24)

                Button {
                    useRecovery.toggle()
                    code = ""
                    errorText = nil
                } label: {
                    Text(useRecovery
                         ? "Use authenticator code instead"
                         : "Lost your authenticator? Use a recovery code")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.blue500)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Verify identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onFinish(false)
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() async {
        errorText = nil
        submitting = true
        defer { submitting = false }
        do {
            _ = try await authService.completeMfaLogin(
                challengeToken: challengeToken,
                code: code.trimmingCharacters(in: .whitespaces)
            )
            onFinish(true)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Invalid code"
        }
    }
}
