//
//  Note.swift
//  E3db
//
//  Created by michael lee on 2/19/20.
//

import Foundation

public class Note: Codable {
    internal init(data: NoteData, plain: NoteData? = nil, fileMeta: NoteData? = nil, type: String? = nil, signature: String? = nil, createdAt: String? = nil, noteID: String? = nil, noteKeys: NoteKeys, noteOptions: NoteOptions? = nil, views: Int? = nil, eacp: NoteEacp? = nil) {
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
        self.eacp = eacp
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
        eacp = try? values.decode(NoteEacp.self, forKey: .eacp)

        
        let clientID = try? values.decode(String.self, forKey: .clientId)
        let idString = try? values.decode(String.self, forKey: .IdString)
        let maxViews = try? values.decode(Int.self, forKey: .maxViews)
        let expiration = try? values.decode(String.self, forKey: .expiration)
        let expires = try? values.decode(Bool.self, forKey: .expires)
        
        noteOptions = NoteOptions(clientId: clientID, IdString: idString, maxViews: maxViews, expiration: expiration, expires: expires)
        
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

        // eacp
        try container.encode(self.eacp, forKey: .eacp)
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
    var eacp: NoteEacp?
    
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
    internal init(clientId: String? = nil, IdString: String? = nil, maxViews: Int? = nil, expiration: String? = nil, expires: Bool? = nil) {
        self.clientId = clientId
        self.IdString = IdString
        self.maxViews = maxViews
        self.expiration = expiration
        self.expires = expires
    }
    
    var clientId: String?
    var IdString: String?
    var maxViews: Int?
    // premium features
    var expiration: String?
    var expires: Bool?
}

public typealias NoteData = [String: String]

public class NoteEacp: Codable {
    public init() {}
}

public class EmailEacp: NoteEacp {
    internal init(emailAddress: String, template: String, providerLink: String, defaultExpirationMinutes: Int) {
        self.emailAddress = emailAddress
        self.template = template
        self.providerLink = providerLink
        self.defaultExpirationMinutes = defaultExpirationMinutes
        super.init()
    }
    
    let emailAddress: String
    let template: String
    let providerLink: String
    let defaultExpirationMinutes: Int
    
    enum CodingKeys: String, CodingKey {
        case eacp = "email_eacp"
    }
    
    enum EacpInfoKeys: String, CodingKey {
        case emailAddress = "email_address"
        case template
        case providerLink = "provider_link"
        case defaultExpirationMinutes = "default_expiration_minutes"
    }
    
    required public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let eacpInfo = try values.nestedContainer(keyedBy: EacpInfoKeys.self, forKey: .eacp)
        emailAddress = try eacpInfo.decode(String.self, forKey: .emailAddress)
        template = try eacpInfo.decode(String.self, forKey: .template)
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
        try eacpInfo.encode(defaultExpirationMinutes, forKey: .defaultExpirationMinutes)
    }
}
