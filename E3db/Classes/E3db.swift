//
//  E3db.swift
//  E3db
//

import Foundation
import Swish
import Result
import Sodium
import Heimdallr

import ResponseDetective

public class E3db {
    fileprivate let api: Api
    fileprivate let config: Config
    fileprivate let authedClient: APIClient

    private static let debugSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)
        return URLSession(configuration: configuration)
    }()

    fileprivate static let staticClient: APIClient = {
        let session   = E3db.debugSession
        let performer = NetworkRequestPerformer(session: session)
        return APIClient(requestPerformer: performer)
    }()

    public init?(config: Config) {
        guard let url = URL(string: config.baseApiUrl) else { return nil }
        self.api    = Api(baseUrl: url)
        self.config = config

        // TODO: Clean up url handling
        let tokenUrl = "https://dev.e3db.com/v1/auth/token"
        let creds = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let client = HeimdallrHTTPClientURLSession(urlSession: E3db.debugSession)
        let heimdallr = Heimdallr(tokenURL: URL(string: tokenUrl)!, credentials: creds, httpClient: client)
        let performer = AuthedRequestPerformer(authenticator: heimdallr, session: E3db.debugSession)
        self.authedClient = APIClient(requestPerformer: performer)
    }
}

// MARK: Registration

extension E3db {
    public static func register(email: String, findByEmail: Bool, apiUrl: String, completion: @escaping (Result<Config, E3dbError>) -> Void) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        // create key pair
        guard let keyPair = Sodium()?.box.keyPair() else {
            return completion(Result(error: .cryptoError("Could not create key pair.")))
        }

        // send registration request
        let api  = Api(baseUrl: url)
        let pubK = PublicKey(curve25519: keyPair.publicKey.base64URLEncodedString())
        let req  = RegisterRequest(api: api, email: email, publicKey: pubK, findByEmail: findByEmail)
        staticClient.perform(req) { result in
            let resp = result
                .mapError { E3dbError.configError($0.localizedDescription) }
                .map { reg in
                    Config(
                        version: 1,
                        baseApiUrl: api.baseUrl.absoluteString,
                        apiKeyId: reg.apiKeyId,
                        apiSecret: reg.apiSecret,
                        clientId: reg.clientId,
                        clientEmail: email,
                        publicKey: pubK.curve25519,
                        privateKey: keyPair.secretKey.base64URLEncodedString()
                    )
            }
            completion(resp)
        }
    }
}

// MARK: Get Client Info

extension E3db {

    public struct ClientInfoRequest: Request {
        public typealias ResponseObject = ClientInfo
        let api: Api
        let clientId: String

        public func build() -> URLRequest {
            let url = api.url(endpoint: .clients)
                .appendingPathComponent(clientId)
            return URLRequest(url: url)
        }
    }

    // TODO: defaults to current client, probably change later
    public func getClientInfo(clientId: String? = nil, completion: @escaping (Result<ClientInfo, E3dbError>) -> Void) {
        let req = ClientInfoRequest(api: api, clientId: clientId ?? config.clientId)
        authedClient.perform(req) { result in
            // TODO: Better error handling
            completion(result.mapError { _ in E3dbError.error })
        }
    }
}
