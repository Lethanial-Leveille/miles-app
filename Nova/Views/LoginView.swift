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
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .tracking(12)

                Text("M.I.L.E.S. INTERFACE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(Theme.background)
                            Text("FACE ID")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(2)
                }
                .padding(.top, 20)

                // Password field — slides in when showPassword is true
                if showPassword {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCESS CODE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                            .tracking(3)

                        SecureField("", text: $password)
                            .font(.system(size: 16, weight: .regular, design: .monospaced))
                            .foregroundColor(Theme.textPrimary)
                            .tint(Theme.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                            )
                            .overlay(HUDCornerBrackets())
                            .disabled(isLoading)

                        Button(action: attemptPasswordLogin) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(Theme.background)
                                } else {
                                    Text("AUTHENTICATE")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 12, design: .monospaced))
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
        .onAppear { isAnimating = true }
    }
}

// MARK: HUD corner brackets on the password field
private struct HUDCornerBrackets: View {
    private let size: CGFloat = 10
    private let thickness: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                bracketPath(corner: .zero, xDir: 1, yDir: 1)
                bracketPath(corner: CGPoint(x: w, y: 0), xDir: -1, yDir: 1)
                bracketPath(corner: CGPoint(x: 0, y: h), xDir: 1, yDir: -1)
                bracketPath(corner: CGPoint(x: w, y: h), xDir: -1, yDir: -1)
            }
        }
    }

    private func bracketPath(corner: CGPoint, xDir: CGFloat, yDir: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: corner.x + xDir * size, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + yDir * size))
        }
        .stroke(Theme.accent.opacity(0.6), lineWidth: thickness)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
