//
//  Config.swift
//  E3db
//

import Foundation
import Valet

/// Configuration for the E3DB Client
public struct Config: Codable {

    /// The name for this client
    public let clientName: String?

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
        clientName: String?,
        clientId: UUID,
        apiKeyId: String,
        apiSecret: String,
        publicKey: String,
        privateKey: String,
        baseApiUrl: URL,
        publicSigKey: String,
        privateSigKey: String
    ) {
        self.clientName = clientName ?? ""
        self.clientId = clientId
        self.apiKeyId = apiKeyId
        self.apiSecret = apiSecret
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.baseApiUrl = baseApiUrl
        self.publicSigKey = publicSigKey
        self.privateSigKey = privateSigKey
    }

    enum CodingKeys: String, CodingKey {
        case clientName    = "client_name"
        case clientId      = "client_id"
        case apiKeyId      = "api_key_id"
        case apiSecret     = "api_secret"
        case publicKey     = "public_key"
        case privateKey    = "private_key"
        case baseApiUrl    = "base_api_url"
        case publicSigKey  = "public_sig_key"
        case privateSigKey = "private_sig_key"
    }
}

// MARK: Storage in Keychain / Secure Enclave

private let kDefaultProfileName = "com.tozny.e3db.defaultProfile"
private let kDefaultUserPrompt  = "Unlock to load profile"

/// Access Protections for storing the Config in the device Keychain
public enum ConfigAccessControl {

    /// Access Control managed by the device's secure element when available
    public enum SecureEnclave {

        /// Access controlled by either biometrics (e.g. Touch ID, Face ID, etc) or device Passcode.
        /// Availability is unaffected by adding or removing fingerprints or faces.
        case userPresence

        /// Requires an enabled and enrolled face for Face ID or fingerprint for Touch ID.
        /// Availability is unaffected by adding or removing fingerprints or faces.
        case biometricAny

        /// Requires an enabled and currently enrolled face for Face ID or fingerprint for Touch ID.
        /// Configuration (i.e. user key pairs and secrets) becomes inaccessable when faces or fingerprints are added or removed.
        case biometricCurrentSet

        /// Requires that the device has a passcode setup.
        case devicePasscode

        // Maps the public E3db interface to the internal Valet value
        var valetAccess: SecureEnclaveAccessControl {
            switch self {
            case .userPresence:
                return .userPresence
            case .biometricAny:
                return .biometricAny
            case .biometricCurrentSet:
                return .biometricCurrentSet
            case .devicePasscode:
                return .devicePasscode
            }
        }
    }

    /// Access Control managed by the device's Keychain
    public enum Keychain {

        /// Access allowed when the application is in the foreground and the device is unlocked.
        /// Configuration will persist through a restore process if using encrypted backups.
        case whenUnlocked

        /// Access allowed once the device has been unlocked once after startup, whether the application is in the foreground or background.
        /// Configuration will persist through a restore process if using encrypted backups.
        case afterFirstUnlock

        /// Access always allowed (not recommended).
        /// Configuration will persist through a restore process if using encrypted backups.
        case always

        /// Access allowed when the application is in the foreground and the device is unlocked.
        /// Configuration will not persist through a restore process.
        /// Configuration will be lost if the passcode is changed or removed.
        case whenPasscodeSetThisDeviceOnly

        /// Access allowed when the application is in the foreground and the device is unlocked.
        /// Configuration will not persist through a restore process.
        case whenUnlockedThisDeviceOnly

        /// Access allowed once the device has been unlocked once after startup, whether the application is in the foreground or background.
        /// Configuration will not persist through a restore process.
        case afterFirstUnlockThisDeviceOnly

        /// Access always allowed (not recommended).
        /// Configuration will not persist through a restore process.
        case alwaysThisDeviceOnly

        // Maps the public E3db interface to the internal Valet value
        var valetAccess: Accessibility {
            switch self {
            case .whenUnlocked:
                return .whenUnlocked
            case .afterFirstUnlock:
                return .afterFirstUnlock
            case .always:
                return .always
            case .whenPasscodeSetThisDeviceOnly:
                return .whenPasscodeSetThisDeviceOnly
            case .whenUnlockedThisDeviceOnly:
                return .whenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly:
                return .afterFirstUnlockThisDeviceOnly
            case .alwaysThisDeviceOnly:
                return .alwaysThisDeviceOnly
            }
        }

    }
}

