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

// MARK: - Raw Frame Entry

struct RawFrameEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let type: String
    let json: String
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

    // Pipeline metrics — per-type frame counts and raw frame buffer
    var frameCounts: [String: Int] = [:]
    var recentFrames: [RawFrameEntry] = []
    private let maxRecentFrames = 200

    /// Latest gesture event from WebSocket
    var lastGesture: GestureFrame?

    /// Latest device status frame from WebSocket (replaces HTTP polling)
    var latestDeviceStatus: DeviceStatusFrame?

    /// Notification relay — set by app to forward pod events
    var notificationRelay: NotificationRelay?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
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
        // Demo mode — generate fake sensor data instead of connecting WS
        if APIBackend.current.isDemo {
            guard demoTask == nil else { return }
            startDemoStream()
            return
        }

        guard !isConnected else { return
        }

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
        demoTask?.cancel(); demoTask = nil
        receiveTask?.cancel(); receiveTask = nil
        pingTask?.cancel(); pingTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        latestDeviceStatus = nil
    }

    func clearLogs() { firmwareLogs.removeAll() }

    // MARK: - Demo Stream

    func startDemoStream() {
        guard demoTask == nil else { return }
        isConnected = true
        error = nil
        frameCount = 0
        fpsTimer = .now

        var tick = 0
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                tick += 1

                // --- FPS bookkeeping ---
                self.lastFrameTime = .now
                self.frameCount += 1
                let elapsed = Date.now.timeIntervalSince(self.fpsTimer)
                if elapsed >= 1 {
                    self.framesPerSecond = Int(Double(self.frameCount) / elapsed)
                    self.frameCount = 0
                    self.fpsTimer = .now
                }


                // --- CapSense (every tick = 0.5s) ---
                let baseValues: [Float] = [15, 16, 14, 15, 12, 13, 3, 3]
                let variation: Float = Float.random(in: -1...1)
                let leftCap = CapSenseSide(
                    values: baseValues.map { $0 + variation + Float.random(in: -0.5...0.5) },
                    status: "good"
                )
                let rightCap = CapSenseSide(
                    values: baseValues.map { $0 * 0.9 + variation + Float.random(in: -0.3...0.3) },
                    status: "good"
                )
                self.leftPresence = leftCap
                self.rightPresence = rightCap
                self.leftHistory.append(leftCap.values)
                self.rightHistory.append(rightCap.values)
                if self.leftHistory.count > self.varianceWindow { self.leftHistory.removeFirst() }
                if self.rightHistory.count > self.varianceWindow { self.rightHistory.removeFirst() }
                self.leftVariance = self.computeVariance(self.leftHistory)
                self.rightVariance = self.computeVariance(self.rightHistory)
                self.trackDemoFrame("capSense2")

                // --- Piezo (every 2 ticks = 1s) ---
                if tick % 2 == 0 {
                    let freq = 500
                    var left: [Int32] = []
                    var right: [Int32] = []
                    let phase = Double(tick) * 0.5 // seconds elapsed
                    for i in 0..<freq {
                        let t = Double(i) / Double(freq)
                        let breath = sin(2 * .pi * 0.25 * (t + phase)) * 5000
                        let heart = sin(2 * .pi * 1.0 * (t + phase)) * 2000
                        let noise = Double.random(in: -500...500)
                        left.append(Int32(breath + heart + noise))
                        right.append(Int32(breath + heart * 0.8 + noise))
                    }
                    self.piezoLeft.append(contentsOf: left)
                    self.piezoRight.append(contentsOf: right)
                    if self.piezoLeft.count > self.maxPiezoSamples {
                        self.piezoLeft.removeFirst(self.piezoLeft.count - self.maxPiezoSamples)
                    }
                    if self.piezoRight.count > self.maxPiezoSamples {
                        self.piezoRight.removeFirst(self.piezoRight.count - self.maxPiezoSamples)
                    }

                    // Simulate vitals from piezo
                    self.leftVitals = LiveVitals(
                        heartRate: 62 + Double.random(in: -2...2),
                        breathingRate: 15 + Double.random(in: -1...1),
                        confidence: 0.85 + Double.random(in: -0.05...0.05)
                    )
                    self.rightVitals = LiveVitals(
                        heartRate: 58 + Double.random(in: -2...2),
                        breathingRate: 14 + Double.random(in: -1...1),
                        confidence: 0.80 + Double.random(in: -0.05...0.05)
                    )
                    self.trackDemoFrame("piezo-dual")
                }

                // --- DeviceStatus (every 4 ticks = 2s) ---
                if tick % 4 == 0 {
                    self.latestDeviceStatus = DeviceStatusFrame(
                        ts: Int(Date().timeIntervalSince1970),
                        leftSide: DeviceStatusFrame.WsSideStatus(
                            currentTemperature: 72 + Double.random(in: -0.5...0.5),
                            targetTemperature: 70,
                            currentLevel: -2,
                            targetLevel: -2,
                            heatingDuration: 0,
                            isAlarmVibrating: false
                        ),
                        rightSide: DeviceStatusFrame.WsSideStatus(
                            currentTemperature: 68 + Double.random(in: -0.5...0.5),
                            targetTemperature: 66,
                            currentLevel: -3,
                            targetLevel: -3,
                            heatingDuration: 0,
                            isAlarmVibrating: false
                        ),
                        waterLevel: "normal",
                        isPriming: false,
                        snooze: nil
                    )
                    self.trackDemoFrame("deviceStatus")
                }

                // --- FrzHealth (every 20 ticks = 10s) ---
                if tick % 20 == 0 {
                    self.frzHealth = FrzHealthFrame(
                        ts: Int(Date().timeIntervalSince1970),
                        left: FrzSideHealth(
                            tec: FrzSideHealth.TecInfo(current: Float.random(in: 1.5...2.5)),
                            pump: FrzSideHealth.PumpInfo(mode: "normal", rpm: Int.random(in: 1800...2200), water: true)
                        ),
                        right: FrzSideHealth(
                            tec: FrzSideHealth.TecInfo(current: Float.random(in: 1.5...2.5)),
                            pump: FrzSideHealth.PumpInfo(mode: "normal", rpm: Int.random(in: 1800...2200), water: true)
                        ),
                        fan: FrzFanHealth(
                            top: FrzFanHealth.FanInfo(rpm: Int.random(in: 2800...3200)),
                            bottom: FrzFanHealth.FanInfo(rpm: Int.random(in: 2800...3200))
                        )
                    )
                    self.trackDemoFrame("frzHealth")
                }

                // --- BedTemp (every 32 ticks = 16s) ---
                if tick % 32 == 0 {
                    let ambC: Float = 22.5 + Float.random(in: -0.3...0.3)
                    let huPct: Float = 45 + Float.random(in: -2...2)
                    let leftZones: [Float] = [30.5, 31.2, 29.8, 30.0].map { $0 + Float.random(in: -0.2...0.2) }
                    let rightZones: [Float] = [29.0, 29.8, 28.5, 29.2].map { $0 + Float.random(in: -0.2...0.2) }
                    self.leftTemps = BedTempSide(amb: ambC, hu: huPct, temps: leftZones)
                    self.rightTemps = BedTempSide(amb: ambC, hu: huPct, temps: rightZones)
                    if let avgL = self.leftTemps?.avgSurfaceTempF {
                        self.leftTempHistory.append((.now, Float(avgL)))
                        if self.leftTempHistory.count > self.maxTempHistory { self.leftTempHistory.removeFirst() }
                    }
                    if let avgR = self.rightTemps?.avgSurfaceTempF {
                        self.rightTempHistory.append((.now, Float(avgR)))
                        if self.rightTempHistory.count > self.maxTempHistory { self.rightTempHistory.removeFirst() }
                    }
                    self.trackDemoFrame("bedTemp2")
                }
            }
        }
    }

    private func trackDemoFrame(_ type: String) {
        frameCounts[type, default: 0] += 1
        recentFrames.insert(
            RawFrameEntry(timestamp: .now, type: type, json: "{\"type\":\"\(type)\",\"demo\":true}"),
            at: 0
        )
        if recentFrames.count > maxRecentFrames { recentFrames.removeLast() }
    }

    func stopDemoStream() {
        demoTask?.cancel()
        demoTask = nil
        isConnected = false
    }

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

        // Track per-type counts and raw frames for pipeline view
        let frameType = frame.typeName
        frameCounts[frameType, default: 0] += 1
        if let jsonStr = String(data: data, encoding: .utf8) {
            recentFrames.insert(RawFrameEntry(timestamp: .now, type: frameType, json: jsonStr), at: 0)
            if recentFrames.count > maxRecentFrames { recentFrames.removeLast() }
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

        case .deviceStatus(let status):
            latestDeviceStatus = status

        case .gesture(let g):
            lastGesture = g
            let entry = FirmwareLogEntry(
                timestamp: Date(),
                level: .info,
                message: "[\(g.tapType)] \(g.side) side tapped"
            )
            firmwareLogs.append(entry)
            if firmwareLogs.count > maxLogLines { firmwareLogs.removeFirst() }

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
