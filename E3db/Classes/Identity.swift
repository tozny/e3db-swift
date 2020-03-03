//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 1/7/20.
//

import Foundation
import ToznySwish
import Sodium


//public class IdentityConfig: Codable {
//    internal init(realmName: String, appName: String, apiUrl: String = Api.defaultUrl, username: String, userId: Int? = nil, brokerTargetUrl: String? = nil, firstName: String? = nil, lastName: String? = nil, storageConfig: Config) {
//        self.realmName = realmName
//        self.appName = appName
//        self.apiUrl = apiUrl
//        self.username = username
//        self.storageConfig = storageConfig
//
//        self.firstName = firstName
//        self.lastName = lastName
//        self.userId = userId
//        self.brokerTargetUrl = brokerTargetUrl
//    }
//
//    convenience init(fromPassNote note: Note) throws {
//        let noteData = try JSONDecoder().decode(SavedNote.self, from: JSONSerialization.data(withJSONObject: note.data))
//
//        let storageConfig = Config(clientName: noteData.config.username,
//                                   clientId: UUID.init(uuidString: noteData.storage.clientId)!,
//                                   apiKeyId: noteData.storage.apiKeyId,
//                                   apiSecret: noteData.storage.apiSecret,
//                                   publicKey: noteData.storage.publicKey,
//                                   privateKey: noteData.storage.privateKey,
//                                   baseApiUrl: URL(string: noteData.storage.apiUrl)!,
//                                   publicSigKey: noteData.storage.publicSigKey,
//                                   privateSigKey: noteData.storage.privateSigKey)
//
//        self.init(realmName:noteData.config.realmName,
//                  appName: noteData.config.appName ?? "account",
//                  apiUrl: noteData.config.apiUrl,
//                  username: noteData.config.username,
//                  userId: noteData.config.userId,
//                  brokerTargetUrl: noteData.config.brokerTargetUrl,
//                  storageConfig: storageConfig)
//    }
//
//    // required to initialize and login to an identity client
//    let realmName: String
//    let appName: String
//    let apiUrl: String
//    let username: String
//
//    // fully initialized config
//    let storageConfig: Config
//
//    // note required for identity functions
//    let userId: Int?
//    let brokerTargetUrl: String?
//    let firstName: String?
//    let lastName: String?
//}

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

    public func changePassword(newPassword: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        guard let newCredentials = try? Crypto.deriveNoteCreds(realmName: self.idConfig.realmName, username: self.idConfig.username, password: newPassword) else {
            return completionHandler(.failure(E3dbError.cryptoError("Couldn't derive note credentials from new password")))
        }
        // TODO: storage config is in id config, and not needed
        let passNote = SavedNote(identity: self.idConfig, store: self.idConfig.storageConfig)
        guard let passNoteData = try? JSONEncoder().encode(passNote),
              let passNoteDataEncryptable  = try? JSONSerialization.jsonObject(with: passNoteData) as! [String: String] else {
            return completionHandler(.failure(E3dbError.configError("Current identity configuration was invalid")))
        }
        let options = NoteOptions(IdString: newCredentials.name, maxViews: -1, expires: false, eacp: TozIdEacp(realmName: self.idConfig.realmName))
        self.storeClient.replaceNoteByName(data: passNoteDataEncryptable, recipientEncryptionKey: newCredentials.encryptionKeyPair.publicKey, recipientSigningKey: newCredentials.signingKeyPair.publicKey, options: options, completionHandler: completionHandler)
    }

    public func fetchToken(appName: String, completionHandler: @escaping (Result<Token, Error>) -> Void) {
        let body = ["grant_type": "password", "client_id": appName]
        guard let bodyData = (try? encodeBodyAsUrl(body))?.data(using: .utf8) else {
            return completionHandler(.failure(E3dbError.jsonError(expected: "valid body", actual: "body"))) // TODO: Fix me
        }
        var request = URLRequest(url: URL(string: self.idConfig.apiUrl + "/auth/realms/" + self.idConfig.realmName + "/protocol/openid-connect/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        self.authClient.tsv1Request(request: request) {
            result -> Void in

            // TODO REMOVE ME
//            print("data lmao")
//            let (_, data) = try! result.get()
//            print("This is the tsv1reqeust response \(String(data: data, encoding:.utf8))")

            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
                (token: Token) -> Void in
                completionHandler(.success(token))
            }
        }
    }

