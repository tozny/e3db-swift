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

public enum E3dbError: Swift.Error {
    case cryptoError(String)        // Message
    case configError(String)        // Message
    case jsonError(String, String)  // (Expected, Actual)
    case apiError(Int, String)      // (StatusCode, Message)
    case error
}

struct Api {
    let baseUrl: URL

    private let version   = "v1"
    private let pdsPath   = "storage"
    private let authPath  = "auth"
    private let tokenPath = "token"

    func url(endpoint: Endpoint) -> URL {
        return baseUrl
            .appendingPathComponent(version)
            .appendingPathComponent(pdsPath)
            .appendingPathComponent(endpoint.rawValue)
    }

    func tokenUrl() -> URL {
        return baseUrl
            .appendingPathComponent(version)
            .appendingPathComponent(authPath)
            .appendingPathComponent(tokenPath)
    }
}

enum Endpoint: String {
    case records
    case clients
    case accessKeys = "access_keys"
    case search
}

struct AkCacheKey: Hashable {
    let writerId: String
    let readerId: String
    let recordType: String

    var hashValue: Int {
        return (writerId + readerId + recordType).hashValue
    }

    static func == (lhs: AkCacheKey, rhs: AkCacheKey) -> Bool {
        return lhs.writerId == rhs.writerId &&
            lhs.readerId == rhs.readerId &&
            lhs.recordType == rhs.recordType
    }
}

struct AuthedRequestPerformer {
    fileprivate let session: URLSession
    fileprivate let authenticator: Heimdallr

    public init(authenticator: Heimdallr, session: URLSession = .shared) {
        self.session = session
        self.authenticator = authenticator
    }
}

extension AuthedRequestPerformer: RequestPerformer {

    @discardableResult
    func perform(_ request: URLRequest, completionHandler: @escaping (Result<HTTPResponse, SwishError>) -> Void) -> URLSessionDataTask {
        if authenticator.hasAccessToken {
            authenticator.authenticateRequest(request) { (result) in
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

    private func requestAccessToken(_ request: URLRequest, completionHandler: @escaping (Result<HTTPResponse, SwishError>) -> Void) {
        authenticator.requestAccessToken(grantType: "client_credentials", parameters: ["grant_type": "client_credentials"]) { (result) in
            guard case .success = result else {
                // Failed to request token
                return completionHandler(.failure(.serverError(code: 401, data: nil)))
            }

            // Got token, authenticating request...
            self.authenticateRequest(request, completionHandler: completionHandler)
        }
    }

    private func authenticateRequest(_ request: URLRequest, completionHandler: @escaping (Result<HTTPResponse, SwishError>) -> Void) {
        authenticator.authenticateRequest(request) { (result) in
            guard case .success(let req) = result else {
                // Failed to authenticate request
                return completionHandler(.failure(.serverError(code: 422, data: nil)))
            }

            // Added auth to the request, now performing it...
            self.perform(authedRequest: req, completionHandler: completionHandler)
        }
    }

    private func perform(authedRequest: URLRequest, completionHandler: @escaping (Result<HTTPResponse, SwishError>) -> Void) {
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
        let auth = req.allHTTPHeaderFields?["Authorization"]?.capitalizedFirst()
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        let task = self.session.dataTask(with: req) { data, response, error in
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
