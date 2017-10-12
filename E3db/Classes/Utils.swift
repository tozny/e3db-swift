//
//  Utils.swift
//  E3db
//

import Foundation
import Sodium
import Result
import Argo
import Swish
import Heimdallr

/// Possible errors encountered from E3db operations
public enum E3dbError: Swift.Error {

    /// A crypto operation failed
    case cryptoError(String)

    /// Configuration failed
    case configError(String)

    /// A network operation failed
    case networkError(String)

    /// JSON parsing failed
    case jsonError(expected: String, actual: String)

    /// An API request encountered an error
    case apiError(code: Int, message: String)

    internal init(swishError: SwishError) {
        switch swishError {
        case let .argoError(.typeMismatch(exp, act)):
            self = .jsonError(expected: "Expected: \(exp). ", actual: "Actual: \(act).")
        case .argoError(.missingKey(let key)):
            self = .jsonError(expected: "Expected: \(key). ", actual: "Actual: (key not found).")
        case .argoError(let err):
            self = .jsonError(expected: "", actual: err.description)
        case .serverError(let code, data: _) where code == 401 || code == 403:
            self = .apiError(code: code, message: "Unauthorized")
        case .serverError(code: 404, data: _):
            self = .apiError(code: 404, message: "Requested item not found")
        case .serverError(code: 409, data: _):
            self = .apiError(code: 409, message: "Existing item cannot be modified")
        case .serverError(code: let code, data: _):
            self = .apiError(code: code, message: swishError.errorDescription ?? "Failed request")
        case .deserializationError, .parseError, .urlSessionError:
            self = .networkError(swishError.errorDescription ?? "Failed request")
        }
    }

    /// Get a human-readable context for the error.
    public var description: String {
        switch self {
        case .cryptoError(let msg), .configError(let msg), .networkError(let msg):
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
    }

    static let defaultUrl   = "https://api.e3db.com/"
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

struct AkCacheKey: Hashable {
    let writerId: UUID
    let userId: UUID
    let recordType: String

    var hashValue: Int {
        return [writerId, userId]
            .map { $0.uuidString }
            .reduce(recordType, +)
            .hashValue
    }

    static func == (lhs: AkCacheKey, rhs: AkCacheKey) -> Bool {
        return lhs.writerId == rhs.writerId &&
            lhs.userId == rhs.userId &&
            lhs.recordType == rhs.recordType
    }
}

struct AuthedRequestPerformer {
    let session: URLSession
    let authenticator: Heimdallr

    init(authenticator: Heimdallr, session: URLSession = .shared) {
        self.session = session
        self.authenticator = authenticator
    }
}

extension AuthedRequestPerformer: RequestPerformer {
    typealias ResponseHandler = (Result<HTTPResponse, SwishError>) -> Void

    @discardableResult
    internal func perform(_ request: URLRequest, completionHandler: @escaping ResponseHandler) -> URLSessionDataTask {
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
            if let error = error {
                completionHandler(.failure(.urlSessionError(error)))
            } else {
                let resp = HTTPResponse(data: data, response: response)
                completionHandler(.success(resp))
            }
        }
        task.resume()
    }
}
