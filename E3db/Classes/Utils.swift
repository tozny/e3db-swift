//
//  Utils.swift
//  E3db
//

import Foundation
//import ToznyHeimdallr
import Result
import Sodium
import Swish

// Allows customizable response parsing
protocol E3dbRequest: Request {
    associatedtype ResponseObject
}

let kStaticJsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .formatted(Formatter.iso8601)
    return encoder
}()

let kStaticJsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(Formatter.iso8601)
    return decoder
}()

// wrapper to align signable types
struct AnySignable: Signable {
    let wrapped: Signable

    init<S: Signable>(_ base: S) {
        self.wrapped = base
    }

    func serialized() -> String {
        return wrapped.serialized()
    }
}

/// Possible errors encountered from E3db operations
public enum E3dbError: Error {

    /// A crypto operation failed
    case cryptoError(String)

    /// Configuration failed
    case configError(String)

    /// A network operation failed
    case networkError(String)

    /// encoding failed
    case encodingError(String)

    /// JSON parsing failed
    case jsonError(expected: String, actual: String)

    /// An API request encountered an error
    case apiError(code: Int, message: String)

    /// Encapsulate general errors that need additional context
    case generalError(String)

    init(swishError: SwishError) {
        switch swishError {
        case .decodingError(DecodingError.dataCorrupted(let ctx)):
            self = .jsonError(expected: ctx.codingPath.map { $0.stringValue }.joined(separator: "."), actual: "corrupted")
        case let .decodingError(DecodingError.keyNotFound(key, _)):
            self = .jsonError(expected: key.stringValue, actual: "")
        case let .decodingError(DecodingError.typeMismatch(any, ctx)), let .decodingError(DecodingError.valueNotFound(any, ctx)):
            self = .jsonError(expected: ctx.codingPath.map { $0.stringValue }.joined(separator: "."), actual: "\(any)")
        case .decodingError:
            self = .jsonError(expected: "", actual: swishError.errorDescription ?? "Failed to decode json")
        case .serverError(let code, data: _) where code == 401 || code == 403:
            self = .apiError(code: code, message: "Unauthorized")
        case .serverError(code: 404, data: _):
            self = .apiError(code: 404, message: "Requested item not found")
        case .serverError(code: 409, data: _):
            self = .apiError(code: 409, message: "Existing item cannot be modified")
        case .serverError(code: let code, data: _):
            self = .apiError(code: code, message: swishError.errorDescription ?? "Failed request")
        case .urlSessionError:
            self = .networkError(swishError.errorDescription ?? "Failed request")
        }
    }

    /// Get a human-readable context for the error.
    public var description: String {
        switch self {
        case .cryptoError(let msg), .configError(let msg), .networkError(let msg), .encodingError(let msg), .generalError(let msg):
            return msg
        case let .jsonError(exp, act):
            return "Failed to decode response. \(exp + act)"
        case let .apiError(code, msg):
            return "API Error (\(code)): \(msg)"
        }
    }
}

struct Api {
    enum Endpoint: String {
        case records
        case clients
        case accessKeys = "access_keys"
        case search
        case policy
        case files
    }

    static let defaultUrl   = "https://api.e3db.com/"
    static let decoder: JSONDecoder = {
        let customDecoder = JSONDecoder()
        customDecoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
        return customDecoder
    }()
    private let version     = "v1"
    private let pdsService  = "storage"
    private let authService = "auth"
    private let acctService = "account"

    let baseUrl: URL
    let tokenUrl: URL
    let registerUrl: URL

    init(baseUrl: URL) {
        self.baseUrl = baseUrl
        self.tokenUrl = baseUrl / version / authService / "token"
        self.registerUrl = baseUrl / version / acctService / "e3db" / "clients" / "register"
    }

    func url(endpoint: Endpoint) -> URL {
        return baseUrl / version / pdsService / endpoint.rawValue
    }
}

struct AuthedRequestPerformer {
    let authenticator: Heimdallr
    let session: URLSession
}

extension AuthedRequestPerformer: RequestPerformer {
    typealias ResponseHandler = (Result<HTTPResponse, SwishError>) -> Void

    @discardableResult
    func perform(_ request: URLRequest, completionHandler: @escaping ResponseHandler) -> URLSessionDataTask {
        if authenticator.hasAccessToken {
            authenticator.authenticateRequest(request) { result in
                if case .success(let req) = result {
                    self.perform(authedRequest: req, completionHandler: completionHandler)
                } else {
                    // Authentication failed, clearing token to retry...
                    self.authenticator.clearAccessToken()
                    self.perform(request, completionHandler: completionHandler)
                }
            }
        } else {
            // No token found, requesting auth token...
            requestAccessToken(request, completionHandler: completionHandler)
        }

        // unused, artifact of Swish
        return URLSessionDataTask()
    }

    private func requestAccessToken(_ request: URLRequest, completionHandler: @escaping ResponseHandler) {
        authenticator.requestAccessToken(grantType: "client_credentials", parameters: ["grant_type": "client_credentials"]) { result in
            guard case .success = result else {
                // Failed to request token
                return completionHandler(.failure(.serverError(code: 401, data: nil)))
            }

            // Got token, authenticating request...
            self.authenticateRequest(request, completionHandler: completionHandler)
        }
    }

    private func authenticateRequest(_ request: URLRequest, completionHandler: @escaping ResponseHandler) {
        authenticator.authenticateRequest(request) { result in
            guard case .success(let req) = result else {
                // Failed to authenticate request
                return completionHandler(.failure(.serverError(code: 422, data: nil)))
            }

            // Added auth to the request, now performing it...
            self.perform(authedRequest: req, completionHandler: completionHandler)
        }
    }

    private func perform(authedRequest: URLRequest, completionHandler: @escaping ResponseHandler) {
        // Must capitalize "Bearer" since the Heimdallr lib chooses
        // to use exactly what is returned from the token request.
        // https://github.com/trivago/Heimdallr.swift/pull/59
        //
        // RFC 6749 suggests that the token type is case insensitive,
        // https://tools.ietf.org/html/rfc6749#section-5.1 while
        // RFC 6750 suggests the Authorization header with "Bearer" prefix
        // is capitalized, https://tools.ietf.org/html/rfc6750#section-2.1
        // ¯\_(ツ)_/¯
        var req  = authedRequest
        let auth = req.allHTTPHeaderFields?["Authorization"]?.replacingOccurrences(of: "bearer", with: "Bearer")
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        let task = session.dataTask(with: req) { data, response, error in
            switch (data, response, error) {
            case let (_, resp as HTTPURLResponse, .some(err)):
                completionHandler(.failure(.urlSessionError(err, response: resp)))
            case let (.some(body), resp as HTTPURLResponse, _):
                let httpResp = HTTPResponse(data: body, response: resp)
                completionHandler(.success(httpResp))
            default:
                completionHandler(.failure(.serverError(code: 400, data: nil)))
            }
        }
        task.resume()
    }
}
