import Foundation
import os

/// JSON over HTTPS for the API providers.
enum HTTPTransport {
    struct Response: Sendable {
        var status: Int
        var data: Data

        var isSuccess: Bool { (200..<300).contains(status) }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// POSTs `body` as JSON. Network failures become `LLMError`s; any HTTP status is returned as is.
    /// `sessionConfiguration` should be a fresh ephemeral one, so nothing is cached on disk.
    static func post<Body: Encodable>(_ url: URL, headers: [String: String], body: Body, provider: Provider,
                                      timeout: TimeInterval,
                                      sessionConfiguration: URLSessionConfiguration) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try encoder.encode(body)

        sessionConfiguration.timeoutIntervalForRequest = timeout
        sessionConfiguration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Logger.backend.info("\(provider.rawValue, privacy: .public) responded with HTTP \(status), \(data.count) bytes")
            return Response(status: status, data: data)
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            if error.code == .timedOut { throw LLMError.timeout }
            throw LLMError.network(provider, error.localizedDescription)
        }
    }

    /// Anthropic and OpenAI both answer errors with `{"error": {"message": …}}`.
    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail
    }

    static func error(for response: Response, provider: Provider) -> LLMError {
        switch response.status {
        case 401, 403:
            return .credentialsRejected(provider)
        case 429:
            return .rateLimited(provider)
        case 503, 529:
            return .overloaded(provider)
        default:
            let message = (try? decoder.decode(ErrorEnvelope.self, from: response.data))?.error.message
                ?? String(decoding: response.data.prefix(300), as: UTF8.self)
            return .requestFailed(provider, status: response.status,
                                  message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from response: Response, provider: Provider) throws -> T {
        do {
            return try decoder.decode(type, from: response.data)
        } catch {
            throw LLMError.requestFailed(provider, status: response.status, message: "Unexpected response.")
        }
    }
}
