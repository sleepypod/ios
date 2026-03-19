import Foundation
import Observation
import SwiftUI

// Piezo buffer is just arrays on the @Observable service — no separate class needed.
// All access is @MainActor (append from WebSocket handler, read from view body).

// MARK: - Firmware Log Entry

struct FirmwareLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String, Sendable {
        case debug, info, warn, error
        var color: Color {
            switch self {
            case .debug: Theme.textMuted
            case .info: Theme.healthy
            case .warn: Theme.amber
            case .error: Theme.error
            }
        }
    }
}

// MARK: - Service

@MainActor
@Observable
final class SensorStreamService {
    var isConnected = false
    var error: String?
    var lastFrameTime: Date?
    var framesPerSecond: Int = 0

    var leftPresence: CapSenseSide?
    var rightPresence: CapSenseSide?
    var leftVitals = LiveVitals()
    var rightVitals = LiveVitals()
    var leftTemps: BedTempSide?
    var rightTemps: BedTempSide?
    var frzHealth: FrzHealthFrame?

    var leftVariance: [Float] = Array(repeating: 0, count: 8)
    var rightVariance: [Float] = Array(repeating: 0, count: 8)

    // Piezo waveform — plain arrays, @MainActor safe
    var piezoLeft: [Int32] = []
    var piezoRight: [Int32] = []
    private let maxPiezoSamples = 1500

    var firmwareLogs: [FirmwareLogEntry] = []
    var leftTempHistory: [(Date, Float)] = []
    var rightTempHistory: [(Date, Float)] = []

    /// Notification relay — set by app to forward pod events
    var notificationRelay: NotificationRelay?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var frameCount = 0
    private var fpsTimer: Date = .now
    private var lastCapUpdate: Date = .distantPast
    private var lastPiezoUpdate: Date = .distantPast
    private var leftHistory: [[Float]] = []
    private var rightHistory: [[Float]] = []
    private let varianceWindow = 20
    private let maxLogLines = 50
    private let maxTempHistory = 60

    /// Variance-based presence detection. An occupied side shows capSense
    /// signal variance from breathing/movement. Empty bed has near-zero variance.
    /// Threshold 0.05 stddev — below this is noise floor.
    func isOccupied(side: Side) -> Bool {
        let variance = side == .left ? leftVariance : rightVariance
        // Check active channels only (skip REF at indices 6,7)
        let maxVar = (0..<6).map { variance[safe: $0] ?? 0 }.max() ?? 0
        return maxVar > 0.05
    }

    private var podURL: URL? {
        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress"), !ip.isEmpty else { return nil }
        return URL(string: "ws://\(ip):3001")
    }

    func connect() {
        guard !isConnected else { return }
        guard let url = podURL else { error = "No pod IP"; return }
        disconnect()

        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: url)
        self.webSocketTask = ws
        ws.resume()
        error = nil

        receiveTask = Task { [weak ws] in
            guard let ws else { return }
            await self.receiveLoop(ws)
        }

        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self.webSocketTask?.sendPing { _ in }
            }
        }
    }

    func disconnect() {
        receiveTask?.cancel(); receiveTask = nil
        pingTask?.cancel(); pingTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func clearLogs() { firmwareLogs.removeAll() }

    // MARK: - Receive

    private func receiveLoop(_ ws: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await ws.receive()
                if !isConnected { isConnected = true }
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) { handleFrame(data) }
                case .data(let data):
                    handleFrame(data)
                @unknown default: break
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.isConnected = false
            self.error = "Disconnected"
            scheduleReconnect()
        }
    }

    private func handleFrame(_ data: Data) {
        guard let frame = SensorFrame.decode(from: data) else { return }

        lastFrameTime = .now
        frameCount += 1
        let elapsed = Date.now.timeIntervalSince(fpsTimer)
        if elapsed >= 1 {
            framesPerSecond = Int(Double(frameCount) / elapsed)
            frameCount = 0
            fpsTimer = .now
        }

        switch frame {
        case .capSense2(let cap):
            let now = Date.now
            guard now.timeIntervalSince(lastCapUpdate) > 0.2 else { return }
            lastCapUpdate = now
            leftPresence = cap.left
            rightPresence = cap.right
            leftHistory.append(cap.left.values)
            rightHistory.append(cap.right.values)
            if leftHistory.count > varianceWindow { leftHistory.removeFirst() }
            if rightHistory.count > varianceWindow { rightHistory.removeFirst() }
            leftVariance = computeVariance(leftHistory)
            rightVariance = computeVariance(rightHistory)

        case .piezoDual(let piezo):
            piezoLeft.append(contentsOf: piezo.left1)
            piezoRight.append(contentsOf: piezo.right1)
            if piezoLeft.count > maxPiezoSamples { piezoLeft.removeFirst(piezoLeft.count - maxPiezoSamples) }
            if piezoRight.count > maxPiezoSamples { piezoRight.removeFirst(piezoRight.count - maxPiezoSamples) }

            let now = Date.now
            guard now.timeIntervalSince(lastPiezoUpdate) > 1.0 else { return }
            lastPiezoUpdate = now
            let left = piezo.left1, right = piezo.right1, freq = piezo.freq
            Task.detached(priority: .utility) { [weak self] in
                let lv = PiezoAnalyzer.extractVitals(signal: left, sampleRate: freq)
                let rv = PiezoAnalyzer.extractVitals(signal: right, sampleRate: freq)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if lv.confidence > 0.1 { self.leftVitals = lv }
                    if rv.confidence > 0.1 { self.rightVitals = rv }
                }
            }

        case .bedTemp2(let temp):
            leftTemps = temp.left
            rightTemps = temp.right
            if let avgL = temp.left.avgSurfaceTempF {
                leftTempHistory.append((.now, Float(avgL)))
                if leftTempHistory.count > maxTempHistory { leftTempHistory.removeFirst() }
            }
            if let avgR = temp.right.avgSurfaceTempF {
                rightTempHistory.append((.now, Float(avgR)))
                if rightTempHistory.count > maxTempHistory { rightTempHistory.removeFirst() }
            }

        case .frzHealth(let frz):
            frzHealth = frz

        case .log(let log):
            let entry = FirmwareLogEntry(
                timestamp: Date(timeIntervalSince1970: Double(log.ts)),
                level: FirmwareLogEntry.LogLevel(rawValue: log.level) ?? .info,
                message: log.msg
            )
            firmwareLogs.append(entry)
            if firmwareLogs.count > maxLogLines { firmwareLogs.removeFirst() }

        case .notification(let notif):
            Task {
                await notificationRelay?.relay(
                    category: notif.category,
                    title: notif.title,
                    message: notif.message
                )
            }

        case .unknown: break
        }
    }

    private func computeVariance(_ history: [[Float]]) -> [Float] {
        guard history.count >= 2 else { return Array(repeating: 0, count: 8) }
        let n = history.map(\.count).min() ?? 0
        guard n > 0 else { return Array(repeating: 0, count: 8) }
        var result = [Float](repeating: 0, count: n)
        for ch in 0..<n {
            let vals = history.compactMap { $0[safe: ch] }
            guard vals.count >= 2 else { continue }
            let mean = vals.reduce(0, +) / Float(vals.count)
            let v = vals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(vals.count)
            result[ch] = sqrt(v)
        }
        return result
    }

    private func scheduleReconnect() {
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            connect()
        }
    }
}
