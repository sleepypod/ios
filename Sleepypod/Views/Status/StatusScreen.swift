import SwiftUI

struct StatusScreen: View {
    @Environment(StatusManager.self) private var statusManager
    @Environment(ScheduleManager.self) private var scheduleManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PodDiscovery.self) private var podDiscovery

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

                // Network discovery
                networkDiscoveryCard

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

    // MARK: - Network Discovery

    @State private var isDiscoveryExpanded = false

    private var networkDiscoveryCard: some View {
        VStack(spacing: 0) {
            // Header — matches ServiceCategoryView style
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDiscoveryExpanded.toggle()
                }
                // Only scan when disconnected — don't disrupt active connection
                if isDiscoveryExpanded && !deviceManager.isConnected && !podDiscovery.isSearching {
                    podDiscovery.startBrowsing()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Network Discovery")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("mDNS auto-discovery")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    // Status badge — matches ServiceCategoryView pattern
                    HStack(spacing: 4) {
                        Image(systemName: deviceManager.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(deviceManager.isConnected ? Theme.healthy : Theme.amber)
                        Text(deviceManager.isConnected ? "1/1" : "0/1")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isDiscoveryExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isDiscoveryExpanded {
                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 8)

                VStack(spacing: 8) {
                    // Connected pod info
                    if deviceManager.isConnected {
                        HStack(spacing: 10) {
                            Image(systemName: "bed.double.fill")
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(podDiscovery.connectedPodName ?? podDiscovery.discoveredPods.first?.name ?? settingsManager.podIP)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text(settingsManager.podIP)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.healthy)
                        }
                        .padding(.vertical, 4)
                    }

                    // Discovered pods from scan
                    if podDiscovery.isSearching {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.accent).scaleEffect(0.7)
                            Text("Scanning network…")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                        }
                        .padding(.vertical, 4)
                    } else if !podDiscovery.discoveredPods.isEmpty {
                        ForEach(podDiscovery.discoveredPods) { pod in
                            HStack(spacing: 10) {
                                Image(systemName: "bed.double.fill")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                Text(pod.name)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Port \(pod.port)")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.vertical, 2)
                        }
                    } else if !deviceManager.isConnected {
                        Text("No Sleepypod found on network")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

}
