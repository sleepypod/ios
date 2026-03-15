import Foundation
import Observation

@MainActor
@Observable
final class DeviceManager {
    var deviceStatus: DeviceStatus?
    var isConnected = false
    var isConnecting = false
    var retryCount = 0
    var selectedSide: SideSelection = .left
    var isLinked = false
    var error: String?
    var lastUpdated: Date?

    /// Show spinner for first 3 attempts, then show failed state
    var showConnectionFailed: Bool {
        !isConnected && !isConnecting && retryCount >= 3 && hasPodIP
    }

    var hasPodIP: Bool {
        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress") else { return false }
        return !ip.isEmpty
    }

    private var api: SleepypodProtocol
    private var debounceTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var pendingUpdate: DeviceStatusUpdate?

    init(api: SleepypodProtocol) {
        self.api = api
    }

    // MARK: - Current State Helpers

    var currentSideStatus: SideStatus? {
        guard let status = deviceStatus else { return nil }
        return status.status(for: selectedSide.primarySide)
    }

    var currentOffset: Int {
        guard let status = currentSideStatus else { return 0 }
        return TemperatureConversion.tempFToOffset(status.targetTemperatureF)
    }

    var isOn: Bool {
        currentSideStatus?.isOn ?? false
    }

    var isAlarmActive: Bool {
        guard let status = deviceStatus else { return false }
        return status.left.isAlarmVibrating || status.right.isAlarmVibrating
    }

    var alarmSide: Side? {
        guard let status = deviceStatus else { return nil }
        if status.left.isAlarmVibrating { return .left }
        if status.right.isAlarmVibrating { return .right }
        return nil
    }

    // MARK: - Backend Switching

    func switchBackend(_ newClient: SleepypodProtocol) {
        stopPolling()
        api = newClient
        deviceStatus = nil
        isConnected = false
        retryCount = 0
        error = nil
        startPolling()
    }

    // MARK: - Polling

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                if pendingUpdate == nil {
                    await fetchStatus()
                }
                // Retry faster when disconnected, normal interval when connected
                let interval: Duration = isConnected ? .seconds(10) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func fetchStatus() async {
        if !isConnected && retryCount < 3 {
            isConnecting = true
        }
        do {
            let status = try await api.getDeviceStatus()
            deviceStatus = status
            isConnected = true
            isConnecting = false
            retryCount = 0
            error = nil
            lastUpdated = Date()
        } catch {
            isConnected = false
            isConnecting = false
            retryCount += 1
            self.error = "\(error)"
            Log.device.error("fetchStatus failed (attempt \(self.retryCount)): \(error)")
        }
    }

    func retryConnection() {
        retryCount = 0
        isConnecting = true
        Task { await fetchStatus() }
    }

    // MARK: - Temperature Control

    func adjustOffset(by delta: Int) {
        guard let status = currentSideStatus else { return }
        let currentOffset = TemperatureConversion.tempFToOffset(status.targetTemperatureF)
        let newOffset = max(TemperatureConversion.minOffset,
                           min(TemperatureConversion.maxOffset, currentOffset + delta))
        let newTempF = TemperatureConversion.offsetToTempF(newOffset)
        setTemperature(newTempF)
    }

    func setTemperature(_ tempF: Int) {
        let clampedTempF = max(TemperatureConversion.minTempF, min(TemperatureConversion.maxTempF, tempF))
        let sides = isLinked ? [Side.left, .right] : selectedSide.sides

        // Optimistic update
        for side in sides {
            updateLocalTemperature(clampedTempF, for: side)
        }

        // Build update
        var update = pendingUpdate ?? DeviceStatusUpdate()
        for side in sides {
            let sideUpdate = SideStatusUpdate(targetTemperatureF: clampedTempF, isOn: nil)
            switch side {
            case .left: update.left = sideUpdate
            case .right: update.right = sideUpdate
            }
        }
        pendingUpdate = update
        scheduleDebouncedSend()
    }

    // MARK: - Power Control

    func togglePower() {
        guard let status = currentSideStatus else { return }
        let newIsOn = !status.isOn
        let sides = isLinked ? [Side.left, .right] : selectedSide.sides

        // Optimistic update
        for side in sides {
            updateLocalPower(newIsOn, for: side)
        }

        // Build and send immediately (no debounce for power)
        var update = DeviceStatusUpdate()
        for side in sides {
            let sideUpdate = SideStatusUpdate(targetTemperatureF: nil, isOn: newIsOn)
            switch side {
            case .left: update.left = sideUpdate
            case .right: update.right = sideUpdate
            }
        }

        Task {
            do {
                try await api.updateDeviceStatus(update)
            } catch {
                self.error = error.localizedDescription
                await fetchStatus() // Revert on failure
            }
        }
    }

    // MARK: - Alarm

    func stopAlarm() {
        guard let side = alarmSide else { return }
        var update = DeviceStatusUpdate()
        let sideUpdate = SideStatusUpdate(targetTemperatureF: nil, isOn: false)
        switch side {
        case .left: update.left = sideUpdate
        case .right: update.right = sideUpdate
        }

        // Optimistic update
        updateLocalAlarm(false, for: side)

        Task {
            do {
                try await api.updateDeviceStatus(update)
            } catch {
                self.error = error.localizedDescription
                await fetchStatus()
            }
        }
    }

    // MARK: - Side Selection

    func selectSide(_ selection: SideSelection) {
        selectedSide = selection
    }

    func toggleLink() {
        isLinked.toggle()
        if isLinked {
            selectedSide = .both
        } else {
            // Fall back to the primary side when unlinking
            selectedSide = .left
        }
    }

    // MARK: - Private Helpers

    private func updateLocalTemperature(_ tempF: Int, for side: Side) {
        guard var status = deviceStatus else { return }
        switch side {
        case .left: status.left.targetTemperatureF = tempF
        case .right: status.right.targetTemperatureF = tempF
        }
        deviceStatus = status
    }

    private func updateLocalPower(_ isOn: Bool, for side: Side) {
        guard var status = deviceStatus else { return }
        switch side {
        case .left: status.left.isOn = isOn
        case .right: status.right.isOn = isOn
        }
        deviceStatus = status
    }

    private func updateLocalAlarm(_ isVibrating: Bool, for side: Side) {
        guard var status = deviceStatus else { return }
        switch side {
        case .left: status.left.isAlarmVibrating = isVibrating
        case .right: status.right.isAlarmVibrating = isVibrating
        }
        deviceStatus = status
    }

    private func scheduleDebouncedSend() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await sendPendingUpdate()
        }
    }

    private func sendPendingUpdate() async {
        guard let update = pendingUpdate else { return }
        pendingUpdate = nil
        do {
            try await api.updateDeviceStatus(update)
        } catch {
            self.error = error.localizedDescription
            Log.device.error("sendPendingUpdate failed: \(error)")
            await fetchStatus() // Revert on failure
        }
    }
}
