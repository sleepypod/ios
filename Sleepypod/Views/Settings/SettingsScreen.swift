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

    @State private var showManualIP = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Unified connection card
                connectionCard

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
            if !deviceManager.isConnected {
                podDiscovery.startBrowsing()
            }
        }
    }

    // MARK: - Unified Connection Card

    @State private var isRebooting = false

    private var isBusy: Bool {
        deviceManager.isConnecting || isRebooting
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Connection status header
            HStack(spacing: 12) {
                Image(systemName: deviceManager.isConnected ? "wifi" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16))
                    .foregroundColor(deviceManager.isConnected ? Theme.healthy : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background((deviceManager.isConnected ? Theme.healthy : Theme.accent).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    if deviceManager.isConnected {
                        Text("Connected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(settingsManager.podIP)
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        // Show discovery status or disconnected state
                        switch podDiscovery.status {
                        case .scanning:
                            Text("Searching…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Looking for Sleepypod on your network")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        case .found(let name):
                            Text("Found \(name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Tap Connect to use this Sleepypod")
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                        case .resolving(let name):
                            Text("Connecting to \(name)…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Resolving address")
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                        default:
                            if deviceManager.isConnecting {
                                Text("Connecting…")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(settingsManager.podIP)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            } else {
                                Text("Disconnected")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(settingsManager.podIP.isEmpty ? "No Sleepypod configured" : "Could not reach \(settingsManager.podIP)")
                                    .font(.caption)
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                    }
                }

                Spacer()

                // Server picker
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
                    Text(selectedBackend.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "222222"))
                        .clipShape(Capsule())
                }
            }

            // Discovered pods (when not connected or pods visible)
            if !deviceManager.isConnected {
                if !podDiscovery.discoveredPods.isEmpty {
                    ForEach(podDiscovery.discoveredPods) { pod in
                        Button {
                            Haptics.medium()
                            connectToPod(pod)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bed.double.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.accent)
                                Text(pod.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Spacer()
                                if isResolving {
                                    ProgressView().tint(Theme.accent).scaleEffect(0.7)
                                } else {
                                    Text("Connect")
                                        .font(.caption.weight(.semibold))
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
                } else if podDiscovery.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent).scaleEffect(0.7)
                        Text("Scanning network…")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }

            // Branch (sleepypod-core only)
            if selectedBackend == .sleepypodCore {
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
            }

            // Manual IP override (collapsed by default)
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showManualIP.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.caption)
                    Text(showManualIP ? "Hide Manual IP" : "Manual IP Override")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(showManualIP ? 90 : 0))
                }
                .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)

            if showManualIP {
                HStack(spacing: 12) {
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
                    }
                }
                .padding(12)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Theme.cardBorder)

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    if !deviceManager.isConnected && settingsManager.podIP.isEmpty {
                        podDiscovery.startBrowsing()
                    } else {
                        deviceManager.retryConnection()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if deviceManager.isConnecting {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: !deviceManager.isConnected && settingsManager.podIP.isEmpty
                                  ? "antenna.radiowaves.left.and.right" : "arrow.triangle.2.circlepath")
                        }
                        Text(deviceManager.isConnecting ? "CONNECTING" :
                                !deviceManager.isConnected && settingsManager.podIP.isEmpty ? "SCAN" : "RECONNECT")
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

                if deviceManager.isConnected {
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
        }
        .cardStyle()
    }

    private func connectToPod(_ pod: PodDiscovery.DiscoveredPod) {
        isResolving = true
        Task {
            if let ip = await podDiscovery.resolve(pod) {
                podDiscovery.connectedPodName = pod.name
                settingsManager.podIP = ip
                deviceManager.retryConnection()
            }
            isResolving = false
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
                    Text("Sleepypod")
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