extension Config {

    /// Securely load a profile using the device's Secure Enclave if available.
    ///
    /// - Important: Accessing this Keychain data will require the user to confirm their presence via
    ///   biometrics (e.g. Touch ID or Face ID) or passcode entry. If no passcode is set on the device, this method will fail.
    ///   Data may be lost when the user removes an entry (fingerprint, face, or passcode) from the device.
    ///
    /// - SeeAlso: `init(loadProfile:keychainAccess:)` for loading `Config` objects from the Keychain without the Secure Enclave.
    /// - SeeAlso: `save(profile:enclaveAccess:)` for storing the `Config` object using the Secure Enclave.
    ///
    /// - Parameters:
    ///   - loadProfile: Name of the profile that was previously saved. Uses internal default if unspecified.
    ///   - userPrompt: A message used to inform the user about unlocking the profile. Uses internal default if unspecified.
    ///   - enclaveAccess: The Secure Enclave access control level used to protect the configuration when saved. Uses `.biometricAny` if unspecified.
    /// - Returns: A fully initialized `Config` object if successful, `nil` otherwise.
    public init?(loadProfile: String? = nil, userPrompt: String? = nil, enclaveAccess: ConfigAccessControl.SecureEnclave = .biometricAny) {
        let profile = loadProfile ?? kDefaultProfileName
        let prompt  = userPrompt ?? kDefaultUserPrompt
        guard let identifier = Identifier(nonEmpty: profile) else { return nil }

        let valet = SecureEnclaveValet.valet(with: identifier, accessControl: enclaveAccess.valetAccess)
        guard case .success(let data) = valet.object(forKey: profile, withPrompt: prompt),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return nil // Could not create config from json
        }
        self = config
    }

    /// Securely load a profile from the device's Keychain.
    ///
    /// - SeeAlso: `init(loadProfile:userPrompt:enclaveAccess:)` for loading `Config` objects from the Keychain using the Secure Enclave.
    /// - SeeAlso: `save(profile:keychainAccess:)` for storing the `Config` object in the Keychain.
    ///
    /// - Parameters:
    ///   - loadProfile: Name of the profile that was previously saved. Uses internal default if unspecified.
    ///   - keychainAccess: The Keychain access control level used to protect the configuration when saved.
    /// - Returns: A fully initialized `Config` object if successful, `nil` otherwise.
    public init?(loadProfile: String? = nil, keychainAccess: ConfigAccessControl.Keychain) {
        let profile = loadProfile ?? kDefaultProfileName
        guard let identifier = Identifier(nonEmpty: profile) else { return nil }

        let valet = Valet.valet(with: identifier, accessibility: keychainAccess.valetAccess)
        guard let data   = valet.object(forKey: profile),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return nil // Could not create config from json
        }
        self = config
    }

    /// Securely store a profile using the device's Secure Enclave if available.
    ///
    /// - Important: Accessing this Keychain data will require the user to confirm their presence via
    ///   biometrics (e.g. Touch ID or Face ID) or passcode entry. If no passcode is set on the device, this method will fail.
    ///   Data may be lost when the user removes an entry (fingerprint, face, or passcode) from the device.
    ///
    /// - SeeAlso: `save(profile:keychainAccess:)` for storing the `Config` object.
    /// - SeeAlso: `init(loadProfile:userPrompt:enclaveAccess:)` for loading `Config` objects from the Keychain using the Secure Enclave.
    ///
    /// - Parameters:
    ///   - profile: Identifier for the profile for loading later. Uses internal default if unspecified.
    ///   - enclaveAccess: The Secure Enclave access control level used to protect the configuration. Uses `.biometricAny` if unspecified.
    /// - Returns: A boolean value indicating whether the config object was successfully saved.
    public func save(profile: String? = nil, enclaveAccess: ConfigAccessControl.SecureEnclave = .biometricAny) -> Bool {
        let userProfile = profile ?? kDefaultProfileName
        guard let identifier = Identifier(nonEmpty: userProfile) else { return false }

        let valet = SecureEnclaveValet.valet(with: identifier, accessControl: enclaveAccess.valetAccess)
        guard let config = try? JSONEncoder().encode(self) else {
            return false // Could not serialize json
        }
        return valet.set(object: config, forKey: userProfile)
    }

    /// Securely store a profile in the device Keychain.
    ///
    /// - SeeAlso: `save(profile:enclaveAccess:)` for storing the `Config` object using the Secure Enclave.
    /// - SeeAlso: `init(loadProfile:keychainAccess:)` for loading `Config` objects from the device Keychain.
    ///
    /// - Parameters:
    ///   - profile: Identifier for the profile for loading later. Uses internal default if unspecified.
    ///   - keychainAccess: The Keychain access control level to protect the configuration.
    /// - Returns: A boolean value indicating whether the config object was successfully saved.
    public func save(profile: String? = nil, keychainAccess: ConfigAccessControl.Keychain) -> Bool {
        let userProfile = profile ?? kDefaultProfileName
        guard let identifier = Identifier(nonEmpty: userProfile) else { return false }

        let valet = Valet.valet(with: identifier, accessibility: keychainAccess.valetAccess)
        guard let config = try? JSONEncoder().encode(self) else {
            return false // Could not serialize json
        }
        return valet.set(object: config, forKey: userProfile)
    }
}

