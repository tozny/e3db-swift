//
//  Note.swift
//  E3db
//
//  Created by michael lee on 2/19/20.
//

import Foundation
import Sodium
import Result

// Mark Note CRUD operations
extension Client {

    public func readNoteByName(noteName: String, completionHandler: @escaping E3dbCompletion<Note>) {
        let params = ["id_string": noteName]
        Client.internalReadNote(params: params, authenticator: self.tsv1AuthClient) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
                                                                    privateEncryptionKey: self.config.privateKey,
                                                                    publicEncryptionKey:  note.noteKeys.writerEncryptionKey,
                                                                    publicSigningKey: note.noteKeys.writerSigningKey) else {
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
                               urlSession: URLSession = URLSession.shared,
                               apiUrl: String = "https://api.e3db.com",
                               completionHandler: @escaping E3dbCompletion<Note>) {
        let params = ["id_string": noteName]
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Client.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
                                                                    privateEncryptionKey: privateEncryptionKey,
                                                                    publicEncryptionKey: note.noteKeys.writerEncryptionKey,
                                                                    publicSigningKey: note.noteKeys.writerSigningKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }

    public func readNote(noteID: String, completionHandler: @escaping E3dbCompletion<Note>) {
        let params = ["note_id": noteID]
        Client.internalReadNote(params: params, authenticator: self.tsv1AuthClient) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note,
                                                                    privateEncryptionKey: self.config.privateKey,
                                                                    publicEncryptionKey: note.noteKeys.writerEncryptionKey,
                                                                    publicSigningKey: note.noteKeys.writerSigningKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }

