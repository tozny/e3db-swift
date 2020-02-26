//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 1/7/20.
//

import Foundation
import ToznySwish
import Sodium


public class IdentityConfig: Codable {
    internal init(realmName: String, appName: String, apiUrl: String = Api.defaultUrl, username: String, userId: Int? = nil, brokerTargetUrl: String? = nil, firstName: String? = nil, lastName: String? = nil, storageConfig: Config) {
        self.realmName = realmName
        self.appName = appName
        self.apiUrl = apiUrl
        self.username = username
        self.storageConfig = storageConfig

        self.firstName = firstName
        self.lastName = lastName
        self.userId = userId
        self.brokerTargetUrl = brokerTargetUrl
    }

    // required to initialize and login to an identity client
    let realmName: String
    let appName: String
    let apiUrl: String
    let username: String

    // fully initialized config
    let storageConfig: Config

    // note required for identity functions
    let userId: Int?
    let brokerTargetUrl: String?
    let firstName: String?
    let lastName: String?
}

public class PartialIdentity {
    let storeClient: Client
    let authClient: Authenticator

    let api: Api
    let idConfig: IdentityConfig

    init(idConfig: IdentityConfig, urlSession: URLSession, scheduler: @escaping Scheduler) {
        self.api = Api(baseUrl: URL(string: idConfig.apiUrl)!)
        self.storeClient = Client(config: idConfig.storageConfig, urlSession: urlSession)
        let authConfig = AuthenticatorConfig(publicSigningKey: idConfig.storageConfig.publicSigKey,
                                             privateSigningKey: idConfig.storageConfig.privateSigKey,
                                             apiUrl: idConfig.apiUrl,
                                             clientId: idConfig.storageConfig.clientId.uuidString.lowercased())
        print("idconfig api url \(idConfig.apiUrl)")
        self.authClient = Authenticator(config: authConfig, urlSession: urlSession)
        self.idConfig = idConfig
    }

    init(fromSelf partialIdentity: PartialIdentity) {
        self.api = partialIdentity.api
        self.storeClient = partialIdentity.storeClient
        self.authClient = partialIdentity.authClient
        self.idConfig = partialIdentity.idConfig
    }

    public convenience init(idConfig: IdentityConfig, urlSession: URLSession = .shared) {
        self.init(idConfig: idConfig, urlSession: urlSession, scheduler: mainQueueScheduler)
    }

//    // First Party Login
//    public func login(username: String, password: String) -> Identity {
//
//    }

    public func readNoteByName(noteName: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["id_string": noteName]
        Identity.internalReadNote(params: params, authenticator: self.authClient) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
                                                                    privateEncryptionKey: self.idConfig.storageConfig.privateKey,
                                                                    publicEncryptionKey: self.idConfig.storageConfig.publicKey,
                                                                    publicSigningKey: self.idConfig.storageConfig
                                                                            .publicSigKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }

    static func readNoteByName(noteName: String,
                               privateEncryptionKey: String,
                               publicEncryptionKey: String,
                               publicSigningKey: String,
                               privateSigningKey: String,
                               additionalHeaders: [String: String]? = nil,
                               urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["id_string": noteName]
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Identity.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                print("this is the note eak \(note.noteKeys.encryptedAccessKey)")
                // TODO: FIX ME DECRYPT NOT KEY NAMING
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: note.noteKeys.writerEncryptionKey, publicSigningKey: note.noteKeys.writerSigningKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }


    // ReadNote
    public func readNote(noteID: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["note_id": noteID]
        Identity.internalReadNote(params: params, authenticator: self.authClient) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: self.idConfig.storageConfig.privateKey, publicEncryptionKey: self.idConfig.storageConfig.publicKey, publicSigningKey: self.idConfig.storageConfig.publicSigKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }

    // TODO: default api constant
    static func readNote(noteID: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", additionalHeaders: [String: String]? = nil, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        let params = ["note_id": noteID]
        Identity.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: publicEncryptionKey, publicSigningKey: publicSigningKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }


