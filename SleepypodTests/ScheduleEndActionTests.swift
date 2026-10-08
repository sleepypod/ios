import Foundation
import Testing
@testable import Sleepypod

@Suite("Schedule end actions", .serialized)
struct ScheduleEndActionTests {
    @Test("Legacy payloads decode without an end action")
    func legacyPower() throws {
        let data = Data(#"{"on":"22:00","off":"07:00","onTemperature":75,"enabled":true}"#.utf8)
        let power = try JSONDecoder().decode(PowerSchedule.self, from: data)
        #expect(power.endAction == nil)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(power)) as? [String: Any]
        #expect(encoded?["endAction"] == nil)
    }

    @Test("Core round-trips maintain, overnight times, and disabled schedules")
    func coreRoundTrip() async throws {
        let previousIP = UserDefaults.standard.string(forKey: "podIPAddress")
        UserDefaults.standard.set("127.0.0.1", forKey: "podIPAddress")
        defer {
            if let previousIP { UserDefaults.standard.set(previousIP, forKey: "podIPAddress") }
            else { UserDefaults.standard.removeObject(forKey: "podIPAddress") }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScheduleProtocolStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        ScheduleProtocolStub.reset()
        let client = SleepypodCoreClient(session: session)
        let schedules = try await client.getSchedules()
        #expect(schedules.left.monday.power.endAction == .maintain)
        #expect(!schedules.left.monday.power.enabled)
        _ = try await client.updateSchedules(schedules, days: [.monday])
        let body = try #require(ScheduleProtocolStub.savedBody)
        let json = try #require(body["json"] as? [String: Any])
        let creates = try #require(json["creates"] as? [String: Any])
        let power = try #require(creates["power"] as? [[String: Any]])
        #expect(power.count == 2)
        #expect(power.allSatisfy { $0["endAction"] as? String == "maintain" })
        #expect(power.allSatisfy { $0["onTime"] as? String == "22:00" && $0["offTime"] as? String == "07:00" })
        #expect(power.allSatisfy { $0["enabled"] as? Bool == false })
    }
}

private final class ScheduleProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var body: [String: Any]?
    static var savedBody: [String: Any]? { lock.withLock { body } }
    static func reset() { lock.withLock { body = nil } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let value: [String: Any]
        if request.url!.path.contains("batchUpdate") {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                var received = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    received.append(contentsOf: bytes.prefix(count))
                }
                data = received
            }
            if let data, let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.lock.withLock { Self.body = decoded }
            }
            value = ["success": true]
        } else {
            value = ["temperature": [], "alarm": [], "power": [[
                "id": 1, "side": "left", "dayOfWeek": "monday",
                "onTime": "22:00", "offTime": "07:00", "onTemperature": 75,
                "enabled": false, "endAction": "maintain"
            ]]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let data = try! JSONSerialization.data(withJSONObject: ["result": ["data": ["json": value]]])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