    // TODO: default api constant
    static func readNote(noteID: String,
                         privateEncryptionKey: String,
                         publicEncryptionKey: String,
                         publicSigningKey: String,
                         privateSigningKey: String,
                         urlSession: URLSession = URLSession.shared,
                         apiUrl: String = "https://api.e3db.com",
                         additionalHeaders: [String: String]? = nil,
                         completionHandler: @escaping E3dbCompletion<Note>) {
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        let params = ["note_id": noteID]
        Client.internalReadNote(params: params, authenticator: auth, additionalHeaders: additionalHeaders) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: note.noteKeys.writerEncryptionKey, publicSigningKey: note.noteKeys.writerSigningKey) else {
                    return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                }
                return completionHandler(.success(unencryptedNote))
            }
        }
    }

    public func writeNote(data: NoteData,
                          recipientEncryptionKey: String,
                          recipientSigningKey: String,
                          options: NoteOptions?,
                          completionHandler: @escaping E3dbCompletion<Note>){
        var options = options
        if options == nil {
            options = NoteOptions(clientId: self.config.clientId.uuidString)
        } else {
            options?.clientId = self.config.clientId.uuidString
        }
        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.config.privateKey, publicKey: self.config.publicKey)
        let signingKeyPair = SigningKeyPair(privateKey: self.config.privateSigKey, publicKey: self.config.publicSigKey)
        Client.internalWriteNote(data: data,
                                   recipientEncryptionKey: recipientEncryptionKey,
                                   recipientSigningKey: recipientSigningKey,
                                   options: options,
                                   encryptionKeys: encryptionKeyPair,
                                   signingKeys: signingKeyPair,
                                   authenticator: self.tsv1AuthClient) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                return completionHandler(.success(note))
            }
        }
    }

    static func writeNote(data: NoteData,
                          recipientEncryptionKey: String,
                          recipientSigningKey: String,
                          privateEncryptionKey: String,
                          publicEncryptionKey: String,
                          publicSigningKey: String,
                          privateSigningKey: String,
                          urlSession: URLSession = URLSession.shared,
                          apiUrl: String = "https://api.e3db.com",
                          options: NoteOptions?,
                          completionHandler: @escaping E3dbCompletion<Note>) {
        let encryptionKeyPair = EncryptionKeyPair(privateKey: privateEncryptionKey, publicKey: publicEncryptionKey)
        let signingKeyPair = SigningKeyPair(privateKey: privateSigningKey, publicKey: publicSigningKey)
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, apiUrl: apiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Client.internalWriteNote(data: data,
                                   recipientEncryptionKey: recipientEncryptionKey,
                                   recipientSigningKey: recipientSigningKey,
                                   options: options,
                                   encryptionKeys: encryptionKeyPair,
                                   signingKeys: signingKeyPair,
                                   authenticator: auth) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                return completionHandler(.success(note))
            }
        }
    }

    static func internalReadNote(params: [String: String],
                                 authenticator: Authenticator,
                                 additionalHeaders: [String: String]? = nil,
                                 completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        guard let paramString = try? encodeBodyAsUrl(params) else {
            return completionHandler(.failure(E3dbError.jsonError(expected: "{param: field}", actual: "params"))) // TODO please
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

    static func internalWriteNote(data: NoteData,
                                  recipientEncryptionKey: String,
                                  recipientSigningKey: String,
                                  options: NoteOptions?,
                                  encryptionKeys: EncryptionKeyPair,
                                  signingKeys: SigningKeyPair,
                                  authenticator: Authenticator,
                                  completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        do {
            let encryptedNote = try createEncryptedNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeys, signingKeys: signingKeys)
            var request = URLRequest(url: URL(string: authenticator.config.apiUrl + "/v2/storage/notes")!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let body = try? JSONEncoder().encode(encryptedNote) else { // TODO bang
                return completionHandler(.failure(E3dbError.jsonError(expected: "Expected note", actual: ""))) // TODO FIX ME
            }
            request.httpBody = body
            authenticator.tsv1Request(request: request, completionHandler: completionHandler)
        } catch {
            return completionHandler(.failure(error))
        }
    }

    static func createEncryptedNote(data:NoteData,
                                    recipientEncryptionKey: String,
                                    recipientSigningKey: String,
                                    options: NoteOptions?,
                                    encryptionKeys: EncryptionKeyPair,
                                    signingKeys: SigningKeyPair) throws -> Note {

        let accessKey = Crypto.generateAccessKey()
        guard let authorizerPrivKey = Box.SecretKey(base64UrlEncoded: encryptionKeys.privateKey),
              let encryptedAccessKey = Crypto.encrypt(accessKey: accessKey!, readerClientKey: ClientKey(curve25519: recipientEncryptionKey), authorizerPrivKey: authorizerPrivKey) else {
            throw E3dbError.cryptoError("Couldn't create access key")
        }
        let noteKeys = NoteKeys(mode: "Sodium", recipientSigningKey: recipientSigningKey, writerSigningKey: signingKeys.publicKey, writerEncryptionKey: encryptionKeys.publicKey, encryptedAccessKey: encryptedAccessKey)
        let unencryptedNote = Note(data: data, noteKeys: noteKeys, noteOptions: options)
        return try Crypto.encryptNote(note: unencryptedNote, accessKey: accessKey!, signingKey: signingKeys.privateKey)
    }

    public func replaceNoteByName(data: NoteData,
                                  recipientEncryptionKey: String,
                                  recipientSigningKey: String,
                                  options: NoteOptions?,
                                  completionHandler: @escaping E3dbCompletion<Note>) {

        var options = options
        if options == nil {
            options = NoteOptions(clientId: self.config.clientId.uuidString)
        } else {
            options?.clientId = self.config.clientId.uuidString
        }
        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.config.privateKey, publicKey: self.config.publicKey)
        let signingKeyPair = SigningKeyPair(privateKey: self.config.privateSigKey, publicKey: self.config.publicSigKey)
        guard let encryptedNote = try? Client.createEncryptedNote(data: data,
                                                             recipientEncryptionKey: recipientEncryptionKey,
                                                             recipientSigningKey: recipientSigningKey,
                                                             options: options,
                                                             encryptionKeys: encryptionKeyPair,
                                                             signingKeys: signingKeyPair),
              let noteBody = try? JSONEncoder().encode(encryptedNote) else {
            return completionHandler(.failure(E3dbError.cryptoError("Couldn't generate and encode note to request body")))
        }
        var request = URLRequest(url: URL(string: self.tsv1AuthClient.config.apiUrl + "/v2/storage/notes")!)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = noteBody
        self.tsv1AuthClient.tsv1Request(request: request) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (note: Note) -> Void in
                // TODO Must be a better way to handle this completion...
                return completionHandler(.success(note))
            }
        }
    }
}

