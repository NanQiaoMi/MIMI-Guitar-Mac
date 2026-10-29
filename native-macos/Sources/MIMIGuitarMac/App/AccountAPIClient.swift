import Foundation
import Security
import MIMICore

struct RemoteUser: Codable, Hashable, Sendable {
    let id: String
    let email: String?
    let phone: String?
    let nickname: String?
    let avatarURL: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, phone, nickname, createdAt
        case avatarURL = "avatarUrl"
    }
}

struct RemoteFavorite: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let category: String
    let key: String?
    let sheetForm: Int
    let difficulty: Int
    let heat: Int
    let screenshotUrl: String?

    var catalogItem: CatalogItem {
        CatalogItem(
            id: id, title: title, artist: artist, category: category,
            difficulty: difficulty, key: key, sheetForm: sheetForm,
            heat: heat, screenshotURL: screenshotUrl
        )
    }
}

enum AccountAPIError: Error, LocalizedError {
    case invalidBaseURL(String)
    case invalidResponse
    case http(status: Int, message: String)
    case missingSession

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let detail): return detail
        case .invalidResponse: return "服务返回了无法读取的响应。"
        case .http(_, let message): return message
        case .missingSession: return "服务已接受登录，但没有返回可用的登录会话。"
        }
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let source = response.url, let destination = request.url,
              Self.sameOrigin(source, destination) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? {
            if let explicit = url.port { return explicit }
            return url.scheme?.lowercased() == "https" ? 443 : 80
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && port(lhs) == port(rhs)
    }
}

@MainActor
final class AccountAPIClient {
    static let defaultBaseURL = "http://127.0.0.1:4336"

    let baseURL: URL
    private let session: URLSession
    private let redirectDelegate: SameOriginRedirectDelegate
    private let keychainAccount: String
    private var sessionToken: String?

    init(baseURLText: String) throws {
        let validated = try Self.validatedBaseURL(baseURLText)
        baseURL = validated
        keychainAccount = Self.originString(validated)
        sessionToken = SessionTokenKeychain.read(account: keychainAccount)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        redirectDelegate = SameOriginRedirectDelegate()
        session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }

    func validateBaseURL() -> String { Self.originString(baseURL) }

    func fetchCurrentUser() async throws -> RemoteUser? {
        do {
            let envelope: UserEnvelope = try await perform(path: "/api/auth/me", method: "GET")
            return envelope.user
        } catch let error as AccountAPIError {
            if case .http(status: 401, message: _) = error { return nil }
            throw error
        }
    }

    func login(account: String, password: String) async throws -> RemoteUser {
        responseTokenCandidate = nil
        let body = CredentialsBody(account: account, password: password, nickname: nil)
        let response: AuthEnvelope = try await perform(path: "/api/auth/login", method: "POST", body: body)
        try persistSessionFromLastResponse()
        return response.user
    }

    func register(account: String, password: String, nickname: String) async throws -> RemoteUser {
        responseTokenCandidate = nil
        let body = CredentialsBody(account: account, password: password, nickname: nickname)
        let response: AuthEnvelope = try await perform(path: "/api/auth/register", method: "POST", body: body)
        try persistSessionFromLastResponse()
        return response.user
    }

    func logout() async throws {
        let _: SuccessEnvelope = try await perform(path: "/api/auth/logout", method: "POST")
        sessionToken = nil
        SessionTokenKeychain.delete(account: keychainAccount)
    }

    func fetchLegacyFavorites() async throws -> [RemoteFavorite] {
        let response: FavoritesEnvelope = try await perform(path: "/api/favorites", method: "GET")
        return response.favorites
    }

    func removeLegacyFavorite(id: String) async throws {
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        let encoded = id.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
        guard !encoded.isEmpty else { throw AccountAPIError.invalidResponse }
        let _: SuccessEnvelope = try await perform(path: "/api/favorites/\(encoded)", method: "DELETE")
    }

