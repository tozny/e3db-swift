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

struct RegistrationRequest: Request, Ogra.Encodable {
    public typealias ResponseObject = RegistrationResponse
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
        let url = api.registerUrl()
        var req = URLRequest(url: url)
        return req.asJsonRequest(.POST, payload: encode())
    }
}

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

struct RegistrationResponse: Argo.Decodable {
    let clientId: UUID
    let apiKeyId: String
    let apiSecret: String
    let name: String
    let publicKey: ClientKey
    let enabled: Bool

    public static func decode(_ j: JSON) -> Decoded<RegistrationResponse> {
        return curry(RegistrationResponse.init)
            <^> j <| "client_id"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"
            <*> j <| "name"
            <*> j <| "public_key"
            <*> j <| "enabled"
    }
}

extension E3db {
    public static func register(token: String, clientName: String, apiUrl: String = Api.defaultUrl, completion: @escaping E3dbCompletion<Config>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        // create key pair
        guard let keyPair = Crypto.generateKeyPair() else {
            return completion(Result(error: .cryptoError("Could not create key pair.")))
        }

        let api    = Api(baseUrl: url)
        let pubK   = ClientKey(curve25519: keyPair.publicKey.base64URLEncodedString())
        let client = ClientRequest(name: clientName, publicKey: pubK)
        let req    = RegistrationRequest(api: api, token: token, client: client)
        staticClient.perform(req) { (result) in
            let resp = result
                .mapError(E3dbError.init)
                .map { registration in
                    Config(
                        version: 1,
                        baseApiUrl: api.baseUrl,
                        apiKeyId: registration.apiKeyId,
                        apiSecret: registration.apiSecret,
                        clientId: registration.clientId,
                        clientName: clientName,
                        publicKey: pubK.curve25519,
                        privateKey: keyPair.secretKey.base64URLEncodedString()
                    )
            }
            completion(resp)
        }
    }
}
