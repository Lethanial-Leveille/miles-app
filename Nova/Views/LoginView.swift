import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var password      = ""
    @State private var isLoading     = false
    @State private var errorMessage: String? = nil

    var onLoginSuccess: () -> Void

    var body: some View {
        ZStack {
            Theme.background(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Logo
                NovaLogoMark(colorScheme: colorScheme)
                    .padding(.bottom, 16)

                Text("NOVA")
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary(colorScheme))
                    .tracking(12)

                // Gold subtitle — Nova Corps identity color, not the blue system accent
                Text("AI INTERFACE SYSTEM")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.gold(colorScheme))
                    .tracking(4)
                    .padding(.top, 6)
                    .padding(.bottom, 52)

                // MARK: Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACCESS CODE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary(colorScheme))
                        .tracking(3)

                    SecureField("", text: $password)
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.textPrimary(colorScheme))
                        .tint(Theme.accent(colorScheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Theme.surface(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.accent(colorScheme).opacity(0.4), lineWidth: 1)
                        )
                        .disabled(isLoading)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 24)

                // MARK: Error message
                if let message = errorMessage {
                    Text(message)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                }

                // MARK: Login button with HUD corner brackets
                Button {
                    attemptLogin()
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .tint(Theme.background(colorScheme))
                        } else {
                            Text("AUTHENTICATE")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .tracking(3)
                                .foregroundColor(Theme.background(colorScheme))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent(colorScheme))
                    .cornerRadius(2)
                    .shadow(color: Theme.glow(colorScheme), radius: 12, x: 0, y: 0)
                    .overlay(HUDCornerBrackets(color: Theme.gold(colorScheme)))
                }
                .disabled(isLoading || password.isEmpty)
                .padding(.horizontal, 40)

                Spacer()
                Spacer()
            }
        }
    }

    private func attemptLogin() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await AuthService.login(password: password)
                await MainActor.run { onLoginSuccess() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: Nova logo — gold outer rings (identity), blue inner ring (system active)
private struct NovaLogoMark: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            // Outermost ring: gold, very faint — ambient identity halo
            Circle()
                .stroke(Theme.gold(colorScheme).opacity(0.18), lineWidth: 1)
                .frame(width: 120, height: 120)

            // Second ring: gold, more visible
            Circle()
                .stroke(Theme.gold(colorScheme).opacity(0.45), lineWidth: 1)
                .frame(width: 94, height: 94)

            // Inner ring: blue — the active system indicator, glowing
            Circle()
                .stroke(Theme.accent(colorScheme), lineWidth: 1.5)
                .frame(width: 66, height: 66)
                .shadow(color: Theme.glow(colorScheme), radius: 10)

            // Center N: gold with gold glow — the Nova Corps emblem
            Text("N")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.gold(colorScheme))
                .shadow(color: Theme.goldGlow(colorScheme), radius: 8)
        }
    }
}

// MARK: HUD corner brackets drawn with paths — gold accent on the button
private struct HUDCornerBrackets: View {
    let color: Color
    private let size: CGFloat = 10
    private let thickness: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Top left
                bracketPath(corner: .zero, xDir: 1, yDir: 1)
                // Top right
                bracketPath(corner: CGPoint(x: w, y: 0), xDir: -1, yDir: 1)
                // Bottom left
                bracketPath(corner: CGPoint(x: 0, y: h), xDir: 1, yDir: -1)
                // Bottom right
                bracketPath(corner: CGPoint(x: w, y: h), xDir: -1, yDir: -1)
            }
        }
    }

    private func bracketPath(corner: CGPoint, xDir: CGFloat, yDir: CGFloat) -> some View {
        Path { path in
            // Horizontal arm
            path.move(to: CGPoint(x: corner.x + xDir * size, y: corner.y))
            path.addLine(to: corner)
            // Vertical arm
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + yDir * size))
        }
        .stroke(color, lineWidth: thickness)
    }
}

#Preview {
    LoginView(onLoginSuccess: {})
}
