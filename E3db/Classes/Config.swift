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
    public let clientName: String
    public let clientId: UUID
    public let apiKeyId: String
    public let apiSecret: String
    public let publicKey: String
    public let privateKey: String
    public let baseApiUrl: URL

    public init(
        clientName: String,
        clientId: UUID,
        apiKeyId: String,
        apiSecret: String,
        publicKey: String,
        privateKey: String,
        baseApiUrl: URL
    ) {
        self.clientName = clientName
        self.clientId = clientId
        self.apiKeyId = apiKeyId
        self.apiSecret = apiSecret
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.baseApiUrl = baseApiUrl
    }
}

// MARK: Json

extension Config: Ogra.Encodable, Argo.Decodable {

    public func encode() -> JSON {
        return JSON.object([
            "base_api_url": baseApiUrl.encode(),
            "api_key_id": apiKeyId.encode(),
            "api_secret": apiSecret.encode(),
            "client_id": clientId.encode(),
            "client_name": clientName.encode(),
            "public_key": publicKey.encode(),
            "private_key": privateKey.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<Config> {
        let tmp = curry(Config.init)
            <^> j <| "base_api_url"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"

        return tmp
            <*> j <| "client_id"
            <*> j <| "client_name"
            <*> j <| "public_key"
            <*> j <| "private_key"
    }
}

private let defaultProfileName = "com.tozny.e3db.defaultProfile"

// MARK: Storage in keychain / secure enclave

extension Config {

    public init?(loadProfile profile: String = defaultProfileName) {
        guard let valet = VALSecureEnclaveValet(identifier: profile, accessControl: .touchIDAnyFingerprint),
              let data  = valet.object(forKey: profile, userPrompt: "Unlock to load profile"),
              let json  = try? JSONSerialization.jsonObject(with: data, options: []),
            case .success(let config) = Config.decode(JSON(json)) else {
            return nil // Could not create config from json
        }
        self = config
    }

    public func save(profile: String = defaultProfileName) -> Bool {
        guard let valet  = VALSecureEnclaveValet(identifier: profile, accessControl: .touchIDAnyFingerprint),
              let config = try? JSONSerialization.data(withJSONObject: self.encode().JSONObject(), options: []) else {
                return false // Could not serialize json
        }
        return valet.setObject(config, forKey: profile)
    }
}
