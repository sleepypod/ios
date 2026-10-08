import Foundation
import Network
import XCTest
@testable import Sleepypod

final class StartupTests: XCTestCase {
    @MainActor
    func testLiveDiscoveryDoesNotWaitForStaleSavedAddress() async throws {
        guard ProcessInfo.processInfo.environment["POD_TEST_URL"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_POD_TEST_URL for discovery timing")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        let cache = defaults.data(forKey: "cachedDeviceStatus")
        defer {
            defaults.set(saved, forKey: "podIPAddress")
            defaults.set(cache, forKey: "cachedDeviceStatus")
        }
        defaults.set("192.0.2.1", forKey: "podIPAddress")
        let client = SleepypodCoreClient()
        let settings = SettingsManager(api: client)
        let manager = DeviceManager(api: client)
        let discovery = PodDiscovery()
        let start = ContinuousClock.now
        let address = await discovery.autoConnect(settingsManager: settings, deviceManager: manager)
        XCTAssertNotNil(address)
        XCTAssertNotEqual(address, "192.0.2.1")
        XCTAssertTrue(manager.isConnected)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    @MainActor
    func testLocalNetworkDenialAndRecoveryAreVisible() {
        let discovery = PodDiscovery()
        discovery.handleBrowserState(.waiting(.dns(-65570)))
        XCTAssertEqual(discovery.status, .permissionRequired)
        XCTAssertFalse(discovery.isSearching)
        discovery.handleBrowserState(.ready)
        XCTAssertEqual(discovery.status, .scanning)
        XCTAssertTrue(discovery.isSearching)
        discovery.stopBrowsing()
    }

    func testUnfilteredMetricsDoNotSilentlySelectLeftSide() async throws {
        let (client, session) = mutationClient(scenario: "bothSides")
        defer { session.invalidateAndCancel() }
        _ = try await client.getSleepRecords()
        _ = try await client.getVitals()
        _ = try await client.getMovement()
    }

    func testAmbientLightAllowsUnavailableMeasurement() throws {
        let json = #"{"id":1,"timestamp":"2026-09-06T00:00:00.000Z","lux":null}"#
        let reading = try JSONDecoder().decode(AmbientLightReading.self, from: Data(json.utf8))
        XCTAssertNil(reading.lux)
    }

    @MainActor
    func testManualEntrySupersedesDiscovery() async {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        defer { defaults.set(saved, forKey: "podIPAddress") }
        defaults.removeObject(forKey: "podIPAddress")
        let client = MockAPIClient()
        let settings = SettingsManager(api: client)
        let manager = DeviceManager(api: client)
        let discovery = PodDiscovery()
        let task = Task { await discovery.autoConnect(settingsManager: settings, deviceManager: manager) }
        while !discovery.isSearching { await Task.yield() }
        settings.podIP = "192.0.2.42"
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(settings.podIP, "192.0.2.42")
        XCTAssertEqual(discovery.status, .idle)
        XCTAssertFalse(manager.isConnected)
        XCTAssertFalse(discovery.isSearching)
    }

    @MainActor
    func testOldScanCleanupDoesNotStopNewScan() async {
        let client = MockAPIClient()
        let settings = SettingsManager(api: client)
        let manager = DeviceManager(api: client)
        let discovery = PodDiscovery()
        let first = Task { await discovery.autoConnect(settingsManager: settings, deviceManager: manager) }
        while !discovery.isSearching { await Task.yield() }
        discovery.cancelAutoConnect()
        let second = Task { await discovery.autoConnect(settingsManager: settings, deviceManager: manager) }
        while !discovery.isSearching { await Task.yield() }
        first.cancel()
        let oldResult = await first.value
        XCTAssertNil(oldResult)
        XCTAssertTrue(discovery.isSearching)
        second.cancel()
        _ = await second.value
        XCTAssertFalse(discovery.isSearching)
    }

    @MainActor
    func testLiveStatusStream() async throws {
        guard let address = ProcessInfo.processInfo.environment["POD_TEST_URL"],
              let host = URL(string: address)?.host else { throw XCTSkip("Set TEST_RUNNER_POD_TEST_URL for live status streaming") }
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        let backend = APIBackend.current
        let stream = SensorStreamService()
        defer {
            stream.disconnect()
            defaults.set(saved, forKey: "podIPAddress")
            APIBackend.current = backend
        }
        defaults.set(host, forKey: "podIPAddress")
        APIBackend.current = .sleepypodCore
        stream.connect()
        let deadline = ContinuousClock.now + .seconds(10)
        while stream.latestDeviceStatus == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(stream.isCurrentPod)
        XCTAssertTrue(stream.isConnected)
        XCTAssertNotNil(stream.latestDeviceStatus)
    }

    @MainActor
    func testWebSocketRejectsStatusFromPreviousAddress() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        let backend = APIBackend.current
        let stream = SensorStreamService()
        defer {
            stream.disconnect()
            defaults.set(saved, forKey: "podIPAddress")
            APIBackend.current = backend
        }
        APIBackend.current = .sleepypodCore
        defaults.set("192.0.2.1", forKey: "podIPAddress")
        stream.connect()
        XCTAssertTrue(stream.isCurrentPod)
        defaults.set("192.0.2.2", forKey: "podIPAddress")
        XCTAssertFalse(stream.isCurrentPod)
        stream.disconnect()
        XCTAssertNil(stream.latestDeviceStatus)
    }

    func testPowerOnPreservesRequestedTemperature() async throws {
        let (client, session) = mutationClient(scenario: "power")
        defer { session.invalidateAndCancel() }
        try await client.updateDeviceStatus(DeviceStatusUpdate(
            left: SideStatusUpdate(targetTemperatureF: 68, isOn: true)))
    }

    func testOvernightPowerScheduleIsSentToCore() async throws {
        let (client, session) = mutationClient(scenario: "overnight")
        defer { session.invalidateAndCancel() }
        var schedules = try await client.getSchedules()
        // An endAction marks a core on the overnight-capable power model; legacy cores stay same-day only.
        schedules.left.monday.power = PowerSchedule(on: "22:00", off: "07:00", endAction: .turnOff, onTemperature: 68, enabled: true)
        _ = try await client.updateSchedules(schedules, days: [.monday])
    }

    private func mutationClient(scenario: String) -> (SleepypodCoreClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MutationContractProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Scenario": scenario]
        let session = URLSession(configuration: config)
        return (SleepypodCoreClient(session: session, baseURL: URL(string: "http://pod.test:3000")), session)
    }

    @MainActor
    func testCacheBelongsToItsPodAndDoesNotClaimLiveConnection() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        let cache = defaults.data(forKey: "cachedDeviceStatus")
        defer {
            defaults.set(saved, forKey: "podIPAddress")
            defaults.set(cache, forKey: "cachedDeviceStatus")
        }
        defaults.set("192.0.2.1", forKey: "podIPAddress")
        let manager = DeviceManager(api: MockAPIClient())
        manager.acceptStatus(try await MockClient().getDeviceStatus())
        let samePod = DeviceManager(api: MockAPIClient())
        XCTAssertNotNil(samePod.deviceStatus)
        XCTAssertFalse(samePod.isConnected)
        defaults.set("192.0.2.2", forKey: "podIPAddress")
        let differentPod = DeviceManager(api: MockAPIClient())
        XCTAssertNil(differentPod.deviceStatus)
        await manager.fetchStatus()
        XCTAssertFalse(manager.isConnected)
        XCTAssertNil(manager.deviceStatus)
    }

