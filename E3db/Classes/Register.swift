//
//  Register.swift
//  E3db
//

import Foundation
import Sodium
import ToznySwish

struct ClientRequest: Encodable {
    let name: String
    let publicKey: ClientKey
    let signingKey: SigningKey

    enum CodingKeys: String, CodingKey {
        case name
        case publicKey  = "public_key"
        case signingKey = "signing_key"
    }
}

/// A type that holds a public encryption key
public struct ClientKey: Codable {

    /// The Base64URL encoded value for the public encryption key
    let curve25519: String
}

/// A type that holds a public signing key
public struct SigningKey: Codable {

    /// The Base64URL encoded value for the public signing key
    let ed25519: String
}

/// A type that contains the registration response info
public struct ClientCredentials: Decodable {

    /// An identifier for the client
    public let clientId: UUID

    /// An identifier for the key for use with the E3db service
    public let apiKeyId: String

    /// A secret to use with the E3db service
    public let apiSecret: String

    /// The name used during client registration
    public let name: String

    /// The public key registered with the E3db service and used for encryption
    public let publicKey: String

    /// The signing public key registered with the E3db service and used for signature operations
    public let signingKey: String

    /// A flag indicating whether this client is active
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case clientId   = "client_id"
        case apiKeyId   = "api_key_id"
        case apiSecret  = "api_secret"
        case name
        case enabled
        case publicKey  = "public_key"
        case signingKey = "signing_key"
    }

    private enum PublicKeyCodingKeys: String, CodingKey {
        case curve25519
    }

    private enum SigningKeyCodingKeys: String, CodingKey {
        case ed25519
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientId   = try values.decode(UUID.self, forKey: .clientId)
        apiKeyId   = try values.decode(String.self, forKey: .apiKeyId)
        apiSecret  = try values.decode(String.self, forKey: .apiSecret)
        name       = try values.decode(String.self, forKey: .name)
        enabled    = try values.decode(Bool.self, forKey: .enabled)
        let pubKey = try values.nestedContainer(keyedBy: PublicKeyCodingKeys.self, forKey: .publicKey)
        publicKey  = try pubKey.decode(String.self, forKey: .curve25519)
        let sigKey = try values.nestedContainer(keyedBy: SigningKeyCodingKeys.self, forKey: .signingKey)
        signingKey = try sigKey.decode(String.self, forKey: .ed25519)
    }
}

// MARK: Registration

extension Client {
    private struct RegistrationRequest: E3dbRequest, Encodable {
        typealias ResponseObject = ClientCredentials
        let api: Api

        let token: String
        let client: ClientRequest

        enum CodingKeys: String, CodingKey {
            case token, client
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(token, forKey: .token)
            try container.encode(client, forKey: .client)
        }

        func build() -> URLRequest {
            let url = api.registerUrl
            var req = URLRequest(url: url)
            return req.asJsonRequest(.post, payload: self)
        }
    }

    private static func generateRegistrationRequest(token: String, clientName: String, publicKey: String, signingKey: String, apiUrl: URL) -> RegistrationRequest {
        let api       = Api(baseUrl: apiUrl)
        let pubKey    = ClientKey(curve25519: publicKey)
        let sigKey    = SigningKey(ed25519: signingKey)
        let clientReq = ClientRequest(name: clientName, publicKey: pubKey, signingKey: sigKey)
        return RegistrationRequest(api: api, token: token, client: clientReq)
    }

    private static func publicClient(urlSession: URLSession, scheduler: @escaping Scheduler) -> APIClient {
        let performer = NetworkRequestPerformer(session: urlSession)
        return APIClient(requestPerformer: performer, scheduler: scheduler)
    }

    static func register(token: String, clientName: String, urlSession: URLSession, apiUrl: String? = nil, scheduler: @escaping Scheduler, completion: @escaping E3dbCompletion<Config>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl ?? Api.defaultUrl) else {
            return completion(.failure(.configError("Invalid apiUrl: \(apiUrl ?? "")")))
        }

