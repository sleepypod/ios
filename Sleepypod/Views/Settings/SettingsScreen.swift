import SwiftUI

struct SettingsScreen: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DeviceManager.self) private var deviceManager
    @FocusState private var isIPFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pod IP configuration
                podIPCard

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

                // Update card
                if let status = deviceManager.deviceStatus {
                    UpdateCardView(freeSleep: status.freeSleep)
                }

                // Actions
                actionsCard
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
                    set: { settingsManager.podIP = $0 }
                ))
                .font(.subheadline)
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isIPFieldFocused)
                .submitLabel(.done)
                .onSubmit { isIPFieldFocused = false }

                // Connection status
                Circle()
                    .fill(deviceManager.isConnected ? Theme.healthy : Theme.error)
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Enter the IP address of your pod (e.g., 192.168.1.88)")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .cardStyle()
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

    // MARK: - Actions

    private var actionsCard: some View {
        HStack(spacing: 12) {
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

            HStack(spacing: 6) {
                Image(systemName: "wifi")
                Text("\(deviceManager.deviceStatus?.wifiStrength ?? 0)%")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cooling)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .cardStyle()
    }
}