    func testSleepRecordEditSendsTypedDates() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DateMutationProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = SleepypodCoreClient(session: session, baseURL: URL(string: "http://pod.test:3000"))
        try await client.updateSleepRecord(id: 42, enteredBedAt: Date(timeIntervalSince1970: 1_700_000_000), leftBedAt: nil)
    }

    @MainActor
    func testSupersededStatusCannotReplaceVerifiedSnapshot() async throws {
        let cache = UserDefaults.standard.data(forKey: "cachedDeviceStatus")
        defer { UserDefaults.standard.set(cache, forKey: "cachedDeviceStatus") }
        let client = SuspendedStatusClient()
        let manager = DeviceManager(api: client)
        let pending = Task { await manager.fetchStatus() }
        await client.gate.waitForRequest()
        var latest = try await MockClient().getDeviceStatus()
        latest.waterLevel = "latest"
        manager.acceptStatus(latest)
        var stale = latest
        stale.waterLevel = "stale"
        await client.gate.finish(stale)
        await pending.value
        XCTAssertEqual(manager.deviceStatus?.waterLevel, "latest")
    }

    @MainActor
    func testCancelledStatusDoesNotEstablishConnection() async throws {
        let cache = UserDefaults.standard.data(forKey: "cachedDeviceStatus")
        defer { UserDefaults.standard.set(cache, forKey: "cachedDeviceStatus") }
        let client = SuspendedStatusClient()
        let manager = DeviceManager(api: client)
        let pending = Task { await manager.fetchStatus() }
        await client.gate.waitForRequest()
        pending.cancel()
        await client.gate.finish(try await MockClient().getDeviceStatus())
        await pending.value
        XCTAssertFalse(manager.isConnected)
        XCTAssertFalse(manager.isConnecting)
        XCTAssertNil(manager.lastUpdated)
    }

    @MainActor
    func testCancelledDiscoveryCannotSaveAnAddress() async {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "podIPAddress")
        defer { defaults.set(saved, forKey: "podIPAddress") }
        defaults.removeObject(forKey: "podIPAddress")
        let client = MockAPIClient()
        let settings = SettingsManager(api: client)
        let manager = DeviceManager(api: client)
        let discovery = PodDiscovery()
        let pending = Task { await discovery.autoConnect(settingsManager: settings, deviceManager: manager) }
        pending.cancel()
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertEqual(settings.podIP, "")
        XCTAssertFalse(discovery.isSearching)
        XCTAssertFalse(manager.isConnected)
    }

    @MainActor
    func testLiveDiscoveryFromEmptyAddress() async throws {
        guard ProcessInfo.processInfo.environment["POD_TEST_URL"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_POD_TEST_URL to opt in to local discovery")
        }
        let defaults = UserDefaults.standard
        let savedIP = defaults.string(forKey: "podIPAddress")
        let cachedStatus = defaults.data(forKey: "cachedDeviceStatus")
        defer {
            defaults.set(savedIP, forKey: "podIPAddress")
            defaults.set(cachedStatus, forKey: "cachedDeviceStatus")
        }
        defaults.removeObject(forKey: "podIPAddress")
        defaults.removeObject(forKey: "cachedDeviceStatus")
        let client = SleepypodCoreClient()
        let settings = SettingsManager(api: client)
        let device = DeviceManager(api: client)
        let discovery = PodDiscovery()
        let start = Date()
        let ip = await discovery.autoConnect(settingsManager: settings, deviceManager: device)
        print("Live discovery to usable status: \(Date().timeIntervalSince(start)) seconds")
        XCTAssertNotNil(ip)
        XCTAssertTrue(device.isConnected)
        XCTAssertNotNil(device.lastUpdated)
        XCTAssertFalse(discovery.isSearching)
    }

    func testLiveCoreLogs() async throws {
        guard let address = ProcessInfo.processInfo.environment["POD_TEST_URL"],
              let url = URL(string: address) else { throw XCTSkip("Set TEST_RUNNER_POD_TEST_URL for live log access") }
        _ = try await SleepypodCoreClient(baseURL: url).getLogs(unit: "sleepypod.service", lines: 1)
    }

    func testLiveCoreReadEndpoints() async throws {
        guard let address = ProcessInfo.processInfo.environment["POD_TEST_URL"],
              let url = URL(string: address) else { throw XCTSkip("Set TEST_RUNNER_POD_TEST_URL to opt in to read-only device checks") }
        let client = SleepypodCoreClient(baseURL: url)
        let start = Date()
        _ = try await client.getDeviceStatus()
        print("Live core first status: \(Date().timeIntervalSince(start)) seconds")
        _ = try await client.getSettings()
        _ = try await client.getSchedules()
        _ = try await client.getServerStatus()
        _ = try await client.getVersion()
        _ = try await client.getLogSources()
        _ = try await client.getInternetStatus()
        _ = try await client.getDiskUsage()
        _ = try await client.getFileCount()
        _ = try await client.getCalibrationStatus(side: .left)
        _ = try await client.getSleepRecords(side: .left)
        _ = try await client.getVitals(side: .left)
        _ = try await client.getMovement(side: .left)
        _ = try await client.getVitalsSummary(side: .left)
        _ = try await client.getWaterLevelLatest()
        _ = try await client.getWaterLevelTrend()
        _ = try await client.getAmbientLightLatest()
        let end = Date()
        _ = try await client.getBedTempHistory(start: end.addingTimeInterval(-3600), end: end, limit: 120, unit: "F")
        _ = try await client.getActiveRunOnce(side: .left)
    }

    func testPoweredOffStatusNeedsOnlyOneFastQuery() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatusFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = SleepypodCoreClient(session: session, baseURL: URL(string: "http://pod.test:3000"))
        let status = try await client.getDeviceStatus()
        XCTAssertNil(status.left.targetTemperatureF)
        XCTAssertNil(status.right.currentTemperatureF)
        XCTAssertEqual(status.left.currentTemperatureF, 79)
        XCTAssertEqual(status.left.currentTemperatureLevel, -12)
        XCTAssertFalse(status.left.isOn)
        XCTAssertTrue(status.right.isAlarmVibrating)
        XCTAssertEqual(status.wifiStrength, 52)
    }

    func testWebSocketAcceptsMissingTemperatures() throws {
        let json = """
        {"ts":1,"leftSide":{"currentTemperature":79,"targetTemperature":null,"currentLevel":-12,"targetLevel":0,"heatingDuration":0,"isAlarmVibrating":false},
        "rightSide":{"currentTemperature":null,"targetTemperature":null,"currentLevel":0,"targetLevel":0,"heatingDuration":0,"isAlarmVibrating":false},"waterLevel":"ok","isPriming":false}
        """
        let frame = try JSONDecoder().decode(DeviceStatusFrame.self, from: Data(json.utf8))
        let status = frame.toDeviceStatus(preserving: nil)
        XCTAssertNil(status.left.targetTemperatureF)
        XCTAssertNil(status.right.currentTemperatureF)
        XCTAssertFalse(status.left.isOn)
    }

    func testRebootDoesNotPrimeHardware() async throws {
        let client = SleepypodCoreClient(baseURL: URL(string: "http://pod.test:3000"))
        do {
            try await client.reboot()
            XCTFail("Core has no reboot procedure")
        } catch APIError.notSupported { }
    }
}

