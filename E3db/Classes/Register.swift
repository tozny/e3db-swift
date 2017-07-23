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

public struct ClientKey: Ogra.Encodable, Argo.Decodable {
    let curve25519: String

    public func encode() -> JSON {
        return JSON.object([
            "curve25519": curve25519.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<ClientKey> {
        return curry(ClientKey.init)
            <^> j <| "curve25519"
    }
}

public struct RegisterRequest: Request, Ogra.Encodable {
    public typealias ResponseObject = RegisterResponse
    let api: Api

    let email: String
    let publicKey: ClientKey
    let findByEmail: Bool

    public func encode() -> JSON {
        return JSON.object([
            "email": email.encode(),
            "public_key": publicKey.encode(),
            "find_by_email": findByEmail.encode()
        ])
    }

    public func build() -> URLRequest {
        let url = api.url(endpoint: .clients)
        var req = URLRequest(url: url)
        return req.asJsonRequest(.POST, payload: encode())
    }
}

public struct RegisterResponse: Argo.Decodable {
    let clientId: String
    let apiKeyId: String
    let apiSecret: String

    public static func decode(_ j: JSON) -> Decoded<RegisterResponse> {
        return curry(RegisterResponse.init)
            <^> j <| "client_id"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"
    }
}

extension E3db {
    public static func register(email: String, findByEmail: Bool, apiUrl: String, completion: @escaping E3dbCompletion<Config>) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        // create key pair
        guard let keyPair = Crypto.generateKeyPair() else {
            return completion(Result(error: .cryptoError("Could not create key pair.")))
        }

        // send registration request
        let api  = Api(baseUrl: url)
        let pubK = ClientKey(curve25519: keyPair.publicKey.base64URLEncodedString())
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
