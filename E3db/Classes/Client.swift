//
//  Client.swift
//  E3db
//

import Foundation
import Heimdallr
import Result
import Sodium
import Swish

#if E3DB_LOGGING && DEBUG && canImport(ResponseDetective)
import ResponseDetective
#endif

/// A type that contains either a value of type `T` or an `E3dbError`
public typealias E3dbResult<T> = Result<T, E3dbError>

/// A completion handler that operates on an `E3dbResult<T>` type,
/// used for async callbacks for E3db `Client` methods.
public typealias E3dbCompletion<T> = (E3dbResult<T>) -> Void

/// Main E3db class to handle data operations.
public final class Client {
    internal let api: Api
    internal let config: Config
    internal let authedClient: APIClient
    internal let akCache = NSCache<AkCacheKey, AccessKey>()

    internal static let session: URLSession = {
        #if E3DB_LOGGING && DEBUG && canImport(ResponseDetective)
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)
        return URLSession(configuration: configuration)
        #else
        return URLSession.shared
        #endif
    }()

    internal init(config: Config, scheduler: @escaping Scheduler) {
        self.api    = Api(baseUrl: config.baseApiUrl)
        self.config = config

        let httpClient    = HeimdallrHTTPClientURLSession(urlSession: Client.session)
        let credentials   = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let tokenStore    = OAuthAccessTokenKeychainStore(service: config.clientId.uuidString)
        let heimdallr     = Heimdallr(tokenURL: api.tokenUrl, credentials: credentials, accessTokenStore: tokenStore, httpClient: httpClient)
        let authPerformer = AuthedRequestPerformer(authenticator: heimdallr, session: Client.session)
        self.authedClient = APIClient(requestPerformer: authPerformer, scheduler: scheduler)
    }

    /// Initializer for the E3db client class.
    ///
    /// - SeeAlso: `Client.register(token:clientName:apiUrl:completion:)` and
    ///   `Client.register(token:clientName:publicKey:apiUrl:completion:)` to generate
    ///   the required Config values.
    ///
    /// - Parameter config: A config object with values that have
    ///   already been registered with the E3db service.
    public convenience init(config: Config) {
        self.init(config: config, scheduler: mainQueueScheduler)
    }
}

// MARK: Key Generation

/// A data type holding the public and private keys as
/// Base64URL encoded strings, used for encryption and signing operations.
/// Only the `publicKey` is sent to the E3db service.
public struct KeyPair {

    /// The public key from a generated keypair as a Base64URL encoded string.
    public let publicKey: String

    /// The private key from a generated keypair as a Base64URL encoded string.
    public let secretKey: String
}

extension Client {

    /// A helper function to create a compatible key pair for E3db encryption operations.
    ///
    /// - Note: This method is not required for library use. A key pair is
    ///   generated and stored in the `Config` object returned by the
    ///   `Client.register(token:clientName:apiUrl:completion:)` method.
    ///
    /// - SeeAlso: `Client.register(token:clientName:publicKey:apiUrl:completion:)`
    ///   for supplying your own key for registration.
    ///
    /// - Returns: A key pair containing Base64URL encoded Curve25519 public and private keys.
    public static func generateKeyPair() -> KeyPair? {
        guard let keyPair = Crypto.generateKeyPair(),
              let pubKey  = keyPair.publicKey.base64UrlEncodedString(),
              let privKey = keyPair.secretKey.base64UrlEncodedString()
            else { return nil }
        return KeyPair(publicKey: pubKey, secretKey: privKey)
    }

    /// A helper function to create a compatible key pair for E3db signature operations.
    ///
    /// - Note: This method is not required for library use. A key pair is
    ///   generated and stored in the `Config` object returned by the
    ///   `Client.register(token:clientName:apiUrl:completion:)` method.
    ///
    /// - Returns: A key pair containing Base64URL encoded Ed25519 public and private keys.
    public static func generateSigningKeyPair() -> KeyPair? {
        guard let keyPair = Crypto.generateSigningKeyPair(),
              let pubKey  = keyPair.publicKey.base64UrlEncodedString(),
              let privKey = keyPair.secretKey.base64UrlEncodedString()
            else { return nil }
        return KeyPair(publicKey: pubKey, secretKey: privKey)
    }
}

// MARK: Get Client Info

struct ClientInfo: Decodable {
    let clientId: UUID
    let publicKey: ClientKey
    let signingKey: SigningKey?
    let validated: Bool

    enum CodingKeys: String, CodingKey {
        case clientId   = "client_id"
        case publicKey  = "public_key"
        case signingKey = "signing_key"
        case validated
    }
}

extension Client {
    private struct ClientInfoRequest: E3dbRequest {
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
