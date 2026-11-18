import Foundation

enum HTTPError: LocalizedError {
    case status(Int, String)
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .status(let code, let service): "\(service): ошибка сервера (\(code))"
        case .missingKey(let service): "\(service): не указан ключ API в Настройках"
        }
    }
}

enum HTTP {
    static func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], service: String) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, service)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func url(_ base: String, _ query: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}
