//
//  Register.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes
import Result
import Sodium

struct ClientRequest: Ogra.Encodable {
    let name: String
    let publicKey: ClientKey
    let signingKey: SigningKey

    func encode() -> JSON {
        return JSON.object([
            "name": name.encode(),
            "public_key": publicKey.encode(),
            "signing_key": signingKey.encode()
        ])
    }
}

/// A type that holds a public encryption key
public struct ClientKey: Swift.Codable {

    /// The Base64URL encoded value for the public encryption key
    let curve25519: String
}

/// :nodoc:
extension ClientKey: Ogra.Encodable, Argo.Decodable {
    public func encode() -> JSON {
        return JSON.object([
            "curve25519": curve25519.encode()
        ])
    }

    static public func decode(_ j: JSON) -> Decoded<ClientKey> {
        return curry(ClientKey.init)
            <^> j <| "curve25519"
    }
}

/// A type that holds a public signing key
public struct SigningKey: Swift.Codable {

    /// The Base64URL encoded value for the public signing key
    let ed25519: String
}

/// :nodoc:
extension SigningKey: Ogra.Encodable, Argo.Decodable {
    public func encode() -> JSON {
        return JSON.object([
            "ed25519": ed25519.encode()
        ])
    }

    static public func decode(_ j: JSON) -> Decoded<SigningKey> {
        return curry(SigningKey.init)
            <^> j <| "ed25519"
    }
}

/// A type that contains the registration response info
public struct ClientCredentials {

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
}

/// :nodoc:
extension ClientCredentials: Argo.Decodable {
    public static func decode(_ j: JSON) -> Decoded<ClientCredentials> {
        return curry(ClientCredentials.init)
            <^> j <| "client_id"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"
            <*> j <| "name"
            <*> j <| ["public_key", "curve25519"]
            <*> j <| ["signing_key", "ed25519"]
            <*> j <| "enabled"
    }
}

// MARK: Registration

extension Client {
    private struct RegistrationRequest: Request, Ogra.Encodable {
        typealias ResponseObject = ClientCredentials
        let api: Api

        let token: String
        let client: ClientRequest

        func encode() -> JSON {
            return JSON.object([
                "token": token.encode(),
                "client": client.encode()
            ])
        }

        func build() -> URLRequest {
            let url = api.registerUrl
            var req = URLRequest(url: url)
            return req.asJsonRequest(.POST, payload: encode())
        }
    }

    static func register(token: String, clientName: String, apiUrl: String? = nil, scheduler: @escaping Scheduler, completion: @escaping E3dbCompletion<Config>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl ?? Api.defaultUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl ?? "")")))
        }

        // create encryption key pair
        guard let keyPair = Client.generateKeyPair() else {
            return completion(Result(error: .cryptoError("Failed to create encryption key pair")))
        }

        // create signing key pair
        guard let signingKeyPair = Client.generateSigningKeyPair() else {
            return completion(Result(error: .cryptoError("Failed to create signing key pair")))
        }

        let api       = Api(baseUrl: url)
        let pubKey    = ClientKey(curve25519: keyPair.publicKey)
        let sigKey    = SigningKey(ed25519: signingKeyPair.publicKey)
        let clientReq = ClientRequest(name: clientName, publicKey: pubKey, signingKey: sigKey)
        let regReq    = RegistrationRequest(api: api, token: token, client: clientReq)
        let performer = NetworkRequestPerformer(session: session)
        let client    = APIClient(requestPerformer: performer, scheduler: scheduler)
        client.perform(regReq) { result in
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
                        baseApiUrl: api.baseUrl,
                        publicSigKey: signingKeyPair.publicKey,
                        privateSigKey: signingKeyPair.secretKey
                    )
            }
            completion(resp)
        }
    }

    /// Provide registration information to the E3db service to create a new client
    /// associated with a particular account. The token provided must be generated from
    /// Tozny's [InnoVault Console](https://console.tozny.com) to register successfully.
    ///
    /// - Note: This registration variant generates the keypair for the client.
    ///
    /// - SeeAlso: The `register(token:clientName:publicKey:apiUrl:completion:)` variant
    ///   of this method allows the caller to provide their own public key.
    ///
    /// - Parameters:
    ///   - token: An opaque value associated with an account and generated by the InnoVault Console
    ///   - clientName: A name to give this client for registration
    ///   - apiUrl: The base URL for the E3DB service, uses production API URL if none provided here
    ///   - completion: A handler to call when this operation completes to provide a complete `Config`
    public static func register(token: String, clientName: String, apiUrl: String? = nil, completion: @escaping E3dbCompletion<Config>) {
        register(token: token, clientName: clientName, apiUrl: apiUrl, scheduler: mainQueueScheduler, completion: completion)
    }

    /// Provide registration information to the E3db service to create a new client
    /// associated with a particular account. The token provided must be generated from
    /// Tozny's [InnoVault Console](https://console.tozny.com) to register successfully.
    ///
    /// - Note: This registration variant does not generate the keypair for the client.
    ///
    /// - SeeAlso: The `register(token:clientName:apiUrl:completion:)` variant
    ///   of this method generates the keypair for the caller.
    ///
    /// - Parameters:
    ///   - token: An opaque value associated with an account and generated the InnoVault Console
    ///   - clientName: A name to give this client for registration
    ///   - publicKey: The public key to register with the E3db service and use for encryption operations
    ///   - signingKey: The public key to register with the E3db service and use for signing operations
    ///   - apiUrl: The base URL for the E3DB service, uses production API URL if none provided here
    ///   - completion: A handler to call when this operation completes to provide `ClientCredentials`
    ///     used to build a `Config` object for initializing an E3db `Client`
    public static func register(token: String, clientName: String, publicKey: String, signingKey: String, apiUrl: String? = nil, completion: @escaping E3dbCompletion<ClientCredentials>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl ?? Api.defaultUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl ?? "")")))
        }

        let api       = Api(baseUrl: url)
        let pubKey    = ClientKey(curve25519: publicKey)
        let sigKey    = SigningKey(ed25519: signingKey)
        let clientReq = ClientRequest(name: clientName, publicKey: pubKey, signingKey: sigKey)
        let regReq    = RegistrationRequest(api: api, token: token, client: clientReq)
        let performer = NetworkRequestPerformer(session: session)
        let client    = APIClient(requestPerformer: performer)
        client.performDefault(regReq, completion: completion)
    }
}
