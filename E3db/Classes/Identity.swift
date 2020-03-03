//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 1/7/20.
//

import Foundation
import ToznySwish
import Sodium
import Result

public class PartialIdentity {
    let storeClient: Client

    let api: Api
    let idConfig: IdentityConfig

    init(idConfig: IdentityConfig, urlSession: URLSession, scheduler: @escaping Scheduler) {
        self.api = Api(baseUrl: URL(string: idConfig.apiUrl)!)
        self.storeClient = Client(config: idConfig.storageConfig, urlSession: urlSession)
        self.idConfig = idConfig
    }

    init(fromSelf partialIdentity: PartialIdentity) {
        self.api = partialIdentity.api
        self.storeClient = partialIdentity.storeClient
        self.idConfig = partialIdentity.idConfig
    }

    public convenience init(idConfig: IdentityConfig, urlSession: URLSession = .shared) {
        self.init(idConfig: idConfig, urlSession: urlSession, scheduler: mainQueueScheduler)
    }

    public func changePassword(newPassword: String, completionHandler: @escaping E3dbCompletion<Note>) {
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

    public func fetchToken(appName: String, completionHandler: @escaping E3dbCompletion<Token>) {
        let body = ["grant_type": "password", "client_id": appName]
        guard let bodyData = (try? encodeBodyAsUrl(body))?.data(using: .utf8) else {
            return completionHandler(.failure(E3dbError.jsonError(expected: "valid body", actual: "body"))) // TODO: Fix me
        }
        var request = URLRequest(url: URL(string: self.idConfig.apiUrl + "/auth/realms/" + self.idConfig.realmName + "/protocol/openid-connect/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        self.storeClient.tsv1AuthClient.handledTsv1Request(request: request, errorHandler: completionHandler) {
            (token: Token) -> Void in
            completionHandler(.success(token))
        }
    }
}

public class Identity: PartialIdentity {
    let identityServiceToken: AgentToken // AgentToken governs whether the user is logged in with TozId
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

    public func token(completionHandler: @escaping E3dbCompletion<Token>) {
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