public class Note: Codable {
    internal init(data: NoteData, plain: NoteData? = nil, fileMeta: NoteData? = nil, type: String? = nil, signature: String? = nil, createdAt: String? = nil, noteID: String? = nil, noteKeys: NoteKeys, noteOptions: NoteOptions? = nil, views: Int? = nil) {
        self.data = data
        self.plain = plain
        self.fileMeta = fileMeta
        self.type = type
        self.signature = signature
        self.createdAt = createdAt
        self.noteID = noteID
        self.noteKeys = noteKeys
        self.noteOptions = noteOptions
        self.views = views
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        data = try values.decode([String: String].self, forKey: .data)
        fileMeta = try? values.decode([String: String].self, forKey: .fileMeta)
        plain = try? values.decode([String: String].self, forKey: .plain)

        type = try? values.decode(String.self, forKey: .type)
        signature = try? values.decode(String.self, forKey: .signature)
        createdAt = try? values.decode(String.self, forKey: .createdAt)
        noteID = try? values.decode(String.self, forKey: .noteID)

        let recipientSigningKey = try values.decode(String.self, forKey: .recipientSigningKey)
        let encryptedAccessKey = try values.decode(String.self, forKey: .encryptedAccessKey)
        let writerEncryptionKey = try values.decode(String.self, forKey: .writerEncryptionKey)
        let writerSigningKey = try values.decode(String.self, forKey: .writerSigningKey)
        let mode = try values.decode(String.self, forKey: .mode)

        noteKeys = NoteKeys(mode: mode, recipientSigningKey: recipientSigningKey, writerSigningKey: writerSigningKey, writerEncryptionKey: writerEncryptionKey, encryptedAccessKey: encryptedAccessKey)

        views = try? values.decode(Int.self, forKey: .views)

        let clientID = try? values.decode(String.self, forKey: .clientId)
        let idString = try? values.decode(String.self, forKey: .IdString)
        let maxViews = try? values.decode(Int.self, forKey: .maxViews)
        let expiration = try? values.decode(String.self, forKey: .expiration)
        let expires = try? values.decode(Bool.self, forKey: .expires)
        let eacp = try? values.decode(NoteEacp.self, forKey: .eacp)

        noteOptions = NoteOptions(clientId: clientID, IdString: idString, maxViews: maxViews, expiration: expiration, expires: expires, eacp: eacp)

    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // core
        try container.encode(self.data, forKey: .data)
        try container.encode(self.plain, forKey: .plain)
        try container.encode(self.fileMeta, forKey: .fileMeta)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.signature, forKey: .signature)

        // server defined
        try container.encode(self.noteID, forKey: .noteID)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.views, forKey: .views)

        // note keys
        try container.encode(self.noteKeys.recipientSigningKey, forKey: .recipientSigningKey)
        try container.encode(self.noteKeys.encryptedAccessKey, forKey: .encryptedAccessKey)
        try container.encode(self.noteKeys.writerEncryptionKey, forKey: .writerEncryptionKey)
        try container.encode(self.noteKeys.writerSigningKey, forKey: .writerSigningKey)
        try container.encode(self.noteKeys.mode, forKey: .mode)

        // note options
        try container.encode(self.noteOptions?.clientId, forKey: .clientId)
        try container.encode(self.noteOptions?.IdString, forKey: .IdString)
        try container.encode(self.noteOptions?.maxViews, forKey: .maxViews)
        try container.encode(self.noteOptions?.expiration, forKey: .expiration)
        try container.encode(self.noteOptions?.expires, forKey: .expires)
        try container.encode(self.noteOptions?.eacp, forKey: .eacp)
    }

    var data: NoteData
    var plain: NoteData?
    var fileMeta: NoteData?
    var type: String?

    var signature: String?
    var createdAt: String?
    var noteID: String?

    var noteKeys: NoteKeys
    var noteOptions: NoteOptions?
    var views: Int?

    enum CodingKeys: String, CodingKey {
        // core
        case data = "data"
        case fileMeta = "file_meta"
        case plain = "plain"
        case type = "type"
        case signature = "signature"

        // server defined
        case createdAt = "created_at"
        case noteID = "note_id"
        case views = "views"

        // note keys
        case mode = "mode"
        case recipientSigningKey = "recipient_signing_key"
        case writerSigningKey = "writer_signing_key"
        case writerEncryptionKey = "writer_encryption_key"
        case encryptedAccessKey = "encrypted_access_key"

        // note options
        case clientId = "client_id"
        case IdString = "id_string"
        case maxViews = "max_views"
        case expiration = "expiration"
        case expires = "expires"

        case eacp = "eacp"
    }
}

public struct NoteKeys: Codable {
    let mode: String
    let recipientSigningKey: String
    let writerSigningKey: String
    let writerEncryptionKey: String
    let encryptedAccessKey: String
}

public class NoteOptions: Codable {
    internal init(clientId: String? = nil, IdString: String? = nil, maxViews: Int? = nil, expiration: String? = nil, expires: Bool? = nil, eacp: NoteEacp? = nil) {
        self.clientId = clientId
        self.IdString = IdString
        self.maxViews = maxViews
        self.expiration = expiration
        self.expires = expires
        self.eacp = eacp
    }

