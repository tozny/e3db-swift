//
// Application.swift
// E3db
//


import Foundation
import Result

public class Application {
    let apiUrl: String
    let appName: String
    let realmName: String
    let brokerTargetUrl: String

    public init(apiUrl: String, appName: String, realmName: String, brokerTargetUrl: String) {
        self.apiUrl = apiUrl
        self.appName = appName
        self.realmName = realmName //.lowercased()
        self.brokerTargetUrl = brokerTargetUrl
    }
    
    /// Get the public info for the current realm
    public func info<Z: Any>(errorHandler: @escaping E3dbCompletion<Z>, completionHandler: @escaping (PublicRealmInfo) -> Void ) {
        var request = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/info/realm/" + self.realmName)!)
        request.httpMethod = "GET"
        Authenticator.request(unauthedReq: request) { result -> Void in
            let handleError = errorCompletion(errorHandler)
            switch(result) {
            case .failure(let error):
                let err = E3dbError.networkError(error.localizedDescription)
                    return handleError(err)
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        return handleError(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self)))
                    }
                    guard let response = try? Api.decoder.decode(PublicRealmInfo.self, from: data) else {
                        return handleError(E3dbError.jsonError(expected: String(describing: type(of: PublicRealmInfo.self)), actual: String(decoding: data, as: UTF8.self)))
                    }
                    completionHandler(response)
                } else {
                    return handleError(E3dbError.networkError("invalid network response"))
                }
            }
        }
    }

    public func login(username: String, password: String, actionHandler: @escaping (IdentityLoginAction) -> [String:String], completionHandler: @escaping E3dbCompletion<Identity>) {
            var username = username
            username = username.lowercased()
        self.info(errorHandler: completionHandler) {
            (realmInfo: PublicRealmInfo) -> Void in
            guard let noteCredentials = try? Crypto.deriveNoteCreds(realmName: realmInfo.name, username: username, password: password) else {
                return completionHandler(.failure(E3dbError.cryptoError("Couldn't derive crypto keys from username and password")))
            }
            let anonAuth = Authenticator(anonConfig: AuthenticatorConfig(publicSigningKey: noteCredentials.signingKeyPair.publicKey, privateSigningKey: noteCredentials.signingKeyPair.privateKey, apiUrl: self.apiUrl, clientId: nil))

            var initiateLoginRequest = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/login")!)
            initiateLoginRequest.httpMethod = "POST"
            let pkceVerifier = try? Crypto.randomBytes(length: 32)
            let pkceChallenge = Crypto.sha256(data: pkceVerifier!.data(using: .utf8)!)
            guard let body = try? JSONSerialization.data(withJSONObject: ["username": username, "realm_name": self.realmName, "app_name": self.appName, "code_challenge": pkceChallenge,"login_style": "api"]) else {
                return completionHandler(.failure(E3dbError.encodingError("initial login request failed to encode")))
            }
            initiateLoginRequest.httpBody = body
            anonAuth.handledTsv1Request(request: initiateLoginRequest, errorHandler: completionHandler) {
                (loginAction: IdentityLoginAction) -> Void in
                let semaphore = DispatchSemaphore(value: 0)
                let actionQueue = DispatchQueue.global()
                actionQueue.async() {
                    var loginAction = loginAction
                    while loginAction.loginAction {
                        if loginAction.type == "fetch" {
                            break
                        }
                        var data: [String: String]? = nil
                        actionQueue.async() {
                            data = actionHandler(loginAction)
                            semaphore.signal()
                        }
                        semaphore.wait()

                        var body: Data?
                        if loginAction.contentType == "application/x-www-form-urlencoded" {
                            body = try? encodeBodyAsUrl(data!).data(using: .utf8)
                        } else {
                            body = try? JSONSerialization.data(withJSONObject: data)
                        }
                        guard let bodyData = body else {
                            return completionHandler(.failure(E3dbError.encodingError("data returned from actionHandler failed to encode")))
                        }
                        var loginActionRequest = URLRequest(url: URL(string: loginAction.actionUrl)!)
                        loginActionRequest.httpMethod = "POST"
                        loginActionRequest.httpBody = bodyData
                        loginActionRequest.addValue(loginAction.contentType, forHTTPHeaderField: "Content-Type")
                        anonAuth.handledTsv1Request(request: loginActionRequest, errorHandler: completionHandler) {
                            (newLoginAction: IdentityLoginAction) -> Void in
                            loginAction = newLoginAction
                            semaphore.signal()
                        }
                        semaphore.wait(timeout: .now() + 10)
                    }
                    // Final request
                    var finalRequest = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/tozid/redirect")!)
                    finalRequest.httpMethod = "POST"
                    guard let finalRequestBody = try? JSONSerialization.data(withJSONObject: [
                        "realm_name": realmInfo.domain/*self.realmName*/,
                        "session_code": loginAction.context["session_code"],
                        "execution": loginAction.context["execution"],
                        "tab_id": loginAction.context["tab_id"],
                        "client_id": loginAction.context["client_id"],
                        "auth_session_id": loginAction.context["auth_session_id"],
                        "code_verifier": pkceVerifier,
                    ]) else {
                        return completionHandler(.failure(E3dbError.encodingError("final body request failed to encode, login context contains invalid data")))
                    }
                    finalRequest.httpBody = finalRequestBody
                    var potentialToken: AgentToken? = nil
                    anonAuth.handledTsv1Request(request: finalRequest, errorHandler: completionHandler) {
                        (token: AgentToken) -> Void in
                        potentialToken = token
                        semaphore.signal()
                    }
                    semaphore.wait(timeout: .now() + 10)
                    guard let token = potentialToken else {
                        return completionHandler(.failure(E3dbError.networkError("failed to get access token")))
                    }
                    Client.readNoteByName(noteName: noteCredentials.name,
                                          privateEncryptionKey: noteCredentials.encryptionKeyPair.privateKey,
                                          publicEncryptionKey: noteCredentials.encryptionKeyPair.publicKey,
                                          publicSigningKey: noteCredentials.signingKeyPair.publicKey,
                                          privateSigningKey: noteCredentials.signingKeyPair.privateKey,
                                          additionalHeaders: ["X-TOZID-LOGIN-TOKEN": token.accessToken],
                                          apiUrl: self.apiUrl) {
                        result -> Void in
                        switch (result) {
                        case .failure(let error):
                            return completionHandler(.failure(error))
                        case .success(let note):
                            guard let idConfig = try? IdentityConfig(fromPassNote: note) else {
                                return completionHandler(.failure(E3dbError.jsonError(expected: "valid identity configuration", actual: "note data configuration failed to parse")))
                            }
                            let partialIdentity = PartialIdentity(idConfig: idConfig)
                            completionHandler(.success(Identity(fromPartial: partialIdentity, identityServiceToken: token)))
                        }
                    }
                }
            }
        }
    }

    public func register(username: String, password: String, email: String, token: String, firstName: String? = nil, lastName: String? = nil, emailEacpExpiryMinutes: Int = 60, completionHandler: @escaping E3dbCompletion<PartialIdentity>) {
        var username = username
        username = username.lowercased()

        guard let cryptoKeys = Client.generateKeyPair(),
        let signingKeys = Client.generateSigningKeyPair() else {
            return completionHandler(.failure(E3dbError.cryptoError("Failed to generate crypto or signing key pairs needed for registration")))
        }
        let publicSigningKey = ["ed25519": signingKeys.publicKey] 
        let publicEncryptionKey = ["curve25519": cryptoKeys.publicKey]
        let identity = IdentityRequest(realmName: realmName, username: username, publicKeys: publicEncryptionKey, signingKeys: publicSigningKey, firstName: firstName, lastName: lastName)
        let payload = IdentityRegisterRequest(realmRegistrationToken: token, realmName: self.realmName, identity: identity)

        var request = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/register")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(payload)

        Authenticator.request(unauthedReq: request) {
            result -> Void in
            Authenticator.handleURLResponse(result, completionHandler) {
                (identityResponse: IdentityRegisterResponse) -> Void in
                self.info(errorHandler: completionHandler) {
                    (realmInfo: PublicRealmInfo) -> Void in
                    do {
                        let storageConfig = Config(clientName: username,
                                               clientId: UUID.init(uuidString: identityResponse.identity.toznyId!)!,
                                               apiKeyId: identityResponse.identity.apiKeyID!,
                                               apiSecret: identityResponse.identity.apiKeySecret!,
                                               publicKey: cryptoKeys.publicKey,
                                               privateKey: cryptoKeys.secretKey,
                                               baseApiUrl: URL(string: self.apiUrl)!,
                                               publicSigKey: signingKeys.publicKey,
                                               privateSigKey: signingKeys.secretKey)

                        let idConfig = IdentityConfig(realmName: realmInfo.name,
                                                  realmDomain: realmInfo.domain,
                                                  appName: self.appName,
                                                  apiUrl: self.apiUrl,
                                                  username: username,
                                                  userId: identityResponse.identity.id,
                                                  brokerTargetUrl: self.brokerTargetUrl,
                                                  firstName: firstName,
                                                  lastName: lastName,
                                                  storageConfig: storageConfig)

                        let noteCreds = try Crypto.deriveNoteCreds(realmName: idConfig.realmName, username: username, password: password)
                        let passNote = PasswordNoteData(identity: idConfig, store: storageConfig)

                        let partialIdentity = PartialIdentity(idConfig: idConfig)

                        let passData = try JSONEncoder().encode(passNote)
                        let passNoteData = try JSONSerialization.jsonObject(with: passData) as! [String: String]

                        let tozIdEacp = TozIdEacp(realmName: idConfig.realmDomain)
                        let options = NoteOptions(IdString: noteCreds.name, maxViews: -1, expires: false, eacp: tozIdEacp)
                        partialIdentity.storeClient.writeNote(data: passNoteData,
                                                      recipientEncryptionKey: noteCreds.encryptionKeyPair.publicKey,
                                                      recipientSigningKey: noteCreds.signingKeyPair.publicKey,
                                                      options: options) {
                            result -> Void in
                            switch(result) {
                            case .failure(let error):
                                return completionHandler(.failure(error))
                            case .success:
                                let brokerClientID = identityResponse.realmBrokerIdentityToznyID
                                if brokerClientID == nil || brokerClientID == "00000000-0000-0000-0000-000000000000" {
                                    return completionHandler(.success(partialIdentity))
                                }
                                partialIdentity.storeClient.getClientInfo(clientId: UUID(uuidString: brokerClientID!)) {
                                    result -> Void in
                                    switch(result) {
                                    case .failure(let error):
                                        return completionHandler(.failure(error))
                                    case .success(let brokerInfo as ClientInfo):
                                    // Email recovery notes through broker
                                        self.registerBrokerEmailHelper(username: username, brokerInfo: brokerInfo, email: email, firstName: firstName, lastName: lastName, partialIdentity: partialIdentity, passwordNoteContents: passNoteData) {
                                            err -> Void in
                                            if let err = err {
                                                return completionHandler(.failure(err))
                                            }
                                            // OTP recovery notes through broker
                                            self.registerBrokerOTPHelper(username: username, brokerInfo: brokerInfo, passwordNoteContents: passNoteData, partialIdentity: partialIdentity) {
                                                err -> Void in
                                                if let err = err {
                                                    return completionHandler(.failure(err))
                                                }
                                                return completionHandler(.success(partialIdentity))
                                            }
                                        }
                                    }
                                }
                                return
                            }
                        }
                    } catch {
                        return completionHandler(.failure(E3dbError.generalError(error.localizedDescription)))
                    }
                }
            }
        }
    }

    public func initiateBrokerLogin(username: String, brokerUrl: String? = nil, errorHandler: @escaping E3dbCompletion<Bool>) {
        var brokerUrl = brokerUrl
        if brokerUrl == nil {
            brokerUrl = self.apiUrl + "/v1/identity/broker/realm/" + self.realmName + "/challenge"
        }
        var username = username
        username = username.lowercased()

        var request = URLRequest(url: URL(string: brokerUrl!)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accepts")
        guard let body = try? JSONSerialization.data(withJSONObject: ["username": username, "action": "challenge"]) else {
            return errorHandler(.failure(E3dbError.jsonError(expected: "{'username': '...', 'action': '...'}", actual: "invalid json object"))) 
        }
        request.httpBody = body
        Authenticator.handledRequest(unauthedReq: request, errorHandler: errorHandler) {
            (resp: [String:String]) -> Void in
            return errorHandler(.success(true))
        }
    }

    public func completeEmailRecovery(otp: String, noteID: String, recoveryUrl: String? = nil, completionHandler: @escaping E3dbCompletion<PartialIdentity>) {
        let auth = ["email_otp": otp]
        self.completeBrokerLogin(authResponse: auth, noteId: noteID, brokerType: "email_otp", brokerUrl: recoveryUrl, completionHandler: completionHandler)
    }

    public func completeOTPRecovery(otp: String, noteId: String, recoverUrl: String? = nil, completionHandler: @escaping  E3dbCompletion<PartialIdentity>) {
        let auth = ["tozny_otp": otp]
        self.completeBrokerLogin(authResponse: auth, noteId: noteId, brokerType: "tozny_otp", brokerUrl: nil, completionHandler: completionHandler)
    }

    public func completeBrokerLogin(authResponse: [String: Any], noteId: String, brokerType: String, brokerUrl: String?, completionHandler: @escaping E3dbCompletion<PartialIdentity>) {
        var brokerUrl = brokerUrl
        if brokerUrl == nil {
            brokerUrl = self.apiUrl + "/v1/identity/broker/realm/" + self.realmName + "/login"
        }
        guard let cryptoKeys = Client.generateKeyPair(),
              let signingKeys = Client.generateSigningKeyPair() else {
            return completionHandler(.failure(E3dbError.cryptoError("Failed to generate crypto or signing key pairs needed for registration")))
        }
        let payload: [String: Any] = ["auth_response": authResponse,
                       "note_id": noteId,
                       "public_key": cryptoKeys.publicKey,
                       "signing_key": signingKeys.publicKey,
                       "action": "login"]

        var request = URLRequest(url: URL(string: brokerUrl!)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return completionHandler(.failure(E3dbError.jsonError(expected: "valid payload", actual: "")))
        }
        request.httpBody = body
        Authenticator.handledRequest(unauthedReq: request, errorHandler: completionHandler) {
            (resp: [String: String]) -> Void in
            guard let transferId = resp["transferId"] else {
                return completionHandler(.failure(E3dbError.jsonError(expected: "transfer id missing", actual: "nil")))
            }
            
            // fetch broker key transfer note
            Client.readNote(noteID: transferId, privateEncryptionKey: cryptoKeys.secretKey, publicEncryptionKey: cryptoKeys.publicKey, publicSigningKey: signingKeys.publicKey, privateSigningKey: signingKeys.secretKey, apiUrl: self.apiUrl) {
                result -> Void in
                switch(result) {
                case .failure(let error):
                    return completionHandler(.failure(error))
                case .success(let note):
                    guard let brokerKey = note.data["broker_key"],
                    let username = note.data["username"],
                    let brokerCreds = try? Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: brokerKey, type: brokerType) else {
                        return completionHandler(.failure(E3dbError.cryptoError("Couldn't generate credentials from broker note")))
                    }
                    Client.readNoteByName(noteName: brokerCreds.name,
                                            privateEncryptionKey: brokerCreds.encryptionKeyPair.privateKey,
                                            publicEncryptionKey: brokerCreds.encryptionKeyPair.publicKey,
                                            publicSigningKey: brokerCreds.signingKeyPair.publicKey,
                                            privateSigningKey: brokerCreds.signingKeyPair.privateKey,
                                            apiUrl: self.apiUrl) {
                        result -> Void in
                        switch(result) {
                        case .failure(let error):
                            return completionHandler(.failure(error))
                        case .success(let note):
                            guard let idConfig = try? IdentityConfig(fromPassNote: note) else {
                                return completionHandler(.failure(E3dbError.jsonError(expected: "Saved Note", actual: "Invalid Note Json")))
                            }
                            completionHandler(.success(PartialIdentity(idConfig: idConfig)))
                        }
                    }
                }
            }
        }
    }

    // MARK: Registration helpers

    func registerBrokerEmailHelper(username: String, brokerInfo: ClientInfo, email: String, firstName: String?, lastName: String?, partialIdentity: PartialIdentity, passwordNoteContents: NoteData, errorHandler: @escaping (E3dbError?) -> Void) {
        do {
            let brokerKeyNoteName = try Crypto.hash(stringToHash: String(format: "brokerKey:%@@realm:%@", username, self.realmName))
            let brokerKey = try Crypto.randomBytes(length: 64)
            let brokerNoteCreds = try Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: brokerKey, type: "email_otp")
            var emailName = ""
            if firstName != nil {
                emailName += firstName!
            }
            if lastName != nil {
                emailName += " " + lastName!
            }
            let templateOpts = ["name": emailName]
            let emailEacp = EmailEacp(emailAddress: email, template: "claim_account", providerLink: self.brokerTargetUrl,  templateFields: templateOpts)
            let brokerNoteOptions = NoteOptions(IdString: brokerKeyNoteName, maxViews: -1, expires: false, eacp: emailEacp)

            let brokerKeyNoteData = ["broker_key": brokerKey, "username": username]
            partialIdentity.storeClient.writeNote(data: brokerKeyNoteData, recipientEncryptionKey: brokerInfo.publicKey.curve25519, recipientSigningKey: brokerInfo.signingKey!.ed25519, options: brokerNoteOptions) {
                result -> Void in
                switch (result) {
                case .failure(let error):
                    return errorHandler(error)
                case .success(let brokerKeyNote):
                    let brokerPassNoteOptions = NoteOptions(IdString: brokerNoteCreds.name, maxViews: -1, expires: false, eacp: LastAccessEacp(lastReadNoteId: brokerKeyNote.noteID!))
                    partialIdentity.storeClient.writeNote(data: passwordNoteContents,
                                                          recipientEncryptionKey: brokerNoteCreds.encryptionKeyPair.publicKey,
                                                          recipientSigningKey: brokerNoteCreds.signingKeyPair.publicKey,
                                                          options: brokerPassNoteOptions) {
                        result -> Void in
                        switch (result) {
                        case .failure(let error):
                            return errorHandler(error)
                        case .success:
                            return errorHandler(nil)
                        }
                    }
                }
            }
        } catch {
            errorHandler(E3dbError.generalError(error.localizedDescription))
        }
    }

    func registerBrokerOTPHelper(username: String, brokerInfo: ClientInfo, passwordNoteContents: NoteData, partialIdentity: PartialIdentity, errorHandler: @escaping (E3dbError?) -> Void) {
        do {
            let brokerToznyOTPKeyNoteName = try Crypto.hash(stringToHash: String(format: "broker_otp:%@@realm:%@", username, self.realmName))
            let brokerToznyOTPKey = try Crypto.randomBytes(length: 64)
            let brokerToznyOTPNoteCreds = try Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: brokerToznyOTPKey, type: "tozny_otp")
            let brokerOtpNoteOptions = NoteOptions(IdString: brokerToznyOTPKeyNoteName, maxViews: -1, expires: false, eacp: TozOtpEacp(include: true))
            partialIdentity.storeClient.writeNote(data: ["broker_key": brokerToznyOTPKey, "username": username],
                                                  recipientEncryptionKey: brokerInfo.publicKey.curve25519,
                                                  recipientSigningKey: brokerInfo.signingKey!.ed25519,
                                                  options: brokerOtpNoteOptions) {
                result -> Void in
                switch (result) {
                case .failure(let error):
                    return errorHandler(error)
                case .success(let writtenBrokerNote):
                    let brokerPassNoteOptions = NoteOptions(IdString: brokerToznyOTPNoteCreds.name, maxViews: -1, expires: false, eacp: LastAccessEacp(lastReadNoteId: writtenBrokerNote.noteID!))
                    partialIdentity.storeClient.writeNote(data: passwordNoteContents,
                                                          recipientEncryptionKey: brokerToznyOTPNoteCreds.encryptionKeyPair.publicKey,
                                                          recipientSigningKey: brokerToznyOTPNoteCreds.signingKeyPair.publicKey,
                                                          options: brokerPassNoteOptions) {
                        result -> Void in
                        switch (result) {
                        case .failure(let error):
                            return errorHandler(error)
                        case .success:
                            return errorHandler(nil)
                        }
                    }
                }
            }
        } catch {
            errorHandler(E3dbError.generalError(error.localizedDescription))
        }
    }
}
