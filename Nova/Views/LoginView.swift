import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var password      = ""
    @State private var showPassword  = false
    @State private var isLoading     = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated waveform logo
                WaveformMark()
                    .frame(height: 90)
                    .padding(.bottom, 36)

                // App name
                Text("NOVA")
                    .novaFont(38, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(12)

                Text("M.I.L.E.S. INTERFACE")
                    .novaFont(11, weight: .medium, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(4)
                    .padding(.top, 6)
                    .padding(.bottom, 52)

                // FaceID primary button
                Button(action: attemptBiometric) {
                    HStack(spacing: 10) {
                        if isLoading && !showPassword {
                            ProgressView().tint(Theme.background)
                        } else {
                            Image(systemName: "faceid")
                                .novaFont(20, weight: .regular)
                                .foregroundColor(Theme.background)
                            Text("FACE ID")
                                .novaFont(14, weight: .bold, design: .monospaced)
                                .tracking(3)
                                .foregroundColor(Theme.background)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.accent)
                    .cornerRadius(2)
                    .shadow(color: Theme.accentGlow, radius: 16)
                }
                .disabled(isLoading)
                .padding(.horizontal, 40)

                // Toggle to reveal password field
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showPassword.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(showPassword ? "HIDE PASSWORD" : "USE PASSWORD")
                        .novaFont(11, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(2)
                }
                .padding(.top, 20)

                // Password field — slides in when showPassword is true
                if showPassword {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCESS CODE")
                            .novaFont(10, weight: .medium, design: .monospaced)
                            .foregroundColor(Theme.textSecondary)
                            .tracking(3)

                        SecureField("", text: $password)
                            .novaFont(16, weight: .regular, design: .monospaced)
                            .foregroundColor(Theme.textPrimary)
                            .tint(Theme.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.surface)
                            // Clipped first, or the fill's square corners show past the pill
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                            .disabled(isLoading)

                        Button(action: attemptPasswordLogin) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(Theme.background)
                                } else {
                                    Text("AUTHENTICATE")
                                        .novaFont(13, weight: .bold, design: .monospaced)
                                        .tracking(3)
                                        .foregroundColor(Theme.background)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .cornerRadius(2)
                            .shadow(color: Theme.accentGlow, radius: 10)
                        }
                        .disabled(isLoading || password.isEmpty)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Error display
                if let msg = errorMessage {
                    Text(msg)
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 16)
                }

                Spacer()
                Spacer()
            }
        }
    }

    private func attemptBiometric() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authManager.loginWithBiometrics()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func attemptPasswordLogin() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authManager.login(password: password)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: Animated waveform — six bars breathing in and out
private struct WaveformMark: View {
    @State private var isAnimating = false

    // Height ratios match the SVG waveform proportions
    private let ratios: [CGFloat] = [0.40, 0.70, 1.00, 0.85, 0.60, 0.45]
    private let maxH: CGFloat = 80

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(Array(ratios.enumerated()), id: \.offset) { i, ratio in
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 10, height: isAnimating ? maxH * ratio : maxH * ratio * 0.35)
                    .foregroundColor(Theme.accent)
                    .shadow(color: Theme.accentGlow, radius: 8)
                    .animation(
                        .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.13),
                        value: isAnimating
                    )
            }
        }
        // The same rings as Talk Mode, still: the first thing you see is the shape of the app
        .frame(width: 150, height: 150)
        .overlay(Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 1))
        .overlay(
            Circle()
                .inset(by: 14)
                .stroke(Theme.accent.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [1, 6]))
        )
        .onAppear { isAnimating = true }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