private final class StatusFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Any diagnostics batch or second endpoint fails this startup contract.
        guard let url = request.url, url.path == "/api/trpc/device.getStatus",
              request.httpMethod == "GET",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == "input" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let json = """
        {"result":{"data":{"json":{"leftSide":{"currentTemperature":79,"targetTemperature":null,"currentLevel":-12,"targetLevel":0,"heatingDuration":0},
        "rightSide":{"currentTemperature":null,"targetTemperature":null,"currentLevel":0,"targetLevel":0,"heatingDuration":0,"isAlarmVibrating":true},
        "waterLevel":"ok","isPriming":false,"podVersion":"J00","sensorLabel":"20600","wifiStrength":52}}}}
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class SuspendedStatusClient: MockAPIClient, @unchecked Sendable {
    let gate = StatusRequestGate()
    override func getDeviceStatus() async throws -> DeviceStatus {
        await gate.request()
    }
}

private actor StatusRequestGate {
    private var pending: CheckedContinuation<DeviceStatus, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func request() async -> DeviceStatus {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ status: DeviceStatus) {
        pending?.resume(returning: status)
        pending = nil
    }
}

private final class DateMutationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let envelope = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let input = envelope?["json"] as? [String: Any]
        let meta = envelope?["meta"] as? [String: Any]
        let dates = meta?["values"] as? [String: [String]]
        guard let url = request.url, url.path == "/api/trpc/biometrics.updateSleepRecord",
              request.httpMethod == "POST", input?["id"] as? Int == 42,
              input?["enteredBedAt"] as? String == "2023-11-14T22:13:20Z",
              input?["leftBedAt"] == nil, dates == ["enteredBedAt": ["Date"]] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = #"{"result":{"data":{"json":{"id":42,"side":"left","enteredBedAt":"2023-11-14T22:13:20Z","leftBedAt":null,"sleepDurationSeconds":0,"timesExitedBed":0}}}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class MutationContractProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let envelope = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let input = envelope?["json"] as? [String: Any]
        let path = request.url?.path ?? ""
        let scenario = request.value(forHTTPHeaderField: "X-Test-Scenario")
        var output = #"{"success":true}"#
        var valid = false
        if scenario == "bothSides", let url = request.url {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let encoded = query?.first(where: { $0.name == "input" })?.value ?? ""
            let envelope = (try? JSONSerialization.jsonObject(with: Data(encoded.utf8))) as? [String: Any]
            let input = envelope?["json"] as? [String: Any]
            valid = ["/api/trpc/biometrics.getSleepRecords", "/api/trpc/biometrics.getVitals", "/api/trpc/biometrics.getMovement"].contains(path)
                && request.httpMethod == "GET" && input != nil && input?["side"] == nil
            output = "[]"
        } else if scenario == "power" {
            valid = path == "/api/trpc/device.setPower" && request.httpMethod == "POST"
                && input?["side"] as? String == "left" && input?["powered"] as? Bool == true
                && input?["temperature"] as? Int == 68
        } else if scenario == "overnight" {
            if path == "/api/trpc/schedules.getAll" && request.httpMethod == "GET" {
                valid = true
                output = #"{"temperature":[],"power":[],"alarm":[]}"#
            } else if path == "/api/trpc/schedules.batchUpdate" && request.httpMethod == "POST" {
                let creates = input?["creates"] as? [String: Any]
                let power = creates?["power"] as? [[String: Any]]
                valid = power?.count == 1 && power?.first?["onTime"] as? String == "22:00"
                    && power?.first?["offTime"] as? String == "07:00"
                    && power?.first?["dayOfWeek"] as? String == "monday"
                    && power?.first?["side"] as? String == "left"
            }
        }
        guard valid, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let json = "{\"result\":{\"data\":{\"json\":\(output)}}}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