    static func internalReadNote(params: [String: String], authenticator: Authenticator, additionalHeaders: [String: String]? = nil, completionHandler:
            @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        var paramString: String = ""
        for (key, value) in params {
            paramString += key + "=" + value + "&"
        }
        var request = URLRequest(url: URL(string: authenticator.config.apiUrl + "/v2/storage/notes?" + paramString)!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let additionalHeaders = additionalHeaders {
            for (key, value) in additionalHeaders {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        authenticator.tsv1Request(request: request, completionHandler: completionHandler)
    }

    public func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void){
        var options = options
        if options == nil {
            options = NoteOptions(clientId: self.idConfig.storageConfig.clientId.uuidString)
        } else {
            options?.clientId = self.idConfig.storageConfig.clientId.uuidString
        }

        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.idConfig.storageConfig.privateKey, publicKey: self.idConfig.storageConfig.publicKey)
        let signingKeyPair = SigningKeyPair(privateKey: self.idConfig.storageConfig.privateSigKey, publicKey: self.idConfig.storageConfig.publicSigKey)

        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: self.authClient) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                return completionHandler(.success(note))
            }
        }
    }

    static func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let encryptionKeyPair = EncryptionKeyPair(privateKey: privateEncryptionKey, publicKey: publicEncryptionKey)
        let signingKeyPair = SigningKeyPair(privateKey: privateSigningKey, publicKey: publicSigningKey)
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: auth) {
            result -> Void in
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (note: Note) -> Void in
                return completionHandler(.success(note))
            }
        }
    }

    static func internalWriteNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair, authenticator: Authenticator, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        let encryptedNote = createEncryptedNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeys, signingKeys: signingKeys)
        var request = URLRequest(url: URL(string: authenticator.config.apiUrl + "/v2/storage/notes")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(encryptedNote!)
        authenticator.tsv1Request(request: request, completionHandler: completionHandler)
    }


    static func createEncryptedNote(data:NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair) -> Note? {
        let accessKey = Crypto.generateAccessKey()
        guard let authorizerPrivKey = Box.SecretKey(base64UrlEncoded: encryptionKeys.privateKey),
              let encryptedAccessKey = Crypto.encrypt(accessKey: accessKey!, readerClientKey: ClientKey(curve25519: recipientEncryptionKey), authorizerPrivKey: authorizerPrivKey) else {
            return nil
        }
        let noteKeys = NoteKeys(mode: "Sodium", recipientSigningKey: recipientSigningKey, writerSigningKey: signingKeys.publicKey, writerEncryptionKey: encryptionKeys.publicKey, encryptedAccessKey: encryptedAccessKey)
        let unencryptedNote = Note(data: data, noteKeys: noteKeys, noteOptions: options)
        return try? Crypto.encryptNote(note: unencryptedNote, accessKey: accessKey!, signingKey: signingKeys.privateKey)
    }
}

public class Identity: PartialIdentity {
    let identityServiceToken: String

    init(idConfig: IdentityConfig, identityServiceToken: String, urlSession: URLSession, scheduler: @escaping
    Scheduler) {
        self.identityServiceToken = identityServiceToken
        super.init(idConfig: idConfig, urlSession: urlSession, scheduler: scheduler)
    }

    init(fromPartial partial: PartialIdentity, identityServiceToken: String) {
        self.identityServiceToken = identityServiceToken
        super.init(fromSelf: partial)
    }
    
    public convenience init(idConfig: IdentityConfig, identityServiceToken: String, urlSession: URLSession = .shared) {
        self.init(idConfig: idConfig, identityServiceToken: identityServiceToken, urlSession: urlSession, scheduler:
        mainQueueScheduler)
    }
    

//    public func register(username: String, password: String, token: String, realmName: String, firstName: String? = nil, lastName: String? = nil, emailEacpExpiryMinutes: Int = 60, completionHandler: @escaping (Result<IdentityRequest, Error>) -> Void) throws {
//        var username = username
//        username = username.lowercased()
//
//        let cryptoKeys = Client.generateKeyPair()
//        let signingKeys = Client.generateSigningKeyPair()
//        let publicSigningKey = ["ed25519": signingKeys!.publicKey] // FIXME: please
//        let publicEncryptionKey = ["curve25519": cryptoKeys!.publicKey]
//        let identity = IdentityRequest(realmName: realmName, username: username, publicKeys: publicSigningKey, signingKeys: publicEncryptionKey, firstName: firstName, lastName: lastName)
//        let payload = IdentityRegisterRequest(realmRegistrationToken: token, realmName: realmName, identity: identity)
//
//        var request = URLRequest(url: URL(string: self.authClient.config.baseApiUrl + "/v1/identity/register")!)
//        request.httpMethod = "POST"
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpBody = try! JSONEncoder().encode(payload)
//
//        self.authClient.tsv1AuthenticatedRequest(request: request) {
//            result -> Void in
//            Identity.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
//                (identityResponse: IdentityRegisterResponse) -> Void in
//                do {
//                    let storageConfig = Config(clientName: username,
//                            clientId: UUID.init(uuidString: identityResponse.identity.toznyId!)!,
//                            apiKeyId: identityResponse.identity.apiKeyID!,
//                            apiSecret: identityResponse.identity.apiKeySecret!,
//                            publicKey: cryptoKeys!.publicKey,
//                            privateKey: cryptoKeys!.secretKey,
//                            baseApiUrl: self.config.baseApiUrl,
//                            publicSigKey: signingKeys!.publicKey,
//                            privateSigKey: signingKeys!.secretKey)
//
//                    let idConfig = IdentityConfig(realmName: realmName,
//                            appName: "account", // TODO: FIXME: please
//                            username: username,
//                            userId: identityResponse.identity.id,
//                            brokerTargetUrl: identityResponse.realmBrokerIdentityToznyID,
//                            firstName: firstName,
//                            lastName: lastName, storageConfig: storageConfig)
//
//                    let noteCreds = try Crypto.deriveNoteCreds(realmName: realmName, username: username, password: password)
//                    let passNote = SavedNote(identity: idConfig, store: storageConfig)
//
//
//
//                } catch {
//                    return completionHandler(.failure(error))
//                }
//            }
//        }
//    }
//

    
}

struct EncryptionKeyPair {
    let privateKey: String
    let publicKey: String
}

typealias SigningKeyPair = EncryptionKeyPair

func sortQueryParameters(query queryString: String) -> String {
    var splitQueryString = queryString.split(separator: "&")
    splitQueryString.sort(by: {$0.split(separator: "=")[0] < $1.split(separator: "=")[0]})
    return splitQueryString.joined(separator: "&")
}
