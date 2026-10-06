import SwiftUI

struct PodDiscoveryMark: View {
    var scanning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    var body: some View {
        ZStack {
            Circle().stroke(Theme.border1, lineWidth: 1).frame(width: 220, height: 220)
            Circle().stroke(Theme.border2, lineWidth: 1).frame(width: 156, height: 156)
            PodMark(size: 92, discovery: true)
            if scanning {
                Circle().trim(from: 0, to: 0.2).stroke(Theme.icon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 156, height: 156).rotationEffect(.degrees(rotating && !reduceMotion ? 360 : 0))
                    .onAppear { rotating = true }
                    .onDisappear { rotating = false }
                    .animation(reduceMotion ? nil : .linear(duration: 2).repeatForever(autoreverses: false), value: rotating)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityHidden(true)
    }
}

/// Back button, three-segment progress and `n/3`, as in 1n/1o.
struct OnboardingHeader: View {
    let step: Int
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            GlassCircleButton(title: "Back", systemImage: "chevron.left", action: onBack)
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Capsule().fill(index <= step ? Theme.text1 : Theme.border2).frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("\(step)/3").font(.mono(11, relativeTo: .caption2)).foregroundStyle(Theme.text2)
                .accessibilityLabel("Step \(step) of 3")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// Top-down bed diagram plus the name fields. Tapping a half makes it this iPhone's side.
struct BedSidesEditor: View {
    @Binding var defaultSide: Side
    @Binding var leftName: String
    @Binding var rightName: String
    var onCommit: ((Side, String) -> Void)?
    @FocusState private var focused: Side?

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                half(.left, name: leftName)
                half(.right, name: rightName)
            }
            .padding(10)
            .frame(height: 240)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border2, lineWidth: 1))

