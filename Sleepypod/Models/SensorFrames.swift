import Foundation

// MARK: - WebSocket Sensor Frame Types

/// Discriminated union for all sensor frame types from ws://pod:3001
enum SensorFrame: Sendable {
    case piezoDual(PiezoDualFrame)
    case capSense2(CapSense2Frame)
    case bedTemp2(BedTemp2Frame)
    case frzHealth(FrzHealthFrame)
    case log(LogFrame)
    case unknown(String)

    static func decode(from data: Data) -> SensorFrame? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        let decoder = JSONDecoder()
        switch type {
        case "piezo-dual":
            return (try? decoder.decode(PiezoDualFrame.self, from: data)).map { .piezoDual($0) }
        case "capSense2":
            return (try? decoder.decode(CapSense2Frame.self, from: data)).map { .capSense2($0) }
        case "bedTemp2":
            return (try? decoder.decode(BedTemp2Frame.self, from: data)).map { .bedTemp2($0) }
        case "frzHealth":
            return (try? decoder.decode(FrzHealthFrame.self, from: data)).map { .frzHealth($0) }
        case "log":
            return (try? decoder.decode(LogFrame.self, from: data)).map { .log($0) }
        default:
            return .unknown(type)
        }
    }
}

// MARK: - Piezo (~1 Hz, 500 samples per side)

struct PiezoDualFrame: Decodable, Sendable {
    let ts: Int
    let freq: Int
    let left1: [Int32]
    let right1: [Int32]
}

// MARK: - Capacitive Presence (~2 Hz)

struct CapSense2Frame: Decodable, Sendable {
    let ts: Int
    let left: CapSenseSide
    let right: CapSenseSide
}

struct CapSenseSide: Decodable, Sendable {
    let values: [Float]  // 8 values: [0:2]=A (head), [2:4]=B (torso), [4:6]=C (legs), [6:8]=REF
    let status: String

    /// Raw channel averages (paired channels)
    var channelAverages: (a: Float, b: Float, c: Float, ref: Float) {
        guard values.count >= 8 else { return (0, 0, 0, 0) }
        return (
            (values[0] + values[1]) / 2,
            (values[2] + values[3]) / 2,
            (values[4] + values[5]) / 2,
            (values[6] + values[7]) / 2
        )
    }

    /// Presence zones with REF baseline subtracted, normalized 0–1
    /// Typical delta from REF is 13–24 pF when occupied
    var zones: (head: Float, torso: Float, legs: Float) {
        let ch = channelAverages
        let a = max(0, ch.a - ch.ref)
        let b = max(0, ch.b - ch.ref)
        let c = max(0, ch.c - ch.ref)
        let scale: Float = 30.0
        return (min(a / scale, 1), min(b / scale, 1), min(c / scale, 1))
    }

    /// Unreliable without calibrated baselines — prefer variance-based detection.
    /// This only checks if the sensor hardware is functioning.
    var sensorHealthy: Bool {
        status == "good"
    }
}

// MARK: - Bed Temperature (~0.06 Hz)

struct BedTemp2Frame: Decodable, Sendable {
    let ts: Int
    let mcu: Float?
    let left: BedTempSide
    let right: BedTempSide
}

struct BedTempSide: Decodable, Sendable {
    let amb: Float   // ambient °C
    let hu: Float    // humidity %
    let temps: [Float]  // 4 zone temps °C

    /// Average valid surface temp in °F (filters -327 sentinel values)
    var avgSurfaceTempF: Int? {
        let valid = temps.filter { $0 > -100 }
        guard !valid.isEmpty else { return nil }
        let avgC = valid.reduce(0, +) / Float(valid.count)
        return Int(avgC * 9.0 / 5.0 + 32)
    }
}

// MARK: - Freezer Health

struct FrzHealthFrame: Decodable, Sendable {
    let ts: Int
    let left: FrzSideHealth
    let right: FrzSideHealth
    let fan: FrzFanHealth?
}

struct FrzSideHealth: Decodable, Sendable {
    let tec: TecInfo
    let pump: PumpInfo

    struct TecInfo: Decodable, Sendable {
        let current: Float
    }

    struct PumpInfo: Decodable, Sendable {
        let mode: String?
        let rpm: Int?
        let water: Bool?
    }
}

struct FrzFanHealth: Decodable, Sendable {
    let top: FanInfo?
    let bottom: FanInfo?

    struct FanInfo: Decodable, Sendable {
        let rpm: Int
    }
}

// MARK: - Log Frame

struct LogFrame: Decodable, Sendable {
    let ts: Int
    let level: String
    let msg: String
}

// MARK: - Live Vitals (from DSP)

struct LiveVitals: Sendable {
    var heartRate: Double?
    var breathingRate: Double?
    var confidence: Double = 0
}
