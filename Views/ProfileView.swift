//
//  ProfileView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ProfileView: View {
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var authService: AuthService
    @State private var avoidStairs: Bool = true
    @State private var voiceGuidance: Bool = false
    @State private var elevatorsOnly: Bool = false
    @State private var showRoomPhotoUpload: Bool = false
    @State private var showMfaSetup: Bool = false
    @State private var showMfaDisable: Bool = false
    @State private var showPasswordRecovery: Bool = false

    private var displayName: String {
        authService.principal?.fullName?.isEmpty == false
            ? (authService.principal?.fullName ?? "")
            : (authService.principal?.email ?? "Guest")
    }

    private var mfaEnabled: Bool {
        authService.principal?.mfaEnabled ?? false
    }

    private var subtitle: String {
        guard let p = authService.principal else { return "Not signed in" }
        if let role = p.role, let org = p.organizationId {
            return "\(role.capitalized) · \(org)"
        }
        return p.email
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue500, .blue700], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                        Text(initials(from: displayName))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.slate900)
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.slate500)
                    }
                    Spacer()
                }
                .padding(.top, 12)

                // Stats
                HStack(spacing: 12) {
                    StatCard(title: "Total Distance", value: "4.2 km")
                    StatCard(title: "Steps", value: "5,430")
                }

                // Preferences
                VStack(spacing: 0) {
                    HStack {
                        Text("Navigation Preferences")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.slate700)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.slate50)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

                    VStack(spacing: 16) {
                        ToggleRow(title: "Avoid Stairs", isOn: $avoidStairs)
                        ToggleRow(title: "Voice Guidance", isOn: $voiceGuidance)
                        ToggleRow(title: "Use Elevators Only", isOn: $elevatorsOnly)
                    }
                    .padding(16)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))

                // Security
                VStack(spacing: 0) {
                    HStack {
                        Text("Security")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.slate700)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.slate50)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Two-factor authentication")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.slate700)
                                Text(mfaEnabled ? "Enabled — required at sign-in" : "Off — recommended for owner / editor accounts")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.slate500)
                            }
                            Spacer()
                            if mfaEnabled {
                                Button("Disable") { showMfaDisable = true }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.red)
                            } else {
                                Button("Enable") { showMfaSetup = true }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.blue500)
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Password")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.slate700)
                                Text("Recover or change your password")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.slate500)
                            }
                            Spacer()
                            Button("Recover") { showPasswordRecovery = true }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.blue500)
                        }
                    }
                    .padding(16)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))

                // Theme
                VStack(spacing: 0) {
                    HStack {
                        Text("Appearance")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.slate700)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.slate50)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

                    VStack(spacing: 16) {
                        HStack {
                            Text("Dark Mode")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.slate600)
                            Spacer()
                            Toggle("", isOn: $themeSettings.isDarkMode)
                                .labelsHidden()
                        }
                    }
                    .padding(16)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))

                Button {
                    showRoomPhotoUpload = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Upload Room Photos")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.blue500)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue500.opacity(0.2)))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 6)

                Button(role: .destructive) { authService.logout() } label: {
                    Text("Log Out")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.red.opacity(0.15)))
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.slate50)
        .sheet(isPresented: $showRoomPhotoUpload) {
            RoomPhotoUploadView()
        }
        .sheet(isPresented: $showMfaSetup) {
            MfaEnrollmentSheet()
                .environmentObject(authService)
        }
        .sheet(isPresented: $showMfaDisable) {
            MfaDisableSheet()
                .environmentObject(authService)
        }
        .sheet(isPresented: $showPasswordRecovery) {
            PasswordRecoverySheet()
                .environmentObject(authService)
        }
        .task {
            try? await authService.refreshPrincipal()
        }
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2).map { $0.first.map(String.init) ?? "" }.joined()
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.slate400)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.slate800)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Color.slate600)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct MfaEnrollmentSheet: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private enum Method: String, CaseIterable, Identifiable {
        case totp = "Authenticator"
        case email = "Email"
        var id: String { rawValue }
    }

    private enum Stage { case picking, loading, ready, confirming, done }

    @State private var stage: Stage = .picking
    @State private var method: Method = .totp
    @State private var enrollment: MfaEnrollment?
    @State private var emailEnrollment: MfaEmailEnrollment?
    @State private var code: String = ""
    @State private var errorText: String?
    @State private var savedCodes: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch stage {
                    case .picking:
                        methodPicker
                    case .loading:
                        ProgressView(method == .email ? "Emailing your code…" : "Generating secret…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    case .ready, .confirming:
                        if method == .totp, let enrollment {
                            secretSection(enrollment)
                            recoverySection(codes: enrollment.recoveryCodes)
                            confirmSection(label: "the 6-digit code from your authenticator")
                        } else if method == .email, let emailEnrollment {
                            emailIntro
                            recoverySection(codes: emailEnrollment.recoveryCodes)
                            confirmSection(label: "the 6-digit code we just emailed you")
                        }
                    case .done:
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.green)
                            Text("MFA enabled")
                                .font(.system(size: 20, weight: .bold))
                            Text(method == .email
                                 ? "From now on you'll receive a one-time code by email at sign-in."
                                 : "From now on, you'll be asked for a 6-digit code at sign-in.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.slate500)
                                .multilineTextAlignment(.center)
                            Button("Done") { dismiss() }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.top, 8)
                        }
                        .padding(.top, 40)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Enable two-factor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pick a second factor")
                .font(.system(size: 18, weight: .bold))
            Text("You can use an authenticator app (more secure, works offline) or have a one-time code emailed to you on every sign-in.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            Picker("", selection: $method) {
                ForEach(Method.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await begin() }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var emailIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 1 — Check your inbox")
                .font(.system(size: 14, weight: .bold))
            Text("We just emailed a 6-digit code to \(authService.principal?.email ?? "your account email"). It expires in a few minutes.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)
        }
    }

    private func secretSection(_ e: MfaEnrollment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 1 — Add to your authenticator")
                .font(.system(size: 14, weight: .bold))
            Text("Open Google Authenticator, 1Password, or Authy and either scan the QR code below or type the secret in by hand.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            HStack {
                Spacer()
                QRCodeView(text: e.provisioningURI)
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate100))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Or enter the secret manually")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.slate400)
                Text(e.secret)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.slate50, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func recoverySection(codes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 2 — Save your recovery codes")
                .font(.system(size: 14, weight: .bold))
            Text("These one-time codes can replace your second factor if you lose access to it. They are shown ONCE — store them somewhere safe.")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(codes, id: \.self) { c in
                    Text(c)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.slate50, in: RoundedRectangle(cornerRadius: 10))

            Toggle("I've saved these codes somewhere safe", isOn: $savedCodes)
                .font(.system(size: 13))
        }
    }

    private func confirmSection(label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step 3 — Confirm with a code")
                .font(.system(size: 14, weight: .bold))
            Text("Enter \(label).")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .padding(14)
                .background(Color.slate50, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate100))

            Button {
                Task { await confirm() }
            } label: {
                HStack {
                    if stage == .confirming { ProgressView().tint(.white) }
                    Text(stage == .confirming ? "Verifying…" : "Confirm and enable")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(stage == .confirming || code.count < 6 || !savedCodes)
            .opacity((code.count < 6 || !savedCodes) ? 0.6 : 1.0)
        }
    }

    private func begin() async {
        errorText = nil
        stage = .loading
        do {
            switch method {
            case .totp:
                let result = try await authService.setupMfa()
                self.enrollment = result
            case .email:
                let result = try await authService.setupMfaEmail()
                self.emailEnrollment = result
            }
            self.stage = .ready
        } catch {
            stage = .picking
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not start MFA setup"
        }
    }

    private func confirm() async {
        errorText = nil
        stage = .confirming
        do {
            switch method {
            case .totp:
                try await authService.confirmMfa(code: code.trimmingCharacters(in: .whitespaces))
            case .email:
                guard let challenge = emailEnrollment?.challengeToken else {
                    throw AuthError.unauthorized("Setup expired — request a new code")
                }
                try await authService.confirmMfaEmail(
                    challengeToken: challenge,
                    code: code.trimmingCharacters(in: .whitespaces)
                )
            }
            stage = .done
        } catch {
            stage = .ready
            errorText = (error as? LocalizedError)?.errorDescription ?? "Invalid code"
        }
    }
}

