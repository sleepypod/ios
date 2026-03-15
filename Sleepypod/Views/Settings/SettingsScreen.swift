import SwiftUI

struct SettingsScreen: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(UpdateChecker.self) private var updateChecker
    @FocusState private var isIPFieldFocused: Bool
    @FocusState private var isBranchFieldFocused: Bool
    @State private var selectedBackend = APIBackend.current
    @State private var selectedBranch = UserDefaults.standard.string(forKey: "podBranch") ?? "main"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pod connection — different layout per backend
                if selectedBackend == .freeSleep {
                    legacyPodCard
                } else {
                    podCard
                }

                // Only show these when connected
                if deviceManager.isConnected {
                    if selectedBackend == .sleepypodCore {
                        UpdateCardView()
                    }

                    if settingsManager.settings != nil {
                        DeviceSettingsCardView()
                    } else if settingsManager.isLoading {
                        ProgressView()
                            .tint(Theme.accent)
                            .padding(40)
                    }

                    if let status = deviceManager.deviceStatus {
                        deviceInfoCard(status: status)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { isIPFieldFocused = false; isBranchFieldFocused = false }
        .task {
            await settingsManager.fetchSettings()
            updateChecker.runningVersion = deviceManager.deviceStatus?.freeSleep.version
            updateChecker.runningBranch = deviceManager.deviceStatus?.freeSleep.branch
            await updateChecker.checkForUpdate()
        }
    }

    // MARK: - Legacy Pod Card (Free Sleep)

    @ViewBuilder
    private var legacyPodCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Server picker (same as main card)
            serverPickerRow

            Text(selectedBackend.description)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(Theme.cardBorder)

            // Just the IP field
            ipAddressRow

            // Reboot
            actionButtons
        }
        .cardStyle()
    }

    // MARK: - Combined Pod Card (Sleepypod)

    @ViewBuilder
    private var podCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            serverPickerRow

            Text(selectedBackend.description)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Branch
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(Theme.accent)
                TextField("Branch", text: $selectedBranch)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isBranchFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isBranchFieldFocused = false
                        saveBranch()
                    }

                if isBranchFieldFocused {
                    Button {
                        Haptics.light()
                        isBranchFieldFocused = false
                        saveBranch()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.healthy)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider().background(Theme.cardBorder)

            ipAddressRow
            actionButtons
        }
        .cardStyle()
    }

    // MARK: - Shared Components

    private var serverPickerRow: some View {
        HStack {
            Text("Pod Server")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
            Spacer()
            Menu {
                ForEach(APIBackend.allCases, id: \.rawValue) { backend in
                    Button {
                        Haptics.tap()
                        selectedBackend = backend
                        APIBackend.current = backend
                        deviceManager.switchBackend(backend.createClient())
                    } label: {
                        HStack {
                            Text(backend.displayName)
                            if selectedBackend == backend {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedBackend.displayName)
                        .font(.subheadline)
                        .foregroundColor(Theme.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    private var ipAddressRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .foregroundColor(Theme.accent)

            TextField("Pod IP Address", text: Binding(
                get: { settingsManager.podIP },
                set: { settingsManager.podIP = $0.trimmingCharacters(in: .whitespaces) }
            ))
            .font(.subheadline)
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .keyboardType(.decimalPad)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isIPFieldFocused)
            .submitLabel(.done)
            .onSubmit { isIPFieldFocused = false }

            if isIPFieldFocused {
                Button {
                    Haptics.light()
                    isIPFieldFocused = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.healthy)
                }
                .buttonStyle(.plain)
            } else {
                connectionIndicator
            }
        }
        .padding(12)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.medium()
                deviceManager.retryConnection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("RECONNECT")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.heavy()
                Task { await settingsManager.reboot() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("REBOOT")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.error.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        let connected = deviceManager.isConnected

        if deviceManager.isConnecting {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(0.7)
        } else if connected {
            let strength = deviceManager.deviceStatus?.wifiStrength ?? 0
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundColor(wifiColor(strength))
                Text("\(strength)%")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(wifiColor(strength))
            }
        } else {
            Circle()
                .fill(Theme.error)
                .frame(width: 8, height: 8)
        }
    }

    private func wifiColor(_ strength: Int) -> Color {
        if strength >= 50 { return Theme.healthy }
        if strength >= 25 { return Theme.amber }
        return Theme.error
    }

    private func saveBranch() {
        let trimmed = selectedBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedBranch = trimmed
        UserDefaults.standard.set(trimmed, forKey: "podBranch")
        updateChecker.trackingBranch = trimmed
    }

    // MARK: - Device Info

    private func deviceInfoCard(status: DeviceStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Info")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                infoTag("Cover: \(status.coverVersion)")
                infoTag("Hub: \(status.hubVersion)")
            }
        }
        .cardStyle()
    }

    private func infoTag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "2a2a3a"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