//    public func replaceNoteByName(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        var options = options
//        if options == nil {
//            options = NoteOptions(clientId: self.idConfig.storageConfig.clientId.uuidString)
//        } else {
//            options?.clientId = self.idConfig.storageConfig.clientId.uuidString
//        }
//        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.idConfig.storageConfig.privateKey, publicKey: self.idConfig.storageConfig.publicKey)
//        let signingKeyPair = SigningKeyPair(privateKey: self.idConfig.storageConfig.privateSigKey, publicKey: self.idConfig.storageConfig.publicSigKey)
//
//        guard let encryptedNote = PartialIdentity.createEncryptedNote(data: data,
//                                                                      recipientEncryptionKey: recipientEncryptionKey,
//                                                                      recipientSigningKey: recipientSigningKey,
//                                                                      options: options,
//                                                                      encryptionKeys: encryptionKeyPair,
//                                                                      signingKeys: signingKeyPair),
//              let noteBody = try? JSONEncoder().encode(encryptedNote) else {
//            return completionHandler(.failure(E3dbError.cryptoError("Couldnt generate and encode note to request body")))
//        }
//        var request = URLRequest(url: URL(string: self.authClient.config.apiUrl + "/v2/storage/notes")!)
//        request.httpMethod = "PUT"
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.httpBody = noteBody
//
//        self.authClient.tsv1Request(request: request) {
//            result -> Void in
//                Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                    (note: Note) -> Void in
//                    // TODO Must be a better way to handle this completion...
//                    return completionHandler(.success(note))
//                }
//        }
//    }

//    public func readNoteByName(noteName: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        let params = ["id_string": noteName]
//        Identity.internalReadNote(params: params, authenticator: self.authClient) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
//                                                                    privateEncryptionKey: self.idConfig.storageConfig.privateKey,
//                                                                    publicEncryptionKey:  note.noteKeys.writerEncryptionKey,
//                                                                    publicSigningKey: note.noteKeys.writerSigningKey) else {
//                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
//                }
//                return completionHandler(.success(unencryptedNote))
//            }
//        }
//    }

//    static func readNoteByName(noteName: String,
//                               privateEncryptionKey: String,
//                               publicEncryptionKey: String,
//                               publicSigningKey: String,
//                               privateSigningKey: String,
//                               additionalHeaders: [String: String]? = nil,
//                               urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        let params = ["id_string": noteName]
//        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
//        let auth = Authenticator(config: config, urlSession: urlSession)
//        Identity.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
//                                                                    privateEncryptionKey: privateEncryptionKey,
//                                                                    publicEncryptionKey: note.noteKeys.writerEncryptionKey,
//                                                                    publicSigningKey: note.noteKeys.writerSigningKey) else {
//                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
//                }
//                return completionHandler(.success(unencryptedNote))
//            }
//        }
//    }


//    // ReadNote
//    public func readNote(noteID: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        let params = ["note_id": noteID]
//        Identity.internalReadNote(params: params, authenticator: self.authClient) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: self.idConfig.storageConfig.privateKey, publicEncryptionKey: note.noteKeys.writerEncryptionKey, publicSigningKey: note.noteKeys.writerSigningKey) else {
//                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
//                }
//                return completionHandler(.success(unencryptedNote))
//            }
//        }
//    }

//    // TODO: default api constant
//    static func readNote(noteID: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", additionalHeaders: [String: String]? = nil, completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
//        let auth = Authenticator(config: config, urlSession: urlSession)
//        let params = ["note_id": noteID]
//        Identity.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: note.noteKeys.writerEncryptionKey, publicSigningKey: note.noteKeys.writerSigningKey) else {
//                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
//                }
//                return completionHandler(.success(unencryptedNote))
//            }
//        }
//    }


