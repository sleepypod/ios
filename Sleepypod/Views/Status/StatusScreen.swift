import SwiftUI

struct StatusScreen: View {
    @Environment(StatusManager.self) private var statusManager
    @Environment(ScheduleManager.self) private var scheduleManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Health circle
                HealthCircleView()

                // Service categories
                let cats = statusManager.categories(schedules: scheduleManager.schedules)
                if cats.isEmpty && statusManager.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                } else {
                    ForEach(cats) { category in
                        ServiceCategoryView(category: category) { service in
                            Task { await statusManager.retryService(service) }
                        }
                    }
                }

                // Biometrics toggle
                if let services = statusManager.services {
                    VStack(spacing: 12) {
                        toggleRow(title: "Biometrics",
                                  description: "Sleep tracking and analysis",
                                  isOn: services.biometrics.enabled) {
                            Task { await statusManager.toggleBiometrics() }
                        }
                        toggleRow(title: "Sentry Logging",
                                  description: "Error reporting service",
                                  isOn: services.sentryLogging.enabled) {
                            Task { await statusManager.toggleSentryLogging() }
                        }
                    }
                    .cardStyle()
                }

                // Logs
                LogsView()

                // Last updated
                if let lastUpdated = statusManager.lastUpdated {
                    Text("Last updated: \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .task {
            statusManager.startPolling()
            await scheduleManager.fetchSchedules()
        }
    }

    private func toggleRow(title: String, description: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in Haptics.medium(); action() }))
                .tint(Theme.cooling)
                .labelsHidden()
        }
    }
}
