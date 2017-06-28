//
//  Register.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Curry
import Runes

public struct PublicKey: Encodable, Decodable {
    let curve25519: String

    var asJson: JsonPayload {
        return ["curve25519": curve25519]
    }

    public static func decode(_ j: JSON) -> Decoded<PublicKey> {
        return curry(PublicKey.init)
            <^> j <| "curve25519"
    }
}

public struct RegisterRequest: Request, Encodable {
    public typealias ResponseObject = RegisterResponse

    let email: String
    let publicKey: PublicKey
    let findByEmail: Bool

    var asJson: JsonPayload {
        return [
            "email": email,
            "public_key": publicKey.asJson,
            "find_by_email": findByEmail
        ]
    }

    public func build() -> URLRequest {
        let url = Endpoints.clients.url()
        var req = URLRequest(url: url)
        return req.setJsonPost(payload: asJson)
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

