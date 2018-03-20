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

/// Configuration for the E3DB Client
public struct Config {

    /// The name for this client
    public let clientName: String

    /// The client identifier
    public let clientId: UUID

    /// The API key identifier
    public let apiKeyId: String

    /// The API secret for making authenticated calls
    public let apiSecret: String

    /// The client's public encryption key
    public let publicKey: String

    /// The client's secret encryption key
    public let privateKey: String

    /// The base URL for the E3DB service
    public let baseApiUrl: URL

    /// The client's public signing key
    public let publicSigKey: String

    /// The client's secret signing key
    public let privateSigKey: String

    /// Initializer to customize the configuration of the client. Typically, library users will
    /// use the `Client.register(token:clientName:apiUrl:completion:)` method which will supply
    /// an initialized `Config` object. Use this initializer if you register with the other
    /// registration method, `Client.register(token:clientName:publicKey:apiUrl:completion:)`.
    /// Pass this object to the `Client(config:)` initializer to create a new `Client`.
    ///
    /// - Parameters:
    ///   - clientName: The name for this client
    ///   - clientId: The client identifier
    ///   - apiKeyId: The API key identifier
    ///   - apiSecret: The API secret for making authenticated calls
    ///   - publicKey: The client's public key
    ///   - privateKey: The client's secret key
    ///   - baseApiUrl: The base URL for the E3DB service
    public init(
        clientName: String,
        clientId: UUID,
        apiKeyId: String,
        apiSecret: String,
        publicKey: String,
        privateKey: String,
        baseApiUrl: URL,
        publicSigKey: String,
        privateSigKey: String
    ) {
        self.clientName = clientName
        self.clientId = clientId
        self.apiKeyId = apiKeyId
        self.apiSecret = apiSecret
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.baseApiUrl = baseApiUrl
        self.publicSigKey = publicSigKey
        self.privateSigKey = privateSigKey
    }
}

// MARK: Json

/// :nodoc:
extension Config: Ogra.Encodable, Argo.Decodable {

    public func encode() -> JSON {
        return JSON.object([
            "client_name": clientName.encode(),
            "client_id": clientId.encode(),
            "api_key_id": apiKeyId.encode(),
            "api_secret": apiSecret.encode(),
            "public_key": publicKey.encode(),
            "private_key": privateKey.encode(),
            "base_api_url": baseApiUrl.encode(),
            "public_sig_key": publicSigKey.encode(),
            "private_sig_key": privateSigKey.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<Config> {
        let tmp = curry(Config.init)
            <^> j <| "client_name"
            <*> j <| "client_id"
            <*> j <| "api_key_id"
            <*> j <| "api_secret"

        return tmp
            <*> j <| "public_key"
            <*> j <| "private_key"
            <*> j <| "base_api_url"
            <*> j <| "public_sig_key"
            <*> j <| "private_sig_key"
    }
}

// MARK: Storage in keychain / secure enclave

private let defaultProfileName   = "com.tozny.e3db.defaultProfile"
private let defaultUserPrompt    = "Unlock to load profile"
private let defaultAccessControl = SecureEnclaveAccessControl.biometricAny

extension Config {

    /// Load a profile from the device's secure enclave if available.
    ///
    /// - Important: Accessing this keychain data will require the user to confirm their presence
    ///   via Touch ID or passcode entry. If no passcode is set on the device, this method will fail.
    ///   Data is removed from the Secure Enclave when the user removes a passcode from the device.
    ///
    /// - SeeAlso: `save(profile:)` for storing the `Config` object.
    ///
    /// - Parameter loadProfile: Name of the profile that was previously saved,
    ///   uses internal default if unspecified.
    /// - Parameter userPrompt: A message used to inform the user about unlocking the profile.
    /// - Returns: A fully initialized `Config` object if successful, `nil` otherwise.
    public init?(loadProfile: String? = nil, userPrompt: String? = nil) {
        let profile = loadProfile ?? defaultProfileName
        let prompt  = userPrompt ?? defaultUserPrompt
        guard let identifier = Identifier(nonEmpty: profile) else { return nil }

        let valet = SecureEnclaveValet.valet(with: identifier, accessControl: defaultAccessControl)
        guard case .success(let data) = valet.object(forKey: profile, withPrompt: prompt),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              case .success(let config) = Config.decode(JSON(json)) else {
            return nil // Could not create config from json
        }
        self = config
    }

    /// Save a profile to the device's secure enclave if available.
    ///
    /// - Important: Accessing this keychain data will require the user to confirm their presence
    ///   via Touch ID or passcode entry. If no passcode is set on the device, this method will fail.
    ///   Data is removed from the Secure Enclave when the user removes a passcode from the device.
    ///
    /// - SeeAlso: `init(loadProfile:userPrompt:)` for loading the `Config` object.
    ///
    /// - Parameter profile: Identifier for the profile for loading later,
    ///   uses internal default if unspecified.
    /// - Returns: A boolean value indicating whether the config object was successfully saved.
    public func save(profile named: String? = nil) -> Bool {
        let profile = named ?? defaultProfileName
        guard let identifier = Identifier(nonEmpty: profile) else { return false }

        let valet = SecureEnclaveValet.valet(with: identifier, accessControl: defaultAccessControl)
        guard let config = try? JSONSerialization.data(withJSONObject: encode().JSONObject(), options: []) else {
            return false // Could not serialize json
        }
        return valet.set(object: config, forKey: profile)
    }
}
