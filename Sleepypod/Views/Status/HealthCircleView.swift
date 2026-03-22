import SwiftUI

struct HealthCircleView: View {
    @Environment(StatusManager.self) private var statusManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var showSerials = false
    @State private var showInternetSheet = false
    @State private var showWaterSheet = false
    @State private var diskUsage: DiskUsage?
    @State private var version: SystemVersion?

    private var progress: Double { statusManager.healthProgress }
    private var status: DeviceStatus? { deviceManager.deviceStatus }

    private var isInternetBlocked: Bool {
        statusManager.isInternetBlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — health ring + name + model chip
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "222222"), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progress == 1.0 ? Theme.healthy : Theme.amber,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: progress)
                    Text("\(statusManager.healthyCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Title row: "Sleepypod" + Pod model chip
                    HStack(spacing: 8) {
                        Text("sleepypod")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        if let status {
                            Text(podModelName(status.hubVersion))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text("\(statusManager.healthyCount) of \(statusManager.totalCount) services healthy")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()
            }

            if let status {
                // Connection row: IP + internet status
                Divider().background(Theme.cardBorder).padding(.vertical, 10)

                HStack(spacing: 8) {
                    if deviceManager.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Theme.healthy)
                        Text(settingsManager.podIP)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    // Wifi signal
                    HStack(spacing: 3) {
                        Image(systemName: "wifi")
                            .font(.system(size: 10))
                        Text("\(deviceManager.deviceStatus?.wifiStrength ?? 0)%")
                            .font(.caption2)
                    }
                    .foregroundColor(wifiColor(deviceManager.deviceStatus?.wifiStrength ?? 0))

                    Text("·")
                        .foregroundColor(Theme.textMuted)

                    // Internet — tappable
                    Button {
                        Haptics.light()
                        showInternetSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isInternetBlocked ? "lock.shield.fill" : "globe")
                                .font(.system(size: 10))
                            Text(isInternetBlocked ? "Local only" : "Internet")
                                .font(.caption2)
                        }
                        .foregroundColor(isInternetBlocked ? Theme.healthy : Theme.amber)
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(Theme.cardBorder).padding(.vertical, 10)

                // Stats row: water + branch/version chip
                HStack(spacing: 0) {
                    // Water level — tappable
                    Button {
                        Haptics.light()
                        showWaterSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            if status.isPriming {
                                PrimingIndicator()
                            } else {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(waterColor(status.waterLevel))
                                Text(waterLabel(status.waterLevel))
                                    .font(.caption2)
                                    .foregroundColor(waterColor(status.waterLevel))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Branch/version chip
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(version?.branch ?? status.freeSleep.branch)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        if let v = version {
                            Text(v.shortHash)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "222222"))
                    .clipShape(Capsule())
                }

                // Disk usage
                if let disk = diskUsage {
                    Divider().background(Theme.cardBorder).padding(.vertical, 10)

                    VStack(spacing: 4) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 10))
                                Text("\(disk.usedGB) / \(disk.totalGB) GB")
                                    .font(.caption2)
                            }
                            .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(Int(disk.usedPercent))%")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(disk.usedPercent > 90 ? Theme.error : disk.usedPercent > 75 ? Theme.amber : Theme.textMuted)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: "222222"))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(disk.usedPercent > 90 ? Theme.error : disk.usedPercent > 75 ? Theme.amber : Theme.accent)
                                    .frame(width: geo.size.width * disk.usedPercent / 100, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Serials (collapsible)
                Divider().background(Theme.cardBorder).padding(.vertical, 10)

                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { showSerials.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "barcode")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                        Text("Serials")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                        Image(systemName: showSerials ? "eye" : "eye.slash")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                if showSerials {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cover: \(status.coverVersion)")
                            Text("Hub: \(status.hubVersion)")
                        }
                        .font(.caption2.monospaced())
                        .foregroundColor(Theme.textMuted)
                        Spacer()
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .cardStyle()
        .task {
            let api = APIBackend.current.createClient()
            diskUsage = try? await api.getDiskUsage()
            version = try? await api.getVersion()
        }
        .sheet(isPresented: $showWaterSheet) {
            WaterLevelSheet(currentLevel: status?.waterLevel ?? "unknown")
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInternetSheet) {
            InternetAccessSheet(isBlocked: isInternetBlocked)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func podModelName(_ version: String) -> String {
        switch version.uppercased() {
        case "H00": "Pod 5"
        case "H01": "Pod 4"
        case "H02": "Pod 3"
        case "H03": "Pod 2"
        default: version
        }
    }

    private func wifiColor(_ strength: Int) -> Color {
        if strength >= 50 { return Theme.healthy }
        if strength >= 25 { return Theme.amber }
        return Theme.error
    }

    private func waterLabel(_ level: String) -> String {
        switch level.lowercased() {
        case "true", "ok", "full", "good": "Water OK"
        case "false", "low", "empty": "Water Low"
        default: "Water: \(level)"
        }
    }

    private func waterColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "true", "ok", "full", "good": Theme.healthy
        case "false", "low", "empty": Theme.amber
        default: Theme.textSecondary
        }
    }
}

// MARK: - Internet Access Sheet

private struct InternetAccessSheet: View {
    let isBlocked: Bool
    @Environment(StatusManager.self) private var statusManager
    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: isBlocked ? "lock.shield.fill" : "globe")
                    .font(.system(size: 48))
                    .foregroundColor(isBlocked ? Theme.healthy : Theme.amber)
                    .padding(.top, 16)

                // Status
                VStack(spacing: 6) {
                    Text(isBlocked ? "Local Network Only" : "Internet Access Enabled")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                    Text(isBlocked
                         ? "Your Sleepypod can only communicate on your local network. It cannot phone home or reach external servers."
                         : "Your Sleepypod can access the internet. This allows external connections and potential data transmission.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                // Buttons
                VStack(spacing: 20) {
                    Button {
                        Haptics.medium()
                        isUpdating = true
                        Task {
                            await statusManager.setInternetAccess(blocked: !isBlocked)
                            isUpdating = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isUpdating {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: isBlocked ? "globe" : "lock.shield.fill")
                            }
                            Text(isBlocked ? "Allow Internet Access" : "Block Internet Access")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isBlocked ? Theme.amber : Theme.healthy)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)

                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(Theme.background)
        }
    }
}
