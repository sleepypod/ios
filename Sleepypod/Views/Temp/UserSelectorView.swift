import SwiftUI

struct UserSelectorView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.light()
            showSheet = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.card)
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

                    // Connection
                    if deviceManager.isConnected && !isDemo {
                        connectionSection
                    }

                    // Device settings
                    if settingsManager.settings != nil {
                        DeviceSettingsCardView()

                        SidesCardView()

                        // Tap Gestures (already applies .cardStyle() internally)
                        TapGestureConfigView()

                        // Haptics & Vibration
                        if deviceManager.isConnected || isDemo {
                            NavigationLink {
                                HapticsTestView()
                            } label: {
                                HStack {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.accent)
                                        .frame(width: 24)
                                    Text("Haptics & Vibration")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Theme.textMuted)
                                }
                                .frame(minHeight: 44)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            .cardStyle()
                        }
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
        // Clear stale demo data before switching backend
        deviceManager.deviceStatus = nil
        APIBackend.current = .sleepypodCore
        let client = APIBackend.sleepypodCore.createClient()
        deviceManager.switchBackend(client)
        dismiss()
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.healthy)
                Text("sleepypod")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                Text(settingsManager.podIP)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            if let name = podDiscovery.connectedPodName {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
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

// MARK: - Side Name Text Field

/// A text field that manages its own state from an initial value and saves on submit/blur.
struct SideNameTextField: View {
    let placeholder: String
    let initialValue: String
    let onCommit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.subheadline)
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { text = initialValue }
            .onChange(of: initialValue) { _, newVal in text = newVal }
            .onSubmit { commitIfChanged() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commitIfChanged() }
            }
    }

    private func commitIfChanged() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != initialValue {
            onCommit(trimmed)
        }
    }
}
