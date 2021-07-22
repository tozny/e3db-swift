//
//  Identity.swift
//  E3db
//

import Foundation

public struct IdentityLoginAction: Decodable {
    let loginAction:Bool // T/F we need a login action to login
    let type:String // login action type totp/mfa
    let actionUrl:String // respond at this url
    let contentType:String // respond with this time
    let fields:[String:String] // fields required to proceed
    let context:[String:String] // additional contextual information needed for logging in


    enum CodingKeys: String, CodingKey {
        case loginAction = "login_action"
        case actionUrl = "action_url"
        case contentType = "content_type"
        case type
        case fields
        case context
    }
}

public struct IdentityLoginSession: Codable {
    let nonce: String
    let clientId: String
    let responseType: String
    let scope: String
    let redirectUri: String
    let responseMode: String
    let state: String
    let username: String
    let target: String
    let authSessionId: String?
    let federated: Bool

    enum CodingKeys: String, CodingKey {
        case nonce
        case clientId = "client_id"
        case responseType = "response_type"
        case scope
        case redirectUri = "redirect_uri"
        case responseMode = "response_mode"
        case state
        case username
        case target
        case authSessionId = "auth_session_id"
        case federated
    }
}

public struct IdentityRegisterRequest: Encodable {
    let realmRegistrationToken: String
    let realmName: String
    let identity: IdentityRequest

    enum CodingKeys: String, CodingKey {
        case realmRegistrationToken = "realm_registration_token"
        case realmName = "realm_name"
        case identity
    }
}

public struct IdentityRegisterResponse: Decodable {
    let identity: IdentityRequest
    let realmBrokerIdentityToznyID: String?

    enum CodingKeys: String, CodingKey {
        case realmBrokerIdentityToznyID = "realm_broker_identity_tozny_id"
        case identity
    }
}

public struct IdentityRequest: Codable {
    let id:Int?
    let toznyId:String? // server defined
    let apiKeyID:String?
    let apiKeySecret:String?
    let realmId:Int?
    let realmName:String
    let username:String
    let publicKeys:[String:String]
    let signingKeys:[String:String]
    let firstName:String?
    let lastName:String?

    public init(id: Int?=nil, toznyId: String?=nil, realmId: Int?=nil, realmName: String, username: String, apiKeyID: String?=nil, apiKeySecret: String?=nil, publicKeys: [String: String], signingKeys: [String: String], firstName: String?=nil, lastName: String?=nil) {
        self.id = id
        self.toznyId = toznyId
        self.realmId = realmId
        self.realmName = realmName
        self.username = username
        self.apiKeyID = apiKeyID
        self.apiKeySecret = apiKeySecret
        self.publicKeys = publicKeys
        self.signingKeys = signingKeys
        self.firstName = firstName
        self.lastName = lastName
    }

    enum CodingKeys: String, CodingKey {
        case id="id"
        case toznyId="tozny_id"
        case realmId="realm_id"
        case realmName="realm_name"
        case username="name"
        case firstName="first_name"
        case lastName="last_name"
        case apiKeyID="api_key_id"
        case apiKeySecret="api_secret_key"
        case publicKeys="public_key"
        case signingKeys="signing_key"
    }
}

public struct NoteCredentials {
    let name: String
    let encryptionKeyPair: EncryptionKeyPair
    let signingKeyPair: SigningKeyPair
}

public struct PasswordNoteData: Codable {
    struct idConfig: Codable {
        let realmName: String
        let appName: String
        let apiUrl: String
        let username: String
        let brokerTargetUrl: String
        let userId: Int?

        enum CodingKeys: String, CodingKey {
            case realmName = "realm_name"
            case appName = "app_name"
            case apiUrl = "api_url"
            case username
            case userId = "user_id"
            case brokerTargetUrl = "broker_target_url"
        }
    }

    struct storageConfig: Codable {
        let clientId: String
        let apiKeyId: String
        let apiSecret: String
        let apiUrl: String
        let publicKey: String
        let privateKey: String
        let publicSigKey: String
        let privateSigKey: String
        let version: Int = 2

        enum CodingKeys: String, CodingKey {
            case apiKeyId = "api_key_id"
            case apiSecret = "api_secret"
            case apiUrl = "api_url"
            case clientId = "client_id"
            case publicKey = "public_key"
            case privateKey = "private_key"
            case publicSigKey = "public_signing_key"
            case privateSigKey = "private_signing_key"
            case version
        }
    }

    let config: idConfig
    let storage: storageConfig

    init(identity: IdentityConfig, store: Config) {
        config = idConfig(realmName: identity.realmName,
                          appName: identity.appName,
                          apiUrl: identity.apiUrl,
                          username: identity.username,
                          brokerTargetUrl: identity.brokerTargetUrl,
                          userId: identity.userId)

        storage = storageConfig(clientId: store.clientId.uuidString,
                                apiKeyId: store.apiKeyId,
                                apiSecret: store.apiSecret,
                                apiUrl: identity.apiUrl,
                                publicKey: store.publicKey,
                                privateKey: store.privateKey,
                                publicSigKey: store.publicSigKey,
                                privateSigKey: store.privateSigKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let idSerial = String(data: try JSONEncoder().encode(config), encoding: .utf8)!
        let storeSerial = String(data: try JSONEncoder().encode(storage), encoding: .utf8)!

        try container.encode(idSerial, forKey: .config)
        try container.encode(storeSerial, forKey: .storage)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storageString = try values.decode(String.self, forKey: .storage)
        let configString = try values.decode(String.self, forKey: .config)

        let decoder = JSONDecoder()
        storage = try decoder.decode(storageConfig.self, from: storageString.data(using: .utf8)!)
        config = try decoder.decode(idConfig.self, from: configString.data(using: .utf8)!)
    }

    enum CodingKeys: String, CodingKey {
        case config
        case storage
    }
}

extension Encodable {
    var dictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}
