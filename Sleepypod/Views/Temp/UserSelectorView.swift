import SwiftUI

struct UserSelectorView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.light()
            showSheet = true
        } label: {
            Text(profile.initial)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            ProfileAndSettingsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Combined Profile + Settings Sheet

private struct ProfileAndSettingsSheet: View {
    @Environment(UserProfile.self) private var profile
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(PodDiscovery.self) private var podDiscovery
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    private var isDemo: Bool {
        APIBackend.current.isDemo
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Demo mode card
                    if isDemo {
                        demoModeCard
                    }

                    // Profile section
                    profileSection

                    // Connection
                    if deviceManager.isConnected && !isDemo {
                        connectionSection
                    }

                    // Device settings
                    if settingsManager.settings != nil {
                        DeviceSettingsCardView()
                        TapGestureConfigView()
                    }

                    // Haptics test
                    if deviceManager.isConnected || isDemo {
                        NavigationLink {
                            HapticsTestView()
                        } label: {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(Theme.accent)
                                Text("Haptics & Vibration")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .cardStyle()
                    }

                    // Update
                    if deviceManager.isConnected && !isDemo {
                        UpdateCardView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .task {
                await settingsManager.fetchSettings()
            }
        }
    }

    // MARK: - Demo Mode

    private var demoModeCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo Mode")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("You are exploring with simulated data.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }

            Button {
                Haptics.medium()
                exitDemoMode()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Connect to Real Pod")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func exitDemoMode() {
        APIBackend.current = .sleepypodCore
        let client = APIBackend.sleepypodCore.createClient()
        deviceManager.switchBackend(client)
        dismiss()
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(spacing: 16) {
            // Avatar
            Text(profile.initial)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Theme.accent.opacity(0.3))
                .clipShape(Circle())

            // Name
            @Bindable var profile = profile
            TextField("Your name", text: $profile.name)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($isNameFocused)
                .padding(12)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 200)

            // Side picker
            HStack(spacing: 0) {
                sideButton(.left)
                sideButton(.right)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func sideButton(_ side: Side) -> some View {
        let isSelected = profile.defaultSide == side
        return Button {
            Haptics.tap()
            profile.defaultSide = side
            deviceManager.selectSide(side == .left ? .left : .right)
        } label: {
            Text(side.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Theme.cooling : Theme.cardElevated)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.healthy)
                Text(settingsManager.podIP)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                if let name = podDiscovery.connectedPodName {
                    Text(name)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    deviceManager.retryConnection()
                } label: {
                    Text("Reconnect")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.heavy()
                    Task { await settingsManager.reboot() }
                } label: {
                    Text("Reboot")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.error.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }
}
