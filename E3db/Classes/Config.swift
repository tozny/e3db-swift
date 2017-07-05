//
//  Config.swift
//  E3db
//


import Foundation
import Argo
import Ogra
import Curry
import Runes
import Valet

public struct Config {
    let version: Int
    let baseApiUrl: String
    let apiKeyId: String
    let apiSecret: String
    let clientId: String
    let clientEmail: String
    let publicKey: String
    let privateKey: String
}

// MARK: Json
extension Config: Encodable, Decodable {
    public func encode() -> JSON {
        return JSON.object([
            "version": version.encode(),
            "base_api_url": baseApiUrl.encode(),
            "api_key_id": apiKeyId.encode(),
            "api_secret": apiSecret.encode(),
            "client_id": clientId.encode(),
            "client_email": clientEmail.encode(),
            "public_key": publicKey.encode(),
            "private_key": privateKey.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<Config> {
        return curry(Config.init)
            <^> j <| "version"
            <*> j <| "base_api_url"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"
            <*> j <| "client_id"
            <*> j <| "client_email"
            <*> j <| "public_key"
            <*> j <| "private_key"
    }
}

private let defaultProfileName = "com.tozny.e3db.sdk.defaultProfile"

public extension Config {

    public func save(profile: String = defaultProfileName) -> Bool {
        guard let valet  = VALSecureEnclaveValet(identifier: profile, accessControl: .userPresence),
              let config = try? JSONSerialization.data(withJSONObject: self.encode().JSONObject(), options: [])
            else { return false }

        return valet.setObject(config, forKey: profile)
    }


    public init?(loadProfile: String = defaultProfileName) {
        guard let valet = VALSecureEnclaveValet(identifier: loadProfile, accessControl: .userPresence),
              let data  = valet.object(forKey: loadProfile, userPrompt: "Unlock to load profile"),
              let json  = try? JSONSerialization.jsonObject(with: data, options: []),
         case let .success(config) = Config.decode(JSON(json))
            else { return nil }

        self = config
    }
}