    func publishArticle(title: String, category: String, content: String) async throws -> String {
        let body = ArticleBody(title: title, category: category, content: content)
        let response: PublishedArticleEnvelope = try await perform(path: "/api/articles", method: "POST", body: body)
        return response.id
    }

    func sendResetCode(phone: String) async throws -> String? {
        let response: MessageEnvelope = try await perform(path: "/api/auth/send-code", method: "POST", body: PhoneBody(phone: phone))
        return response.message
    }

    func resetPassword(phone: String, code: String, password: String) async throws -> String? {
        let response: MessageEnvelope = try await perform(
            path: "/api/auth/reset", method: "POST",
            body: ResetBody(phone: phone, code: code, password: password)
        )
        return response.message
    }

    private var responseTokenCandidate: String?

    private func persistSessionFromLastResponse() throws {
        guard let token = responseTokenCandidate, !token.isEmpty else { throw AccountAPIError.missingSession }
        responseTokenCandidate = nil
        sessionToken = token
        guard SessionTokenKeychain.write(token, account: keychainAccount) else {
            // The active in-memory session remains usable for this app run.
            return
        }
    }

    private func perform<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body? = nil
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let sessionToken {
            request.setValue("mimi_token=\(sessionToken)", forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        updateSessionCandidate(from: http)
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error)
                ?? "服務請求失敗（HTTP \(http.statusCode)）。"
            throw AccountAPIError.http(status: http.statusCode, message: message)
        }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountAPIError.invalidResponse }
    }

    private func perform<Response: Decodable>(path: String, method: String) async throws -> Response {
        try await perform(path: path, method: method, body: Optional<EmptyBody>.none)
    }

    private func endpoint(_ path: String) -> URL {
        var url = baseURL
        for component in path.split(separator: "/") { url.appendPathComponent(String(component)) }
        return url
    }

    private func updateSessionCandidate(from response: HTTPURLResponse) {
        guard let responseURL = response.url else { return }
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        if let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: responseURL).first(where: { $0.name == "mimi_token" }) {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~+-")
            responseTokenCandidate = !cookie.value.isEmpty && cookie.value.unicodeScalars.allSatisfy(allowed.contains) ? cookie.value : nil
        }
    }

    private static func validatedBaseURL(_ raw: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw AccountAPIError.invalidBaseURL("请输入有效的服务地址。")
        }
        let ipv4Parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let isIPv4Loopback: Bool = {
            guard ipv4Parts.count == 4 else { return false }
            guard ipv4Parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return false }
            let octets = ipv4Parts.compactMap(Int.init)
            return octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } && octets[0] == 127
        }()
        let loopback = host == "localhost" || host == "::1" || host == "[::1]" || isIPv4Loopback
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw AccountAPIError.invalidBaseURL("服务地址必须使用 HTTPS；HTTP 只允许 localhost 或 loopback 地址。")
        }
        guard let url = components.url, url.host != nil else {
            throw AccountAPIError.invalidBaseURL("请输入有效的服务地址。")
        }
        return url
    }

    private static func originString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }
}

private struct CredentialsBody: Encodable {
    let account: String
    let password: String
    let nickname: String?
}
private struct PhoneBody: Encodable { let phone: String }
private struct ResetBody: Encodable { let phone: String; let code: String; let password: String }
private struct ArticleBody: Encodable { let title: String; let category: String; let content: String }
private struct EmptyBody: Encodable {}
private struct AuthEnvelope: Decodable { let user: RemoteUser }
private struct UserEnvelope: Decodable { let user: RemoteUser }
private struct FavoritesEnvelope: Decodable { let favorites: [RemoteFavorite] }
private struct SuccessEnvelope: Decodable { let ok: Bool? }
private struct PublishedArticleEnvelope: Decodable { let id: String }
private struct MessageEnvelope: Decodable { let message: String? }
private struct APIErrorEnvelope: Decodable { let error: String? }

private enum SessionTokenKeychain {
    private static let service = "com.mimi.guitar.mac.session"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ token: String, account: String) -> Bool {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