    var clientId: String?
    var IdString: String?
    var maxViews: Int?
    // premium features
    var expiration: String?
    var expires: Bool?
    var eacp: NoteEacp?
}

public typealias NoteData = [String: String]

public class NoteEacp: Codable {
    public init() {}

    static func TozOtpEacp(include: Bool) -> Codable {
        return ["tozny_otp_eacp": ["include": "true"]]
    }

    static func LastAccessEacp(lastReadId: String) -> Codable {
        return ["last_access_eacp": ["last_read_note_id": lastReadId]]
    }
}

public class TozOtpEacp: NoteEacp {
    struct EacpWrapper: Codable {
        let include: Bool
    }
    let eacpWrapper: EacpWrapper

    public init(include: Bool) {
        eacpWrapper = EacpWrapper(include: include)
        super.init()
    }

    required public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eacpWrapper = try values.decode(EacpWrapper.self, forKey: .eacpWrapper)
        super.init()
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eacpWrapper, forKey: .eacpWrapper)
    }

    enum CodingKeys: String, CodingKey {
        case eacpWrapper = "tozny_otp_eacp"
    }
}

public class LastAccessEacp: NoteEacp {
    struct EacpWrapper: Codable {
        let lastReadNoteId: String

        enum CodingKeys: String, CodingKey {
            case lastReadNoteId = "last_read_note_id"
        }
    }
    let eacpWrapper: EacpWrapper

    public init(lastReadNoteId: String) {
        eacpWrapper = EacpWrapper(lastReadNoteId: lastReadNoteId)
        super.init()
    }

    required public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eacpWrapper = try values.decode(EacpWrapper.self, forKey: .eacpWrapper)
        super.init()
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eacpWrapper, forKey: .eacpWrapper)
    }

    enum CodingKeys: String, CodingKey {
        case eacpWrapper = "last_access_eacp"
    }
}

public class TozIdEacp: NoteEacp {
    struct EacpWrapper: Codable {
        let realmName: String

        enum CodingKeys: String, CodingKey {
            case realmName = "realm_name"
        }
    }

    let eacpWrapper: EacpWrapper

    public init(realmName: String) {
        self.eacpWrapper = EacpWrapper(realmName: realmName)
        super.init()
    }

    required public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eacpWrapper = try values.decode(EacpWrapper.self, forKey: .eacpWrapper)
        super.init()
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eacpWrapper, forKey: .eacpWrapper)
    }

    enum CodingKeys: String, CodingKey {
        case eacpWrapper = "tozid_eacp"
    }
}

public class EmailEacp: NoteEacp {
    // TODO: Extract 60 to constnat
    internal init(emailAddress: String, template: String, providerLink: String, defaultExpirationMinutes: Int = 60, templateFields: [String:String]? = nil) {
        self.emailAddress = emailAddress
        self.template = template
        self.providerLink = providerLink
        self.defaultExpirationMinutes = defaultExpirationMinutes
        self.templateFields = templateFields
        super.init()
    }

    let emailAddress: String
    let template: String
    let providerLink: String
    let defaultExpirationMinutes: Int
    let templateFields: [String:String]?

    enum CodingKeys: String, CodingKey {
        case eacp = "email_eacp"
    }

    enum EacpInfoKeys: String, CodingKey {
        case emailAddress = "email_address"
        case template
        case templateFields = "template_fields"
        case providerLink = "provider_link"
        case defaultExpirationMinutes = "default_expiration_minutes"
    }

    required public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let eacpInfo = try values.nestedContainer(keyedBy: EacpInfoKeys.self, forKey: .eacp)
        emailAddress = try eacpInfo.decode(String.self, forKey: .emailAddress)
        template = try eacpInfo.decode(String.self, forKey: .template)
        templateFields = try? eacpInfo.decode([String:String].self, forKey: .templateFields)
        defaultExpirationMinutes = try eacpInfo.decode(Int.self, forKey: .defaultExpirationMinutes)
        providerLink = try eacpInfo.decode(String.self, forKey: .providerLink)
        super.init()
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var eacpInfo = container.nestedContainer(keyedBy: EacpInfoKeys.self, forKey: .eacp)

        try eacpInfo.encode(emailAddress, forKey: .emailAddress)
        try eacpInfo.encode(template, forKey: .template)
        try eacpInfo.encode(providerLink, forKey: .providerLink)
        try eacpInfo.encode(templateFields, forKey: .templateFields)
        try eacpInfo.encode(defaultExpirationMinutes, forKey: .defaultExpirationMinutes)
    }
}

