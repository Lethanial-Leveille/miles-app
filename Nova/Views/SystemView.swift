import SwiftUI

// What the Pi reports about itself. A missing reading shows as a dash: the Pi could not take
// it, and showing zero would claim something false.
struct SystemView: View {
    @State private var details: SystemDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // The order a failure matters in: voice is the product, the server feeds this app,
    // and the tunnel is what reaches the Pi from outside
    private let services: [(key: String, label: String)] = [
        ("miles-voice", "VOICE"),
        ("miles-server", "SERVER"),
        ("miles-tunnel", "TUNNEL"),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "SYSTEM") {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .novaFont(13)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .accessibilityLabel("Refresh")
                }

                if isLoading && details == nil {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if let errorMessage, details == nil {
                    Spacer()
                    Text(errorMessage)
                        .novaFont(13, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(24)
                    Spacer()
                } else if let details {
                    ScrollView {
                        VStack(spacing: 0) {
                            if let errorMessage {
                                Text(errorMessage)
                                    .novaFont(11, design: .monospaced)
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(.top, 12)
                            }

                            SectionLabel(title: "SERVICES")
                            ForEach(services, id: \.key) { service in
                                serviceRow(label: service.label, running: details.services[service.key] ?? nil)
                            }

                            SectionLabel(title: "HEALTH")
                            readingRow("UPTIME", uptime(details.uptimeHours))
                            readingRow("CORE TEMP", details.coreTempF.map { String(format: "%.1f°F", $0) })
                            readingRow("VOICE RESTARTS", details.voiceServiceRestarts.map(String.init))

                            SectionLabel(title: "CONVERSATION")
                            readingRow("MEDIAN LATENCY", details.medianLatencyMs.map { String(format: "%.1fs", $0 / 1000) })
                            readingRow("TURNS SERVED", details.turnsServed.map(String.init))
                            readingRow("ACTIVE MEMORIES", details.activeMemories.map(String.init))

                            SectionLabel(title: "BUILD")
                            readingRow("COMMIT", details.gitCommit)
                            readingRow("WHISPER", details.whisperModel)
                        }
                        .padding(.bottom, 32)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func serviceRow(label: String, running: Bool?) -> some View {
        // No red in this app, so down is told apart by a hollow dot and the word, not a color
        let word = running.map { $0 ? "RUNNING" : "DOWN" } ?? "UNKNOWN"
        return HStack(spacing: 12) {
            Circle()
                .strokeBorder(running == true ? Theme.accent : Theme.textSecondary, lineWidth: 1.5)
                .background(Circle().fill(running == true ? Theme.accent : .clear))
                .frame(width: 9, height: 9)
                .shadow(color: running == true ? Theme.accentGlow : .clear, radius: 4)

            Text(label)
                .novaFont(12, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(1)

            Spacer()

            Text(word)
                .novaFont(11, weight: running == false ? .bold : .regular, design: .monospaced)
                .foregroundColor(running == true ? Theme.accent : Theme.textPrimary)
                .tracking(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .accessibilityElement(children: .combine)
    }

    private func readingRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .novaFont(11, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(1)
            Spacer()
            Text(value ?? "—")
                .novaFont(13, design: .monospaced)
                .monospacedDigit()
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .accessibilityElement(children: .combine)
    }

    private func uptime(_ hours: Double?) -> String? {
        guard let hours else { return nil }
        let days = Int(hours / 24)
        let rest = Int(hours.truncatingRemainder(dividingBy: 24))
        return days > 0 ? "\(days)d \(rest)h" : String(format: "%.1fh", hours)
    }

    private func load() async {
        isLoading = true
        do {
            details = try await APIService.fetchStatusDetails()
            errorMessage = nil
        } catch {
            // A failed refresh keeps the last readings on screen and says so above them
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    SystemView()
}
