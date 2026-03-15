import SwiftUI

struct SettingsScreen: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(PodDiscovery.self) private var podDiscovery
    @FocusState private var isIPFieldFocused: Bool
    @FocusState private var isBranchFieldFocused: Bool
    @State private var selectedBackend = APIBackend.current
    @State private var selectedBranch = UserDefaults.standard.string(forKey: "podBranch") ?? "main"
    @State private var isResolving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pod connection — different layout per backend
                if selectedBackend == .freeSleep {
                    legacyPodCard
                } else {
                    podCard
                }

                // Pod discovery
                if !deviceManager.isConnected || !podDiscovery.discoveredPods.isEmpty || podDiscovery.isSearching {
                    discoveryCard
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
            // Auto-discover pods if not connected
            if !deviceManager.isConnected {
                podDiscovery.startBrowsing()
            }
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

    @State private var isRebooting = false

    private var isBusy: Bool {
        deviceManager.isConnecting || isRebooting
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.medium()
                deviceManager.retryConnection()
            } label: {
                HStack(spacing: 6) {
                    if deviceManager.isConnecting {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(deviceManager.isConnecting ? "CONNECTING" : "RECONNECT")
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
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)

            Button {
                Haptics.heavy()
                isRebooting = true
                Task {
                    await settingsManager.reboot()
                    isRebooting = false
                    deviceManager.retryConnection()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(isRebooting ? "REBOOTING…" : "REBOOT")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(isRebooting ? Theme.amber : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isRebooting ? Theme.amber.opacity(0.2) : Theme.error.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRebooting)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.5 : 1)
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

    // MARK: - Pod Discovery

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                Text("Network Discovery")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)

                Spacer()

                if podDiscovery.isSearching {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Haptics.light()
                        podDiscovery.startBrowsing()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if podDiscovery.discoveredPods.isEmpty {
                if podDiscovery.isSearching {
                    Text("Searching for pods on your network...")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                } else {
                    Text("No pods found. Make sure your pod is powered on and on the same network.")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
            } else {
                ForEach(podDiscovery.discoveredPods) { pod in
                    Button {
                        Haptics.medium()
                        connectToPod(pod)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bed.double.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.accent)
                                .frame(width: 36, height: 36)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pod.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text("Port \(pod.port)")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textMuted)
                            }

                            Spacer()

                            if isResolving {
                                ProgressView()
                                    .tint(Theme.accent)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .padding(10)
                        .background(Theme.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                }
            }
        }
        .cardStyle()
    }

    private func connectToPod(_ pod: PodDiscovery.DiscoveredPod) {
        isResolving = true
        Task {
            if let ip = await podDiscovery.resolve(pod) {
                settingsManager.podIP = ip
                deviceManager.retryConnection()
            }
            isResolving = false
        }
    }

    // MARK: - Device Info

    @State private var showSerials = false

    private func deviceInfoCard(status: DeviceStatus) -> some View {
        VStack(spacing: 0) {
            // Header — icon + name + connection badge
            HStack(spacing: 12) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep Pod")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(Theme.healthy)
                }

                Spacer()

                // Wifi signal
                if let strength = deviceManager.deviceStatus?.wifiStrength {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .font(.system(size: 11))
                        Text("\(strength)%")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(wifiColor(strength))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(wifiColor(strength).opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 14)

            Divider().background(Theme.cardBorder)

            // Info rows
            VStack(spacing: 0) {
                hardwareRow(
                    icon: "cpu",
                    label: "Firmware",
                    value: status.freeSleep.version
                )

                Divider().background(Theme.cardBorder).padding(.leading, 36)

                hardwareRow(
                    icon: "arrow.triangle.branch",
                    label: "Branch",
                    value: status.freeSleep.branch
                )

                Divider().background(Theme.cardBorder).padding(.leading, 36)

                hardwareRow(
                    icon: "drop.fill",
                    label: "Water Level",
                    value: status.waterLevel.capitalized
                )

                Divider().background(Theme.cardBorder).padding(.leading, 36)

                // Serial rows with eye toggle
                HStack {
                    Image(systemName: "barcode")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 20)

                    Text("Serials")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSerials.toggle()
                        }
                    } label: {
                        Image(systemName: showSerials ? "eye" : "eye.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)

                if showSerials {
                    VStack(spacing: 6) {
                        serialRow(label: "Cover", value: status.coverVersion)
                        serialRow(label: "Hub", value: status.hubVersion)
                    }
                    .padding(.leading, 36)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .cardStyle()
    }

    private func hardwareRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline.monospaced())
                .foregroundColor(.white)
        }
        .padding(.vertical, 10)
    }

    private func serialRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textMuted)

            Spacer()

            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(Theme.textTertiary)
        }
    }
}
