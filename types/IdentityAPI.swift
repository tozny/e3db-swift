//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 2/19/20.
//

import Foundation

public struct IdentityRegisterRequest: Encodable {
    let realmRegistationToken: String
    let realmName: String
    let username: String
    let publicEncryptionKey: String
    let publicSigningKey: String
    let firstName: String
    let lastName: String
        
    enum CodingKeys: String, CodingKey {
        case realmRegistationToken = "realm_registration_token"
        case realmName = "realm_name"
        case identity
    }
    
    enum IdentityKeys: String, CodingKey {
        case realmName = "realm_name"
        case username = "name"
        case publicEncryptionKey = "public_key"
        case publicSigningKey = "signing_key"
        case firstName = "first_name"
        case lastName = "last_name"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(realmRegistationToken, forKey: .realmRegistationToken)
        try container.encode(realmName, forKey: .realmName)
        
        var eacpInfo = container.nestedContainer(keyedBy: IdentityKeys.self, forKey: .identity)
        try eacpInfo.encode(realmName, forKey: .realmName)
        try eacpInfo.encode(username, forKey: .username)
        try eacpInfo.encode(publicSigningKey, forKey: .publicSigningKey)
        try eacpInfo.encode(publicEncryptionKey, forKey: .publicEncryptionKey)
        try eacpInfo.encode(firstName, forKey: .firstName)
        try eacpInfo.encode(lastName, forKey: .lastName)
    }

}