public class IdentityConfig: Codable {
    internal init(realmName: String, realmDomain: String?, appName: String, apiUrl: String = Api.defaultUrl, username: String?, userId: Int? = nil, brokerTargetUrl: String, firstName: String? = nil, lastName: String? = nil, storageConfig: Config) {
        self.realmName = realmName
        self.realmDomain = realmDomain ?? ""
        self.appName = appName
        self.apiUrl = apiUrl
        self.username = username ?? ""
        self.storageConfig = storageConfig

        self.firstName = firstName
        self.lastName = lastName
        self.userId = userId
        self.brokerTargetUrl = brokerTargetUrl
    }

    convenience init(fromPassNote note: Note) throws {
        let noteData = try JSONDecoder().decode(PasswordNoteData.self, from: JSONSerialization.data(withJSONObject: note.data))

        let storageConfig = Config(clientName: noteData.config.username,
                                   clientId: UUID.init(uuidString: noteData.storage.clientId)!,
                                   apiKeyId: noteData.storage.apiKeyId,
                                   apiSecret: noteData.storage.apiSecret,
                                   publicKey: noteData.storage.publicKey,
                                   privateKey: noteData.storage.privateKey,
                                   baseApiUrl: URL(string: noteData.storage.apiUrl)!,
                                   publicSigKey: noteData.storage.publicSigKey,
                                   privateSigKey: noteData.storage.privateSigKey)

        self.init(realmName:noteData.config.realmName,
                  realmDomain:noteData.config.realmDomain,
                  appName: noteData.config.appName,
                  apiUrl: noteData.config.apiUrl,
                  username: noteData.config.username,
                  userId: noteData.config.userId,
                  brokerTargetUrl: noteData.config.brokerTargetUrl,
                  storageConfig: storageConfig)
    }

    // required to initialize and login to an identity client
    public let realmName: String
    public let realmDomain: String
    public let appName: String
    public let apiUrl: String
    public let username: String
    public let brokerTargetUrl: String

    // fully initialized config
    public let storageConfig: Config

    // not required for identity functions
    public var userId: Int?
    public var firstName: String?
    public var lastName: String?
}

// AgentToken is the token that indicates a user is logged in with TozId
public class AgentToken: Codable {
    let accessToken: String
    let tokenType: String
    let expiry: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiry
    }
}

// Token represents token returned to a partial identity
public class Token: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshExpiresIn: Int
    let refreshToken: String
    let tokenType: String
    let notBeforePolicy: Int
    let sessionState: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshExpiresIn = "refresh_expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case notBeforePolicy = "not-before-policy" // TODO: Fixme from server response
        case sessionState = "session_state"
        case scope
    }
}

// Allows for decoding the Date format returned by Tozny services
extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
