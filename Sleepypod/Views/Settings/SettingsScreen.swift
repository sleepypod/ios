import SwiftUI

struct SettingsScreen: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DeviceManager.self) private var deviceManager
    @FocusState private var isIPFieldFocused: Bool
    @State private var selectedBackend = APIBackend.current

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Backend selector
                backendCard

                // Pod IP + reboot
                podIPCard

                // Update card (right under connection)
                UpdateCardView(
                    currentVersion: deviceManager.deviceStatus?.freeSleep.version ?? "1.0.0",
                    currentBranch: deviceManager.deviceStatus?.freeSleep.branch ?? "main"
                )

                // Device settings
                if settingsManager.settings != nil {
                    DeviceSettingsCardView()
                } else if settingsManager.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                }

                // Device info
                if let status = deviceManager.deviceStatus {
                    deviceInfoCard(status: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { isIPFieldFocused = false }
        .task {
            await settingsManager.fetchSettings()
        }
    }

    // MARK: - Backend Selector

    @ViewBuilder
    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Text(selectedBackend.description)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    // MARK: - Pod IP Card

    @ViewBuilder
    private var podIPCard: some View {
        @Bindable var manager = settingsManager
        VStack(alignment: .leading, spacing: 12) {
            Text("Pod Connection")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)

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

                // Done / WiFi indicator
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
                    wifiIndicator
                }
            }
            .padding(12)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Enter the IP address of your pod (e.g., 192.168.1.88)")
                .font(.caption)
                .foregroundColor(Theme.textMuted)

            // Reboot button right below IP
            Button {
                Haptics.heavy()
                Task { await settingsManager.reboot() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("REBOOT POD")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.cooling)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var wifiIndicator: some View {
        let strength = deviceManager.deviceStatus?.wifiStrength ?? 0
        let connected = deviceManager.isConnected

        if connected {
            HStack(spacing: 4) {
                Image(systemName: wifiIcon(strength))
                    .font(.system(size: 12))
                    .foregroundColor(wifiColor(strength))
                Text("\(strength)%")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(wifiColor(strength))
            }
        } else {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12))
                .foregroundColor(Theme.error)
        }
    }

    private func wifiIcon(_ strength: Int) -> String {
        if strength >= 60 { return "wifi" }
        if strength >= 30 { return "wifi" }
        return "wifi.weak"
    }

    private func wifiColor(_ strength: Int) -> Color {
        if strength >= 50 { return Theme.healthy }
        if strength >= 25 { return Theme.amber }
        return Theme.error
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
