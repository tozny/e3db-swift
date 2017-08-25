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

    func encode() -> JSON {
        return JSON.object([
            "name": name.encode(),
            "public_key": publicKey.encode()
        ])
    }
}

struct ClientKey: Ogra.Encodable, Argo.Decodable {
    let curve25519: String

    func encode() -> JSON {
        return JSON.object([
            "curve25519": curve25519.encode()
        ])
    }

    static func decode(_ j: JSON) -> Decoded<ClientKey> {
        return curry(ClientKey.init)
            <^> j <| "curve25519"
    }
}

public struct ClientCredentials: Argo.Decodable {
    public let clientId: UUID
    public let apiKeyId: String
    public let apiSecret: String
    public let name: String
    public let publicKey: String
    public let enabled: Bool

    public static func decode(_ j: JSON) -> Decoded<ClientCredentials> {
        return curry(ClientCredentials.init)
            <^> j <| "client_id"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"
            <*> j <| "name"
            <*> j <| ["public_key", "curve25519"]
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

    /// Register a new client for E3db associated with the account used to create the token. This
    /// method generates the cryptographic keypair and provides it in the resulting Config object.
    ///
    /// - SeeAlso: `generateKeyPair()`
    ///
    /// - Parameters:
    ///   - token: An identifier string associated with an account generated from Tozny's Admin Console
    ///   - clientName: The name to use for the new client
    ///   - apiUrl: The base url used for api calls
    ///   - completion: A completion handler supplying the new client configuration
    public static func register(token: String, clientName: String, apiUrl: String = Api.defaultUrl, completion: @escaping E3dbCompletion<Config>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        // create key pair
        guard let keyPair = Client.generateKeyPair() else {
            return completion(Result(error: .cryptoError("Could not create key pair.")))
        }

        let api    = Api(baseUrl: url)
        let pubK   = ClientKey(curve25519: keyPair.publicKey)
        let client = ClientRequest(name: clientName, publicKey: pubK)
        let req    = RegistrationRequest(api: api, token: token, client: client)
        staticClient.perform(req) { (result) in
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
                        baseApiUrl: api.baseUrl
                    )
            }
            completion(resp)
        }
    }

    public static func register(token: String, clientName: String, publicKey: String, apiUrl: String = Api.defaultUrl, completion: @escaping E3dbCompletion<ClientCredentials>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        let api    = Api(baseUrl: url)
        let pubK   = ClientKey(curve25519: publicKey)
        let client = ClientRequest(name: clientName, publicKey: pubK)
        let req    = RegistrationRequest(api: api, token: token, client: client)
        staticClient.performDefault(req, completion: completion)
    }
}
