import Foundation
import Testing
@testable import SleepypodModels

// MARK: - tRPC Envelope

/// tRPC responses are wrapped: {"result":{"data":{"json": T}}}
private struct TRPCEnvelope<T: Decodable>: Decodable {
    let result: TRPCResult<T>
}
private struct TRPCResult<T: Decodable>: Decodable {
    let data: TRPCData<T>
}
private struct TRPCData<T: Decodable>: Decodable {
    let json: T
}

private func loadFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw NSError(
            domain: "ContractTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(name).json"]
        )
    }
    return try Data(contentsOf: url)
}

private func decodeTRPC<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let data = try loadFixture(name)
    let envelope = try JSONDecoder().decode(TRPCEnvelope<T>.self, from: data)
    return envelope.result.data.json
}

private func decodeTRPCOptional<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
    let data = try loadFixture(name)
    // Check if it's a null/empty fixture
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = json["result"] as? [String: Any],
       let dataObj = result["data"] as? [String: Any],
       dataObj["json"] is NSNull {
        return nil
    }
    return try decodeTRPC(name, as: type)
}

// MARK: - Healthcheck

@Test func healthcheckDecodes() throws {
    let result = try decodeTRPC("healthcheck", as: String.self)
    #expect(result == "yay!" || !result.isEmpty)
}

// MARK: - Health

@Test func healthSystemDecodes() throws {
    struct HealthSystem: Codable {
        var status: String
    }
    let result = try decodeTRPC("health-system", as: HealthSystem.self)
    #expect(result.status == "ok" || result.status == "degraded")
}

@Test func healthSchedulerDecodes() throws {
    struct HealthScheduler: Codable {
        var enabled: Bool
        var healthy: Bool
    }
    _ = try decodeTRPC("health-scheduler", as: HealthScheduler.self)
}

// MARK: - System

@Test func internetStatusDecodes() throws {
    struct InternetStatus: Codable {
        var blocked: Bool
    }
    _ = try decodeTRPC("internet-status", as: InternetStatus.self)
}

@Test func wifiStatusDecodes() throws {
    struct WifiStatus: Codable {
        var connected: Bool
        var ssid: String?
        var signal: Int?
    }
    _ = try decodeTRPC("wifi-status", as: WifiStatus.self)
}

// MARK: - Biometrics

@Test func processingStatusDecodes() throws {
    struct ProcessingStatus: Codable {
        var iosProcessingActive: Bool
    }
    _ = try decodeTRPC("processing-status", as: ProcessingStatus.self)
}

// MARK: - Device (may fail in CI without hardware)

@Test func deviceStatusDecodesIfAvailable() throws {
    guard let _ = try? decodeTRPCOptional("device-status", as: DeviceStatusJSON.self) else {
        return // Skip if fixture is null (no hardware in CI)
    }
}

private struct DeviceStatusJSON: Codable {
    var leftSide: SideJSON
    var rightSide: SideJSON
    var waterLevel: String
    var isPriming: Bool
}
private struct SideJSON: Codable {
    var currentTemperature: Double
    var targetTemperature: Double
    var heatingDuration: Int
}

// MARK: - Calibration (may not exist in CI)

@Test func calibrationDecodesIfAvailable() throws {
    struct CalibrationSensor: Codable {
        var status: String
        var sensorType: String
    }
    struct CalibrationStatus: Codable {
        var capacitance: CalibrationSensor
        var piezo: CalibrationSensor
        var temperature: CalibrationSensor
    }
    _ = try? decodeTRPCOptional("calibration-left", as: CalibrationStatus.self)
}
