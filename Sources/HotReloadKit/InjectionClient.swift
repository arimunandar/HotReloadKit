#if DEBUG
import Foundation
import os

/// HTTP client that fetches compiled dylibs from the host's file server
public actor InjectionClient {
    public static let shared = InjectionClient()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.hotreload", category: "client")

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        // Allow connecting to localhost from simulator
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Fetch a dylib from the host's HTTP server
    /// - Parameter urlString: The full URL to the dylib
    /// - Returns: The dylib binary data
    public func fetchDylib(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw InjectionError.invalidURL(urlString)
        }

        logger.info("Fetching dylib from \(urlString)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InjectionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw InjectionError.httpError(httpResponse.statusCode)
        }

        logger.info("Fetched dylib: \(data.count) bytes")
        return data
    }
}

enum InjectionError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
#endif
