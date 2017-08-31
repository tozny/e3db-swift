//
//  Client.swift
//  E3db
//

import Foundation
import Swish
import Result
import Sodium
import Heimdallr

import Argo
import Ogra
import Curry
import Runes

#if E3DB_LOGGING
import ResponseDetective
#endif

/// A type that contains either a value of type `T` or an `E3dbError`
public typealias E3dbResult<T>     = Result<T, E3dbError>

/// A completion handler that operates on an `E3dbResult<T>` type,
/// used for async callbacks for E3db `Client` methods.
public typealias E3dbCompletion<T> = (E3dbResult<T>) -> Void

/// Main E3db class to handle data operations.
public final class Client {
    internal let api: Api
    internal let config: Config
    internal let authedClient: APIClient

    internal static let session: URLSession = {
        #if E3DB_LOGGING
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)
        return URLSession(configuration: configuration)
        #else
        return URLSession.shared
        #endif
    }()

    internal static var akCache = [AkCacheKey: AccessKey]()

    /// Initializer for the E3db client class.
    ///
    /// - SeeAlso: `Client.register(token:clientName:apiUrl:completion:)` and
    ///   `Client.register(token:clientName:publicKey:apiUrl:completion:)` to generate
    ///   the required Config values.
    ///
    /// - Parameter config: A config object with values that have
    ///   already been registered with the E3db service.
    public init(config: Config) {
        self.api    = Api(baseUrl: config.baseApiUrl)
        self.config = config

        let httpClient    = HeimdallrHTTPClientURLSession(urlSession: Client.session)
        let credentials   = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let tokenStore    = OAuthAccessTokenKeychainStore(service: config.clientId.uuidString)
        let heimdallr     = Heimdallr(tokenURL: api.tokenUrl, credentials: credentials, accessTokenStore: tokenStore, httpClient: httpClient)
        let authPerformer = AuthedRequestPerformer(authenticator: heimdallr, session: Client.session)
        self.authedClient = APIClient(requestPerformer: authPerformer)
    }
}

// MARK: Key Generation

/// A data type holding the public and private Curve25519 keys as
/// Base64URL encoded strings, used for encryption operations.
/// Only the `publicKey` is sent to the E3db service.
public struct KeyPair {

    /// The public Curve25519 key from a generated keypair as a Base64URL encoded string.
    public let publicKey: String

    /// The private Curve25519 key from a generated keypair as a Base64URL encoded string.
    public let secretKey: String
}

extension Client {

    /// A helper function to create a compatible key pair for E3db operations.
    ///
    /// - Note: This method is not required for library use. A key pair is
    ///   generated and stored in the `Config` object returned by the
    ///   `Client.register(token:clientName:apiUrl:completion:)` method.
    ///
    /// - SeeAlso: `Client.register(token:clientName:publicKey:apiUrl:completion:)`
    ///   for supplying your own key for registration.
    ///
    /// - Returns: A key pair containing Base64URL encoded public and private keys.
    public static func generateKeyPair() -> KeyPair? {
        guard let keyPair = Crypto.generateKeyPair() else { return nil }
        let pubKey  = keyPair.publicKey.base64URLEncodedString()
        let privKey = keyPair.secretKey.base64URLEncodedString()
        return KeyPair(publicKey: pubKey, secretKey: privKey)
    }
}

// MARK: Get Client Info

struct ClientInfo: Argo.Decodable {
    let clientId: UUID
    let publicKey: ClientKey
    let validated: Bool

    static func decode(_ j: JSON) -> Decoded<ClientInfo> {
        return curry(ClientInfo.init)
            <^> j <| "client_id"
            <*> j <| "public_key"
            <*> j <| "validated"
    }
}

extension Client {
    private struct ClientInfoRequest: Request {
        typealias ResponseObject = ClientInfo
        let api: Api
        let clientId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .clients) / clientId.uuidString
            return URLRequest(url: url)
        }
    }

    func getClientInfo(clientId: UUID? = nil, completion: @escaping E3dbCompletion<ClientInfo>) {
        let req = ClientInfoRequest(api: api, clientId: clientId ?? config.clientId)
        authedClient.performDefault(req, completion: completion)
    }
}

extension Client {
    private struct LookupRequest: Request {
        typealias ResponseObject = ClientInfo
        let api: Api
        let email: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .clients) / ("find" + "?email=" + email)
            return URLRequest(url: url)
        }
    }

    func getClientInfo(email: String, completion: @escaping E3dbCompletion<ClientInfo>) {
        let req = LookupRequest(api: api, email: email)
        authedClient.performDefault(req, completion: completion)
    }
}