            GroupedCard {
                field(.left, text: $leftName)
                field(.right, text: $rightName)
            }
        }
        .onChange(of: focused) { previous, _ in
            guard let previous else { return }
            onCommit?(previous, (previous == .left ? leftName : rightName).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func half(_ side: Side, name: String) -> some View {
        let selected = defaultSide == side
        return Button {
            Haptics.tap()
            defaultSide = side
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(side.rawValue.uppercased())
                Spacer(minLength: 0)
                Text(name.isEmpty ? "Name" : name).font(.title2.weight(.semibold))
                    .foregroundStyle(name.isEmpty ? Theme.text3 : Theme.text1).lineLimit(1).minimumScaleFactor(0.7)
                if selected { Text("This iPhone").font(.caption).foregroundStyle(Theme.text2) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Theme.text1 : Theme.border1, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side.displayName) side, \(name.isEmpty ? "unnamed" : name)")
        .accessibilityValue(selected ? "This iPhone" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func field(_ side: Side, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Eyebrow(side.rawValue.uppercased()).frame(width: 60, alignment: .leading)
            TextField("Name", text: text)
                .font(.callout)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused, equals: side)
                .accessibilityLabel("\(side.displayName) name")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

struct WelcomeScreen: View {
    let onConnect: () -> Void
    let onDemo: () -> Void
    @Environment(PodDiscovery.self) private var discovery
    @Environment(SettingsManager.self) private var settings
    @Environment(DeviceManager.self) private var device
    @Environment(UserProfile.self) private var profile
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30
    @State private var step = Int(DebugRoute.current?.replacingOccurrences(of: "onboard", with: "") ?? "") ?? 1
    @State private var manualIP = ""
    @State private var manualExpanded = false
    @State private var resolvedAddresses: [String: String] = [:]
    @State private var resolvedModels: [String: String] = [:]
    @State private var selectedPod: PodDiscovery.DiscoveredPod?
    @State private var connecting = false
    @State private var failure: String?
    @State private var leftName = ""
    @State private var rightName = ""

    var body: some View {
        @Bindable var profile = profile
        NavigationStack {
            Group {
                if step == 1 { findPod }
                else if step == 2 { chooseSides(defaultSide: $profile.defaultSide) }
                else { HealthAccessView(onComplete: onConnect) }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                if step > 1 { OnboardingHeader(step: step) { withAnimation { step -= 1 } } }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { discovery.startBrowsing() }
        .task(id: discovery.discoveredPods.map(\.id)) {
            for pod in discovery.discoveredPods where resolvedAddresses[pod.id] == nil {
                if let address = await discovery.resolve(pod), !Task.isCancelled {
                    resolvedAddresses[pod.id] = address
                    var endpoint = URLComponents()
                    endpoint.scheme = "http"
                    endpoint.host = address
                    endpoint.port = Int(pod.port)
                    if let url = endpoint.url,
                       let status = try? await SleepypodCoreClient(discoveryURL: url).getDeviceStatus(), !Task.isCancelled {
                        resolvedModels[pod.id] = status.podModelName
                    }
                }
            }
        }
        .onDisappear { discovery.stopBrowsing() }
    }

    // MARK: 1m Find the pod

    private var title: String {
        if !discovery.discoveredPods.isEmpty { return "Found your pod" }
        return discovery.status == .failed || (!discovery.isSearching && discovery.discoveredPods.isEmpty && discovery.status != .idle)
            ? "Couldn't find a pod" : "Looking for your pod"
    }

    private var findPod: some View {
        ScrollView {
            VStack(spacing: 0) {
                PodDiscoveryMark(scanning: discovery.isSearching && discovery.discoveredPods.isEmpty)
                    .padding(.top, 78)
                VStack(spacing: 10) {
                    Text(title).font(.title.bold()).tracking(-0.4)
                    Text("Your iPhone and the pod need to be on the same Wi-Fi.")
                        .font(.subheadline).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 32)

                GroupedCard {
                    ForEach(discovery.discoveredPods) { pod in podRow(pod) }
                    Button {
                        withAnimation(.snappy) { manualExpanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "keyboard").font(.system(size: 15)).frame(width: 22)
                            Text("Enter IP manually").font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text3).rotationEffect(.degrees(manualExpanded ? 90 : 0))
                        }
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(manualExpanded ? .isSelected : [])
                    if manualExpanded {
                        TextField("192.168.1.88", text: $manualIP)
                            .font(.mono(15, relativeTo: .subheadline))
                            .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(.horizontal, 16).frame(minHeight: 52)
                            .accessibilityLabel("Pod IP address")
                            .onChange(of: manualIP) { if !manualIP.isEmpty { selectedPod = nil } }
                    }
                }
                .padding(.top, 28)
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.amber).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(connecting ? "Connecting…" : "Connect") { Task { await connect() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(connecting || (manualIP.isEmpty && discovery.discoveredPods.isEmpty))
                Button("Explore demo") {
                    discovery.stopBrowsing()
                    onDemo()
                    Task { await device.fetchStatus(); await prepareSides() }
                }
                .buttonStyle(GlassButtonStyle())
                if discovery.status == .failed && discovery.discoveredPods.isEmpty {
                    Button("Search again") { discovery.startBrowsing() }
                        .font(.callout.weight(.medium)).foregroundStyle(Theme.text2).frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
            .background(Theme.background)
        }
    }

    private func podRow(_ pod: PodDiscovery.DiscoveredPod) -> some View {
        let selected = manualIP.isEmpty && (selectedPod?.id ?? discovery.discoveredPods.first?.id) == pod.id
        return Button {
            Haptics.tap()
            selectedPod = pod
            manualIP = ""
        } label: {
            HStack(spacing: 12) {
                StatusDot(size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("sleepypod").font(.callout.weight(.semibold)).foregroundStyle(Theme.text1)
                    Text("\(resolvedAddresses[pod.id] ?? "Resolving…") · \(resolvedModels[pod.id] ?? "Pod")")
                        .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.green) }
            }
            .padding(.horizontal, 16).frame(minHeight: 64).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 1n Who sleeps where

    private func chooseSides(defaultSide: Binding<Side>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Who sleeps where?").font(.system(size: titleSize, weight: .bold)).tracking(-0.5)
                    Text("Sides as seen lying in bed. Names show up on every screen.")
                        .font(.subheadline).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .padding(.horizontal, 8)
                BedSidesEditor(defaultSide: defaultSide, leftName: $leftName, rightName: $rightName)
                    .padding(.top, 32)
                if let failure { Text(failure).font(.footnote).foregroundStyle(Theme.amber).padding(.top, 12) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") {
                Task {
                    await settings.updateSideName(.left, name: leftName.trimmingCharacters(in: .whitespacesAndNewlines))
                    await settings.updateSideName(.right, name: rightName.trimmingCharacters(in: .whitespacesAndNewlines))
                    if let error = settings.error { failure = error; return }
                    device.selectSide(profile.defaultSide == .left ? .left : .right)
                    failure = nil
                    withAnimation { step = 3 }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16).padding(.bottom, 10)
            .background(Theme.background)
        }
    }

    // MARK: Actions

    private func connect() async {
        connecting = true
        defer { connecting = false }
        if manualIP.isEmpty, let pod = selectedPod ?? discovery.discoveredPods.first {
            if let known = resolvedAddresses[pod.id] { manualIP = known } else { manualIP = await discovery.resolve(pod) ?? "" }
            selectedPod = pod
            discovery.connectedPodName = pod.name
        }
        guard !manualIP.isEmpty else { failure = "Couldn't resolve the pod's address."; return }
        discovery.stopBrowsing()
        SettingsManager.registerPodIdentity(address: manualIP, bonjourID: selectedPod?.id)
        settings.podIP = manualIP
        await device.fetchStatus()
        guard device.isConnected else { failure = "Couldn't connect. Check the address and Wi-Fi, then retry."; return }
        await prepareSides()
    }

    private func prepareSides() async {
        await settings.fetchSettings()
        guard settings.settings != nil else { failure = settings.error ?? "Couldn't load pod settings."; return }
        leftName = settings.settings?.left.name ?? ""
        rightName = settings.settings?.right.name ?? ""
        failure = nil
        withAnimation { step = 2 }
    }
}

/// Shown in a tab when the pod is unreachable: the 1m layout without the result list.
struct DisconnectedTabView: View {
    let tab: String
    var selectedTab: Binding<String>?
    @Environment(DeviceManager.self) private var device
    @Environment(SettingsManager.self) private var settings
    @Environment(PodDiscovery.self) private var discovery
    @State private var manualExpanded = false

    private var statusText: String {
        switch discovery.status {
        case .idle: "Connecting…"
        case .scanning: "Looking for your pod"
        case .found: "Found your pod"
        case .resolving(let name): "Resolving \(name)…"
        case .connected(let ip): "Connecting to \(ip)…"
        case .failed: "Couldn't find a pod"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PodDiscoveryMark(scanning: discovery.status == .scanning || discovery.status == .idle)
                    .padding(.top, 40)
                VStack(spacing: 10) {
                    Text(statusText).font(.title2.bold()).tracking(-0.3)
                    Text("Your iPhone and the pod need to be on the same Wi-Fi.")
                        .font(.subheadline).foregroundStyle(Theme.text2)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                GroupedCard {
                    Button {
                        withAnimation(.snappy) { manualExpanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "keyboard").font(.system(size: 15)).frame(width: 22)
                            Text("Enter IP manually").font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text3).rotationEffect(.degrees(manualExpanded ? 90 : 0))
                        }
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if manualExpanded {
                        HStack {
                            TextField("192.168.1.88", text: Binding(get: { settings.podIP }, set: { settings.podIP = $0 }))
                                .font(.mono(15, relativeTo: .subheadline))
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.decimalPad)
                                .accessibilityLabel("Pod IP address")
                            Button("Connect") { device.retryConnection() }
                                .font(.subheadline.weight(.semibold)).disabled(settings.podIP.isEmpty)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                    }
                }
                .padding(.top, 28)
                if discovery.status == .failed {
                    Button("Retry") { Task { _ = await discovery.autoConnect(settingsManager: settings, deviceManager: device) } }
                        .buttonStyle(GlassButtonStyle())
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }
}

struct DemoModeBanner: View {
    var body: some View {
        Text("Demo mode").font(.mono(10)).foregroundStyle(Theme.amber)
            .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.card, in: Capsule())
    }
}
