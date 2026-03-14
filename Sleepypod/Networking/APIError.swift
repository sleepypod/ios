import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse(statusCode: Int)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case networkError(Error)
    case serverError(message: String)
    case noBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .invalidResponse(let code):
            "Server returned status \(code)"
        case .decodingFailed(let error):
            "Failed to decode response: \(error.localizedDescription)"
        case .encodingFailed(let error):
            "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .serverError(let message):
            "Server error: \(message)"
        case .noBaseURL:
            "Pod IP address not configured"
        }
    }
}