//    static func internalReadNote(params: [String: String], authenticator: Authenticator, additionalHeaders: [String: String]? = nil, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
//        guard let paramString = try? encodeBodyAsUrl(params) else {
//            return completionHandler(.failure(E3dbError.jsonError(expected: "{param: field}", actual: "params"))) // TODO please
//        }
//
//        var request = URLRequest(url: URL(string: authenticator.config.apiUrl + "/v2/storage/notes?" + paramString)!)
//        request.httpMethod = "GET"
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        if let additionalHeaders = additionalHeaders {
//            for (key, value) in additionalHeaders {
//                request.addValue(value, forHTTPHeaderField: key)
//            }
//        }
//        authenticator.tsv1Request(request: request, completionHandler: completionHandler)
//    }

//    public func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void){
//        var options = options
//        if options == nil {
//            options = NoteOptions(clientId: self.idConfig.storageConfig.clientId.uuidString)
//        } else {
//            options?.clientId = self.idConfig.storageConfig.clientId.uuidString
//        }
//
//        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.idConfig.storageConfig.privateKey, publicKey: self.idConfig.storageConfig.publicKey)
//        let signingKeyPair = SigningKeyPair(privateKey: self.idConfig.storageConfig.privateSigKey, publicKey: self.idConfig.storageConfig.publicSigKey)
//
//        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: self.authClient) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                return completionHandler(.success(note))
//            }
//        }
//    }
//
//    // TODO: decrypt written note after writing
//    static func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, apiUrl: String = "https://api.e3db.com", options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void) {
//        let encryptionKeyPair = EncryptionKeyPair(privateKey: privateEncryptionKey, publicKey: publicEncryptionKey)
//        let signingKeyPair = SigningKeyPair(privateKey: privateSigningKey, publicKey: publicSigningKey)
//        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
//        let auth = Authenticator(config: config, urlSession: urlSession)
//        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: auth) {
//            result -> Void in
//            Authenticator.handleURLResponse(urlResult: result, errorHandler: errorCompletion(completionHandler)) {
//                (note: Note) -> Void in
//                return completionHandler(.success(note))
//            }
//        }
//    }

//    static func internalWriteNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair, authenticator: Authenticator, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
//        let encryptedNote = createEncryptedNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeys, signingKeys: signingKeys)
//        var request = URLRequest(url: URL(string: authenticator.config.apiUrl + "/v2/storage/notes")!)
//        request.httpMethod = "POST"
//        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        // TODO FIX NIL UNWARPPING HERE
//        request.httpBody = try? JSONEncoder().encode(encryptedNote!)
//        authenticator.tsv1Request(request: request, completionHandler: completionHandler)
//    }
//
//
//    static func createEncryptedNote(data:NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair) -> Note? {
//        let accessKey = Crypto.generateAccessKey()
//        guard let authorizerPrivKey = Box.SecretKey(base64UrlEncoded: encryptionKeys.privateKey),
//              let encryptedAccessKey = Crypto.encrypt(accessKey: accessKey!, readerClientKey: ClientKey(curve25519: recipientEncryptionKey), authorizerPrivKey: authorizerPrivKey) else {
//            return nil
//        }
//        let noteKeys = NoteKeys(mode: "Sodium", recipientSigningKey: recipientSigningKey, writerSigningKey: signingKeys.publicKey, writerEncryptionKey: encryptionKeys.publicKey, encryptedAccessKey: encryptedAccessKey)
//        let unencryptedNote = Note(data: data, noteKeys: noteKeys, noteOptions: options)
//        return try? Crypto.encryptNote(note: unencryptedNote, accessKey: accessKey!, signingKey: signingKeys.privateKey)
//    }
}

public class Identity: PartialIdentity {
    let identityServiceToken: AgentToken // AgentToken governs whether the user is logged in with identity service
    let keycloakToken: Token?

    init(idConfig: IdentityConfig, identityServiceToken: AgentToken, urlSession: URLSession, scheduler: @escaping
    Scheduler) {
        self.identityServiceToken = identityServiceToken
        self.keycloakToken = nil
        super.init(idConfig: idConfig, urlSession: urlSession, scheduler: scheduler)
    }

    init(fromPartial partial: PartialIdentity, identityServiceToken: AgentToken) {
        self.identityServiceToken = identityServiceToken
        self.keycloakToken = nil
        super.init(fromSelf: partial)
    }
    
    public convenience init(idConfig: IdentityConfig, identityServiceToken: AgentToken, urlSession: URLSession = .shared) {
        self.init(idConfig: idConfig, identityServiceToken: identityServiceToken, urlSession: urlSession, scheduler:
        mainQueueScheduler)
    }

    public func agentToken() -> String {
        return self.identityServiceToken.accessToken
    }

    public func agentInfo() -> AgentToken {
        return self.identityServiceToken
    }

    public func token(completionHandler: @escaping (Result<Token, Error>) -> Void) {
        // TODO: Expired token is not refreshed automatically
        if let keycloakToken = self.keycloakToken {
            return completionHandler(.success(keycloakToken))
        }
        self.fetchToken(appName: self.idConfig.appName, completionHandler: completionHandler)
    }
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
