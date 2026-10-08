import SwiftUI

struct HealthCircleView: View {
    @Environment(StatusManager.self) private var statusManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var showSerials = false
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
                        .stroke(Theme.track, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progress == 1.0 ? Theme.healthy : Theme.amber,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: progress)
                    Text("\(statusManager.healthyCount)")
                        .font(.mono(14, weight: .bold))
                        .foregroundColor(Theme.text1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Title row: "Sleepypod" + Pod model chip
                    HStack(spacing: 8) {
                        Text("sleepypod")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.text1)

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

                    Label(isInternetBlocked ? "Local only" : "Internet", systemImage: isInternetBlocked ? "lock.shield.fill" : "globe")
                        .font(.caption2).foregroundStyle(Theme.text2)
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
                            .font(.mono(10, weight: .medium))
                        if let v = version {
                            Text(v.shortHash)
                                .font(.mono(9))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.active)
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
                                    .fill(Theme.track)
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
                        .font(.mono(11))
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

    }

    private func podModelName(_ version: String) -> String {
        // Matches sleepypod-core src/hardware/pods.ts POD_CAPS.
        switch version.uppercased() {
        case "H00": "Pod 3"
        case "I00": "Pod 4"
        case "J00": "Pod 5"
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