private struct MfaDisableSheet: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var password: String = ""
    @State private var errorText: String?
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Disable two-factor authentication")
                    .font(.system(size: 18, weight: .bold))
                Text("Enter your password to confirm. Your authenticator pairing and recovery codes will be wiped.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.slate500)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(14)
                    .background(Color.slate50, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.slate100))

                if let errorText {
                    Text(errorText).font(.system(size: 13)).foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if submitting { ProgressView().tint(.white) }
                        Text(submitting ? "Disabling…" : "Disable MFA")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(submitting || password.isEmpty)
                .opacity(password.isEmpty ? 0.6 : 1.0)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Disable MFA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorText = nil
        submitting = true
        defer { submitting = false }
        do {
            try await authService.disableMfa(password: password)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not disable MFA"
        }
    }
}

private struct PasswordRecoverySheet: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case change = "Change"
        case reset = "Email reset"
        var id: String { rawValue }
    }

    private enum ResetStage { case requestCode, redeemCode, done }

    @State private var mode: Mode = .change

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    @State private var resetStage: ResetStage = .requestCode
    @State private var resetEmail: String = ""
    @State private var resetCode: String = ""
    @State private var resetNewPassword: String = ""

    @State private var errorText: String?
    @State private var infoText: String?
    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in clearMessages() }

                    if mode == .change {
                        changeSection
                    } else {
                        resetSection
                    }

                    if let infoText {
                        Text(infoText)
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                resetEmail = authService.principal?.email ?? ""
            }
        }
    }

    private var changeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change your password")
                .font(.system(size: 16, weight: .bold))
            Text("Enter your current password to confirm, then pick a new one (at least 8 characters).")
                .font(.system(size: 13))
                .foregroundStyle(Color.slate500)

            field(title: "Current password", text: $currentPassword, secure: true, content: .password)
            field(title: "New password", text: $newPassword, secure: true, content: .newPassword)
            field(title: "Confirm new password", text: $confirmPassword, secure: true, content: .newPassword)

            primaryButton(title: submitting ? "Updating…" : "Update password",
                          enabled: canSubmitChange) {
                Task { await submitChange() }
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        switch resetStage {
        case .requestCode:
            VStack(alignment: .leading, spacing: 12) {
                Text("Email me a reset code")
                    .font(.system(size: 16, weight: .bold))
                Text("We'll send a 6-digit code to your email. Enter it on the next step along with a new password.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.slate500)

                field(title: "Email", text: $resetEmail, secure: false, content: .emailAddress, keyboard: .emailAddress)

                primaryButton(title: submitting ? "Sending…" : "Send code",
                              enabled: !submitting && !resetEmail.isEmpty) {
                    Task { await submitRequestCode() }
                }
            }
        case .redeemCode:
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter the code we emailed you")
                    .font(.system(size: 16, weight: .bold))
                Text("If your email is registered, a 6-digit code is on its way. Enter it here with a new password.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.slate500)

                field(title: "Email", text: $resetEmail, secure: false, content: .emailAddress, keyboard: .emailAddress)
                field(title: "6-digit code", text: $resetCode, secure: false, content: .oneTimeCode, keyboard: .numberPad)
                field(title: "New password", text: $resetNewPassword, secure: true, content: .newPassword)

                primaryButton(title: submitting ? "Resetting…" : "Reset password",
                              enabled: canSubmitReset) {
                    Task { await submitRedeemCode() }
                }

                Button("Use a different email") {
                    resetStage = .requestCode
                    clearMessages()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.blue500)
            }
        case .done:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Password updated")
                    .font(.system(size: 18, weight: .bold))
                Text("You can now sign in with the new password.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.slate500)
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 30)
        }
    }

    private func field(
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

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if submitting { ProgressView().tint(.white) }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue500, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled || submitting)
        .opacity((!enabled || submitting) ? 0.6 : 1.0)
    }

    private var canSubmitChange: Bool {
        !submitting
        && !currentPassword.isEmpty
        && newPassword.count >= 8
        && newPassword == confirmPassword
    }

    private var canSubmitReset: Bool {
        !submitting
        && !resetEmail.isEmpty
        && resetCode.count >= 6
        && resetNewPassword.count >= 8
    }

    private func clearMessages() {
        errorText = nil
        infoText = nil
    }

    private func submitChange() async {
        clearMessages()
        submitting = true
        defer { submitting = false }
        do {
            try await authService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            infoText = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not change password"
        }
    }

    private func submitRequestCode() async {
        clearMessages()
        submitting = true
        defer { submitting = false }
        do {
            try await authService.requestPasswordReset(email: resetEmail.trimmingCharacters(in: .whitespaces))
            infoText = "If that email is registered, a 6-digit code is on its way."
            resetStage = .redeemCode
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not send reset email"
        }
    }

    private func submitRedeemCode() async {
        clearMessages()
        submitting = true
        defer { submitting = false }
        do {
            try await authService.resetPassword(
                email: resetEmail.trimmingCharacters(in: .whitespaces),
                code: resetCode.trimmingCharacters(in: .whitespaces),
                newPassword: resetNewPassword
            )
            resetStage = .done
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Invalid or expired code"
        }
    }
}

private struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.render(text: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code for authenticator setup")
        } else {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
        }
    }

    private static func render(text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

#Preview("Profile") { ProfileView() }
