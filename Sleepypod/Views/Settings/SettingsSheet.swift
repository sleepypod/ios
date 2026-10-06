import SwiftUI

/// The gear sheet (1l): quick actions and the most-used rows over the current tab.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    @Environment(StatusManager.self) private var status
    @Environment(HealthSyncService.self) private var health
    @State private var showAllSettings = DebugRoute.current == "allsettings"
    @State private var confirmPrime = false
    @State private var primeError: String?

    private var podName: String { device.deviceStatus?.podModelName ?? "Pod" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text(podName).font(.title3.bold())
                        if APIBackend.current.isDemo { Eyebrow("DEMO", color: Theme.amber) }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text1)
                                .frame(width: 36, height: 36)
                                .background(GlassFill.selected(scheme), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    .padding(.horizontal, 4)
                    HStack(spacing: 10) {
                        quick("Link sides", icon: "link", active: device.isLinked) { device.toggleLink() }
                        quick("Away", icon: "airplane", active: away) {
                            Task { await settings.toggleAwayMode(device.selectedSide.primarySide) }
                        }
                        quick("Prime", icon: "drop", active: device.deviceStatus?.isPriming == true) { confirmPrime = true }
                    }
                    GroupedCard(glass: true) {
                        NavigationLink { StatusScreen().navigationTitle("Status") } label: {
                            SettingsRow("Status", icon: "waveform.path.ecg", iconColor: Theme.text1, chevron: true) {
                                RowValue(status.totalCount > 0 ? "\(status.healthyCount)/\(status.totalCount)" : "—", mono: true,
                                         color: status.totalCount == 0 ? Theme.text2 : status.healthyCount == status.totalCount ? Theme.green : Theme.amber)
                            }
                        }
                        NavigationLink { BedSensorScreen().navigationTitle("Sensors") } label: {
                            SettingsRow("Sensors", icon: "waveform", iconColor: Theme.text1, chevron: true)
                        }
                        NavigationLink { HealthAccessView() } label: {
                            SettingsRow("Apple Health", icon: "heart", iconColor: Theme.red, chevron: true) {
                                RowValue(health.enabled ? "On" : "Off")
                            }
                        }
                        Button { showAllSettings = true } label: {
                            SettingsRow("All settings", icon: "gearshape", iconColor: Theme.text1, chevron: true)
                        }
                    }
                    .buttonStyle(.plain)
                    if let primeError { Text(primeError).font(.footnote).foregroundStyle(Theme.red) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Start priming?", isPresented: $confirmPrime, titleVisibility: .visible) {
                Button("Start priming") {
                    Task {
                        do { try await APIBackend.current.createClient().startPriming(); await device.fetchStatus() }
                        catch { primeError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Water will circulate through the pod to remove trapped air.") }
            .task { await settings.fetchSettings(); await status.fetchAll() }
        }
        .tint(Theme.text1)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(SettingsSheetBackground())
        .fullScreenCover(isPresented: $showAllSettings) {
            NavigationStack {
                AllSettingsScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showAllSettings = false } label: { Text("Done").fontWeight(.semibold) }
                        }
                    }
            }
        }
    }

    private var away: Bool {
        device.selectedSide.primarySide == .left ? settings.settings?.left.awayMode ?? false : settings.settings?.right.awayMode ?? false
    }

    private func quick(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Spacer(minLength: 8)
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .foregroundStyle(active ? Theme.background : Theme.text1)
            .background(active ? Theme.text1 : GlassFill.selected(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Full settings (1j), pushed from "All settings".
struct AllSettingsScreen: View {
    @Environment(UserProfile.self) private var profile
    @Environment(SettingsManager.self) private var settings
    @Environment(DeviceManager.self) private var device
    @Environment(StatusManager.self) private var status
    @Environment(UpdateChecker.self) private var updates
    @Environment(HealthSyncService.self) private var health
    @State private var showWater = false

    private var allHealthy: Bool { status.totalCount > 0 && status.healthyCount == status.totalCount }

    var body: some View {
        @Bindable var profile = profile
        ScrollView {
            VStack(spacing: 22) {
                NavigationLink { StatusScreen().navigationTitle("Status") } label: { podHeader }
                    .buttonStyle(.plain)

                GroupedSection("BED") {
                    GroupedCard {
                        NavigationLink { SidesSettingsView() } label: {
                            SettingsRow("Sides", icon: "person.2", tile: true, chevron: true) {
                                RowValue("\(settings.leftName) · \(settings.rightName)")
                            }
                        }
                        NavigationLink {
                            ScrollView { TapGestureConfigView().padding(16) }
                                .background(Theme.background).navigationTitle("Tap gestures")
                        } label: { SettingsRow("Tap gestures", icon: "hand.tap", tile: true, chevron: true) }
                        Menu {
                            Picker("Units", selection: Binding(get: { settings.temperatureFormat }, set: { format in
                                Task { await settings.updateTemperatureFormat(format) }
                            })) {
                                Text("Fahrenheit (°F)").tag(TemperatureFormat.fahrenheit)
                                Text("Celsius (°C)").tag(TemperatureFormat.celsius)
                                Text("Relative (±)").tag(TemperatureFormat.relative)
                            }
                        } label: {
                            SettingsRow("Units", icon: "thermometer.medium", tile: true) { menuValue(unitLabel) }
                        }
                    }
                }

                GroupedSection("HEALTH") {
                    GroupedCard {
                        NavigationLink { HealthAccessView() } label: {
                            SettingsRow("Apple Health", icon: "heart", iconColor: Theme.red, tile: true, chevron: true) {
                                RowValue(health.enabled ? "On" : "Off")
                            }
                        }
                        NavigationLink { AnalysisInventoryView() } label: {
                            SettingsRow("On-device analysis", icon: "cpu", tile: true, chevron: true)
                        }
                    }
                }

                GroupedSection("POD") {
                    GroupedCard {
                        NavigationLink { StatusScreen().navigationTitle("Status") } label: {
                            SettingsRow("Status", icon: "waveform.path.ecg", tile: true, chevron: true)
                        }
                        NavigationLink { BedSensorScreen().navigationTitle("Sensors") } label: {
                            SettingsRow("Sensors", icon: "waveform", tile: true, chevron: true)
                        }
                        Button { showWater = true } label: {
                            SettingsRow("Water & priming", icon: "drop", tile: true, chevron: true)
                        }
                        NavigationLink {
                            ScrollView { UpdateCardView().padding(16) }.background(Theme.background).navigationTitle("Updates")
                        } label: {
                            SettingsRow("Updates", icon: "arrow.down.circle", tile: true, chevron: true) {
                                if updates.updateAvailable {
                                    Text("1").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                        .frame(minWidth: 22, minHeight: 22).background(Theme.red, in: Capsule())
                                        .accessibilityLabel("Update available")
                                }
                            }
                        }
                    }
                }

                GroupedSection("APP") {
                    GroupedCard {
                        Menu {
                            Picker("Appearance", selection: $profile.appearance) {
                                ForEach(UserProfile.Appearance.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            SettingsRow("Appearance", icon: "circle.lefthalf.filled", tile: true) { menuValue(profile.appearance.rawValue) }
                        }
                        SettingsRow("Developer", icon: "chevron.left.forwardslash.chevron.right", tile: true) {
                            Toggle("Developer", isOn: $profile.developer).labelsHidden()
                        }
                    }
                }

                if profile.developer {
                    GroupedSection("DEVELOPER") {
                        GroupedCard {
                            NavigationLink { LogsView() } label: { SettingsRow("Logs", icon: "doc.text", tile: true, chevron: true) }
                            NavigationLink { DataPipelineView() } label: {
                                SettingsRow("Data pipeline", icon: "point.3.connected.trianglepath.dotted", tile: true, chevron: true)
                            }
                            NavigationLink { HapticsTestView() } label: {
                                SettingsRow("Haptics test", icon: "iphone.radiowaves.left.and.right", tile: true, chevron: true)
                            }
                            SettingsRow("Internet access", icon: "globe", tile: true) {
                                Toggle("Internet access", isOn: Binding(get: { !status.isInternetBlocked }, set: { enabled in
                                    Task { await status.setInternetAccess(blocked: !enabled) }
                                })).labelsHidden()
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .tint(Theme.green)
        .background(Theme.background)
        .navigationTitle("Settings")
        .task { await status.fetchAll() }
        .sheet(isPresented: $showWater) { WaterLevelSheet(currentLevel: device.deviceStatus?.waterLevel ?? "Unknown") }
    }

    private var podHeader: some View {
        HStack(spacing: 14) {
            PodMark()
            VStack(alignment: .leading, spacing: 3) {
                Text(device.deviceStatus?.podModelName ?? "Pod").font(.headline).foregroundStyle(Theme.text1)
                HStack(spacing: 6) {
                    StatusDot(color: allHealthy ? Theme.green : Theme.amber)
                    Text(podSubtitle).font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .cardSurface()
        .contentShape(Rectangle())
    }

    private var podSubtitle: String {
        let address = APIBackend.current.isDemo ? "demo" : settings.podIP.isEmpty ? "—" : settings.podIP
        return status.totalCount > 0 ? "\(address) · \(status.healthyCount)/\(status.totalCount)" : address
    }

    private var unitLabel: String {
        switch settings.temperatureFormat {
        case .fahrenheit: "°F"
        case .celsius: "°C"
        case .relative: "±"
        }
    }

    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 4) {
            RowValue(text)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
        }
    }
}

struct SidesSettingsView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(SettingsManager.self) private var settings
    @State private var leftName = ""
    @State private var rightName = ""

    var body: some View {
        @Bindable var profile = profile
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Sides as seen lying in bed. Tap a side to make it this iPhone's default.")
                    .font(.subheadline).foregroundStyle(Theme.text2)
                BedSidesEditor(defaultSide: $profile.defaultSide, leftName: $leftName, rightName: $rightName) { side, name in
                    Task { await settings.updateSideName(side, name: name) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Sides")
        .onAppear {
            leftName = settings.settings?.left.name ?? ""
            rightName = settings.settings?.right.name ?? ""
        }
    }
}

struct AnalysisInventoryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupedSection("ON THIS iPHONE") {
                    GroupedCard {
                        SettingsRow("Stage model", icon: "cpu", tile: true) { RowValue("rule-based", mono: true) }
                        SettingsRow("Runs", icon: "iphone", tile: true) { RowValue("On device") }
                    }
                }
                Text("Sleep stages are estimated on this iPhone from the pod's vitals and movement. No trained Core ML stage model is installed yet.")
                    .font(.footnote).foregroundStyle(Theme.text2).padding(.horizontal, 16)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("On-device analysis")
    }
}

private struct SettingsSheetBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.presentationBackground(Theme.card) }
        else { content }
    }
}