        // create encryption key pair
        guard let keyPair = Client.generateKeyPair() else {
            return completion(.failure(.cryptoError("Failed to create encryption key pair")))
        }

        // create signing key pair
        guard let signingKeyPair = Client.generateSigningKeyPair() else {
            return completion(.failure(.cryptoError("Failed to create signing key pair")))
        }

        let regRequest = generateRegistrationRequest(token: token, clientName: clientName, publicKey: keyPair.publicKey, signingKey: signingKeyPair.publicKey, apiUrl: url)
        let pubClient  = publicClient(urlSession: urlSession, scheduler: scheduler)
        pubClient.perform(regRequest) { result in
            let resp = result
                .mapError(E3dbError.init)
                .map { creds in
                    Config(
                        clientName: clientName,
                        clientId: creds.clientId,
                        apiKeyId: creds.apiKeyId,
                        apiSecret: creds.apiSecret,
                        publicKey: keyPair.publicKey,
                        privateKey: keyPair.secretKey,
                        baseApiUrl: url,
                        publicSigKey: signingKeyPair.publicKey,
                        privateSigKey: signingKeyPair.secretKey
                    )
                }
            completion(resp)
        }
    }

    /// Provide registration information to the E3db service to create a new client
    /// associated with a particular account. The token provided must be generated from
    /// Tozny's [Dashboard](https://dashboard.tozny.com) to register successfully.
    ///
    /// - Note: This registration variant generates the keypair for the client.
    ///
    /// - SeeAlso: The `register(token:clientName:publicKey:signingKey:urlSession:apiUrl:completion:)` variant
    ///   of this method allows the caller to provide their own public key.
    ///
    /// - Parameters:
    ///   - token: An opaque value associated with an account and generated by the Tozny dashboard
    ///   - clientName: A name to give this client for registration
    ///   - urlSession: The URLSession to use for the client. Defaults to `URLSession.shared`
    ///   - apiUrl: The base URL for the E3DB service, uses production API URL if none provided here
    ///   - completion: A handler to call when this operation completes to provide a complete `Config`
    public static func register(token: String, clientName: String, urlSession: URLSession = .shared, apiUrl: String? = nil, completion: @escaping E3dbCompletion<Config>) {
        register(token: token, clientName: clientName, urlSession: urlSession, apiUrl: apiUrl, scheduler: mainQueueScheduler, completion: completion)
    }

    /// Provide registration information to the E3db service to create a new client
    /// associated with a particular account. The token provided must be generated from
    /// Tozny's [Dashboard](https://dashboard.tozny.com) to register successfully.
    ///
    /// - Note: This registration variant does not generate the keypair for the client.
    ///
    /// - SeeAlso: The `register(token:clientName:urlSession:apiUrl:completion:)` variant
    ///   of this method generates the keypair for the caller.
    ///
    /// - Parameters:
    ///   - token: An opaque value associated with an account and generated in the Tozny dashboard
    ///   - clientName: A name to give this client for registration
    ///   - publicKey: The public key to register with the E3db service and use for encryption operations
    ///   - signingKey: The public key to register with the E3db service and use for signing operations
    ///   - urlSession: The URLSession to use for the client. Defaults to `URLSession.shared`
    ///   - apiUrl: The base URL for the E3DB service, uses production API URL if none provided here
    ///   - completion: A handler to call when this operation completes to provide `ClientCredentials`
    ///     used to build a `Config` object for initializing an E3db `Client`
    public static func register(token: String, clientName: String, publicKey: String, signingKey: String, urlSession: URLSession = .shared, apiUrl: String? = nil, completion: @escaping E3dbCompletion<ClientCredentials>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl ?? Api.defaultUrl) else {
            return completion(.failure(.configError("Invalid apiUrl: \(apiUrl ?? "")")))
        }

        let regRequest = generateRegistrationRequest(token: token, clientName: clientName, publicKey: publicKey, signingKey: signingKey, apiUrl: url)
        let pubClient  = publicClient(urlSession: urlSession, scheduler: mainQueueScheduler)
        pubClient.performDefault(regRequest, completion: completion)
    }
}
