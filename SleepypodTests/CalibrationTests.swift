import Testing
import Foundation
@testable import Sleepypod

@Suite("Calibration")
struct CalibrationTests {

    private func makeSensor(_ type: String, status: String, quality: Double? = nil, error: String? = nil) -> CalibrationSensor {
        CalibrationSensor(id: 1, side: "left", sensorType: type, status: status, qualityScore: quality, samplesUsed: 300, errorMessage: error)
    }

    @Test("Nullable sensor fields decode correctly")
    func nullableSensors() throws {
        let json = """
        {"capacitance": null, "piezo": {"id":1,"side":"left","sensorType":"piezo","status":"completed","qualityScore":0.85,"samplesUsed":300,"errorMessage":null}, "temperature": null}
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(CalibrationStatus.self, from: json)
        #expect(cal.capacitance == nil)
        #expect(cal.piezo?.status == "completed")
        #expect(cal.piezo?.qualityScore == 0.85)
        #expect(cal.temperature == nil)
        #expect(cal.sensors.count == 1) // only piezo, others nil
    }

    @Test("All sensors present decodes correctly")
    func allSensors() throws {
        let json = """
        {
            "capacitance": {"id":1,"side":"left","sensorType":"capacitance","status":"completed","qualityScore":1.0,"samplesUsed":300,"errorMessage":null},
            "piezo": {"id":2,"side":"left","sensorType":"piezo","status":"completed","qualityScore":0.0,"samplesUsed":300,"errorMessage":null},
            "temperature": {"id":3,"side":"left","sensorType":"temperature","status":"completed","qualityScore":0.356,"samplesUsed":356,"errorMessage":null}
        }
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(CalibrationStatus.self, from: json)
        #expect(cal.sensors.count == 3)
        #expect(cal.healthyCount == 3)
    }

    @Test("Failed sensor with error message")
    func failedSensor() throws {
        let json = """
        {
            "capacitance": {"id":1,"side":"left","sensorType":"capacitance","status":"failed","qualityScore":null,"samplesUsed":null,"errorMessage":"No capSense records available"},
            "piezo": {"id":2,"side":"left","sensorType":"piezo","status":"completed","qualityScore":0.8,"samplesUsed":300,"errorMessage":null},
            "temperature": null
        }
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(CalibrationStatus.self, from: json)
        #expect(cal.sensors.count == 2) // cap + piezo, temp is nil
        #expect(cal.capacitance?.status == "failed")
        #expect(cal.capacitance?.errorMessage == "No capSense records available")
        #expect(cal.healthyCount == 1) // only piezo completed
    }

    @Test("Healthy count requires completed status")
    func healthyCount() {
        let cal = CalibrationStatus(
            capacitance: makeSensor("capacitance", status: "completed", quality: 1.0),
            piezo: makeSensor("piezo", status: "pending"),
            temperature: makeSensor("temperature", status: "failed", error: "timeout")
        )
        #expect(cal.healthyCount == 1)
        #expect(cal.sensors.count == 3)
    }

    @Test("Trigger calibration calls API for each sensor type")
    @MainActor
    func triggerPerSensor() async {
        let mock = MockAPIClient()
        mock.calibrationStatuses["left"] = CalibrationStatus(
            capacitance: makeSensor("capacitance", status: "completed", quality: 1.0),
            piezo: makeSensor("piezo", status: "completed", quality: 0.8),
            temperature: makeSensor("temperature", status: "completed", quality: 0.5)
        )

        // Trigger individual sensors
        _ = try? await mock.triggerCalibration(side: .left, sensorType: "piezo")
        _ = try? await mock.triggerCalibration(side: .left, sensorType: "temperature")
        _ = try? await mock.triggerCalibration(side: .left, sensorType: "capacitance")

        #expect(mock.triggerCalibrationCalls.count == 3)
        #expect(mock.triggerCalibrationCalls[0].1 == "piezo")
    }

    @Test("Full calibration calls single API endpoint")
    @MainActor
    func triggerFull() async {
        let mock = MockAPIClient()
        _ = try? await mock.triggerFullCalibration()
        #expect(mock.triggerFullCalibrationCalls == 1)
    }
}
