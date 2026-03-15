import Foundation

final class FreeSleepClient: SleepypodProtocol, @unchecked Sendable {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var baseURL: URL? {
        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress"), !ip.isEmpty else {
            return nil
        }
        return URL(string: "http://\(ip):3000")
    }

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Device Status

    func getDeviceStatus() async throws -> DeviceStatus {
        try await get(.deviceStatus)
    }

    func updateDeviceStatus(_ update: DeviceStatusUpdate) async throws {
        try await post(.updateDeviceStatus, body: update, expectResponse: false)
    }

    // MARK: - Settings

    func getSettings() async throws -> PodSettings {
        try await get(.settings)
    }

    func updateSettings(_ settings: PodSettings) async throws -> PodSettings {
        try await post(.updateSettings, body: settings)
    }

    // MARK: - Schedules

    func getSchedules() async throws -> Schedules {
        try await get(.schedules)
    }

    func updateSchedules(_ schedules: Schedules) async throws -> Schedules {
        try await post(.updateSchedules, body: schedules)
    }

    // MARK: - Server Status

    func getServerStatus() async throws -> ServerStatus {
        try await get(.serverStatus)
    }

    // MARK: - Services

    func getServices() async throws -> Services {
        try await get(.services)
    }

    func updateServices(_ services: Services) async throws -> Services {
        try await post(.updateServices, body: services)
    }

    // MARK: - Metrics

    func getSleepRecords(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [SleepRecord] {
        try await get(.sleepRecords(side: side, start: start, end: end))
    }

    func getVitals(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [VitalsRecord] {
        try await get(.vitals(side: side, start: start, end: end))
    }

    func getVitalsSummary(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> VitalsSummary {
        try await get(.vitalsSummary(side: side, start: start, end: end))
    }

    func getMovement(side: Side? = nil, start: Date? = nil, end: Date? = nil) async throws -> [MovementRecord] {
        try await get(.movement(side: side, start: start, end: end))
    }

    // MARK: - Actions

    func triggerAlarm(_ alarm: AlarmJob) async throws {
        let _: Schedules = try await post(.alarm, body: alarm)
    }

    func reboot() async throws {
        try await postEmpty(path: "/api/execute", body: ["command": "reboot"])
    }

    // MARK: - Private Helpers

    private func buildRequest(_ endpoint: APIEndpoint) throws -> URLRequest {
        guard let base = baseURL else { throw APIError.noBaseURL }
        guard var components = URLComponents(url: base.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = endpoint.queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        return request
    }

    private func get<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let request = try buildRequest(endpoint)
        let (data, response) = try await performRequest(request)
        try validateResponse(response)
        return try decode(data)
    }

    @discardableResult
    private func post<Body: Encodable, Response: Decodable>(
        _ endpoint: APIEndpoint,
        body: Body,
        expectResponse: Bool = true
    ) async throws -> Response {
        var request = try buildRequest(endpoint)
        request.httpBody = try encode(body)
        let (data, response) = try await performRequest(request)
        try validateResponse(response)
        if expectResponse {
            return try decode(data)
        }
        // Return a dummy value for void-like responses — caller should use the throwing overload
        throw APIError.invalidResponse(statusCode: 0) // Should not reach here
    }

    private func post<Body: Encodable>(
        _ endpoint: APIEndpoint,
        body: Body,
        expectResponse: Bool
    ) async throws {
        guard !expectResponse else { return }
        var request = try buildRequest(endpoint)
        request.httpBody = try encode(body)
        let (_, response) = try await performRequest(request)
        try validateResponse(response)
    }

    private func postEmpty(path: String, body: [String: String]) async throws {
        guard let base = baseURL else { throw APIError.noBaseURL }
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(body)
        let (_, response) = try await performRequest(request)
        try validateResponse(response)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIError.encodingFailed(error)
        }
    }
}
