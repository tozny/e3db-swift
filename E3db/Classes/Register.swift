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

public struct PublicKey: Encodable, Decodable {
    let curve25519: String

    public func encode() -> JSON {
        return JSON.object([
            "curve25519": curve25519.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<PublicKey> {
        return curry(PublicKey.init)
            <^> j <| "curve25519"
    }
}

public struct RegisterRequest: Request, Encodable {
    public typealias ResponseObject = RegisterResponse
    let api: Api

    let email: String
    let publicKey: PublicKey
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

public struct RegisterResponse: Decodable {
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
