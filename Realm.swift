//
// Created by michael lee on 2/21/20.
//

import Foundation

public class Application {
    let apiUrl: String
    let appName: String
    let realmName: String
    let brokerTargetUrl: String

    public init(apiUrl: String, appName: String, realmName: String, brokerTargetUrl: String) {
        self.apiUrl = apiUrl
        self.appName = appName
        self.realmName = realmName
        self.brokerTargetUrl = brokerTargetUrl
    }

    public func login(username: String, password: String, actionHandler: @escaping (IdentityLoginAction) -> [String:String], completionHandler: @escaping (Result<Identity, Error>) -> Void) {
        do {
            var username = username
            username = username.lowercased()

//            let semaphore = DispatchSemaphore(value: 0)
//            let actionQueue = DispatchQueue.global()

            guard let noteCredentials = try? Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: password) else {
                return completionHandler(.failure(E3dbError.cryptoError("Couldn't derive crypto keys from username and password")))
            }

            let anonAuth = Authenticator(anonConfig: AuthenticatorConfig(publicSigningKey: noteCredentials.signingKeyPair.publicKey, privateSigningKey: noteCredentials.signingKeyPair.privateKey, apiUrl: self.apiUrl, clientId: nil))

            var initiateLoginRequest = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/login")!)
            initiateLoginRequest.httpMethod = "POST"
            initiateLoginRequest.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "realm_name": self.realmName, "app_name": self.appName, "login_style": "api"])

            anonAuth.handledTsv1Request(request: initiateLoginRequest, errorHandler: completionHandler) {
                (loginSession: [String:String]) -> Void in
                print("this is login session \(loginSession)")

                guard let encodedString = try? encodeBodyAsUrl(loginSession),
                      let encodedBody = encodedString.data(using: .utf8) else {
                    return completionHandler(.failure(E3dbError.apiError(code: 500, message: "Response from server was not encodable")))
                }

                // TODO: FIX ME - needed because of ngrok
                var sessionRequest = URLRequest(url: URL(string: self.apiUrl + "/auth/realms/" + self.realmName + "/protocol/openid-connect/auth")!)
                sessionRequest.httpMethod = "POST"
                sessionRequest.addValue("application/json", forHTTPHeaderField: "Accepts")
                sessionRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                sessionRequest.httpBody = encodedBody

                anonAuth.handledTsv1Request(request: sessionRequest, errorHandler: completionHandler) {
                    (loginAction: IdentityLoginAction) -> Void in
                    let semaphore = DispatchSemaphore(value: 0)
                    let actionQueue = DispatchQueue.global()
                    actionQueue.async() {
                        var loginAction = loginAction
                        print("this is the login action \(loginAction)")

    //                    while loginAction.loginAction {
    //                        print("beginning")
    //                        if loginAction.type == "fetch"{
    //
    //                            break
    //                        }
    //                        var data: [String: String]? = nil
    //                        actionQueue.async() {
    //                            data = actionHandler(loginAction)
    //                            semaphore.signal()
    //                        }
    //                        semaphore.wait(timeout: .now() + 100) // TODO: adjust timeout?
    //
    //                        var body: Data? // TODO: Handle my questions :(
    //                        if loginAction.contentType == "application/x-www-form-urlencoded" {
    //                            body = try? encodeBodyAsUrl(data!).data(using: .utf8)
    //                        } else {
    //                            body = try? JSONSerialization.data(withJSONObject: data)
    //                        }
    //
    //                        var loginActionRequest = URLRequest(url: URL(string: loginAction.actionUrl)!)
    //                        loginActionRequest.httpMethod = "POST"
    //                        loginActionRequest.httpBody = body
    //                        loginActionRequest.addValue(loginAction.contentType, forHTTPHeaderField: "Content-Type")
    //                        anonAuth.handledTsv1Request(request: loginActionRequest, errorHandler: completionHandler) {
    //                            (newLoginAction: IdentityLoginAction) -> Void in
    //                            loginAction = newLoginAction
    //                            semaphore.signal()
    //                        }
    //                        semaphore.wait(timeout: .now() + 100) // TODO: SEMAPHORES HERE??
    //                    }

                        print("before final request")
                        print("this is login action \(loginAction)")
                        // Final request
                        var finalRequest = URLRequest(url: URL(string: self.apiUrl + "/v1/identity/tozid/redirect")!)
                        finalRequest.httpMethod = "POST"
                        guard let finalRequestBody = try? JSONSerialization.data(withJSONObject: [
                            "realm_name": self.realmName,
                            "session_code": loginAction.context["session_code"],
                            "execution": loginAction.context["execution"],
                            "tab_id": loginAction.context["tab_id"],
                            "client_id": loginAction.context["client_id"],
                            "auth_session_id": loginAction.context["auth_session_id"],
                        ]) else {
                            return completionHandler(.failure(E3dbError.jsonError(expected: "failed to marshal final request body", actual: "uh")))
                        }
                        finalRequest.httpBody = finalRequestBody

                        var potentialAccessToken: String? = nil
                        anonAuth.handledTsv1Request(request: finalRequest, errorHandler: completionHandler) {
                            (tokenResp: [String: String]) -> Void in // TODO: Define this as a concrete type?
                            potentialAccessToken = tokenResp["access_token"]
                            semaphore.signal()
                        }
                        semaphore.wait(timeout: .now() + 5) // TODO: SEMAPHORES HERE??
                        guard let accessToken = potentialAccessToken else {
                            return completionHandler(.failure(E3dbError.networkError("failed to get access token")))
                        }

                        print("sign private '\(noteCredentials.signingKeyPair.privateKey)'")
                        print("sign public '\(noteCredentials.signingKeyPair.publicKey)'")
                        print("encryption private '\(noteCredentials.encryptionKeyPair.privateKey)'")
                        print("encryption public '\(noteCredentials.encryptionKeyPair.publicKey)'")
                        print("this is the not name \(noteCredentials.name)")

                        print("this is api url \(self.apiUrl)")
                        Identity.readNoteByName(noteName: noteCredentials.name,
                                                privateEncryptionKey: noteCredentials.encryptionKeyPair.privateKey,
                                                publicEncryptionKey: noteCredentials.encryptionKeyPair.publicKey,
                                                publicSigningKey: noteCredentials.signingKeyPair.publicKey,
                                                privateSigningKey: noteCredentials.signingKeyPair.privateKey,
                                                additionalHeaders: ["X-TOZID-LOGIN-TOKEN": accessToken],
                                                apiUrl: self.apiUrl) {
                            result -> Void in
                            switch(result) {
                            case .failure(let error):
                                return completionHandler(.failure(error))
                            case .success(let note):
                                print("this is the note found \(note)")
                            }
                        }
                    }
                }
            }
        } catch {
            completionHandler(.failure(E3dbError.apiError(code: 500, message: "Unexpected error attempting to login")))
        }
    }

    public func repeatLoginActions(data: [String: String]) {

    }

    public func register(username: String, password: String, email: String, token: String, firstName: String? = nil, lastName: String? = nil, emailEacpExpiryMinutes: Int = 60, completionHandler: @escaping (Result<PartialIdentity, Error>)
    -> Void) {
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
            Authenticator.handleURLResponse(urlResult: result, errorHandler: completionHandler) {
                (identityResponse: IdentityRegisterResponse) -> Void in
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

                    let idConfig = IdentityConfig(realmName: self.realmName,
                                                  appName: self.appName,
                                                  apiUrl: self.apiUrl,
                                                  username: username,
                                                  userId: identityResponse.identity.id,
                                                  brokerTargetUrl: identityResponse.realmBrokerIdentityToznyID,
                                                  firstName: firstName,
                                                  lastName: lastName,
                                                  storageConfig: storageConfig)

                    let noteCreds = try Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: password)
                    let passNote = SavedNote(identity: idConfig, store: storageConfig)

                    let partialIdentity = PartialIdentity(idConfig: idConfig)

                    let data = try JSONEncoder().encode(passNote)
                    let jsonData = try JSONSerialization.jsonObject(with: data) as! [String: String]


                    let tozIdEacp = TozIdEacp(realmName: self.realmName)
                    let options = NoteOptions(IdString: noteCreds.name, maxViews: -1, expires: false, eacp: tozIdEacp)
                    partialIdentity.writeNote(data: jsonData, recipientEncryptionKey: noteCreds.encryptionKeyPair.publicKey, recipientSigningKey: noteCreds.signingKeyPair.publicKey, options: options) {
                        result -> Void in
                        switch(result) {
                        case .failure(let error):
                            print("failed to write note \(error)")
                            return completionHandler(.failure(error))
                        case .success:
                            let brokerClientID = identityResponse.realmBrokerIdentityToznyID
                            if brokerClientID == nil || brokerClientID == "00000000-0000-0000-0000-000000000000" {
                                print("broker client is was not found \(brokerClientID)")
                                return completionHandler(.success(partialIdentity))
                            }
                            partialIdentity.storeClient.getClientInfo(clientId: UUID(uuidString: brokerClientID!)) {
                                result -> Void in
                                switch(result) {
                                case .failure(let error):
                                    return completionHandler(.failure(error))
                                case .success(let brokerInfo as ClientInfo):
                                    // Email recovery notes through broker
                                    self.registerBrokerEmailHelper(username: username, brokerInfo: brokerInfo, email: email, firstName: firstName, lastName: lastName, partialIdentity: partialIdentity, passwordNoteContents: jsonData) {
                                        err -> Void in
                                        if let err = err {
                                            return completionHandler(.failure(err))
                                        }

                                        // OTP recovery notes through broker
                                        self.registerBrokerOTPHelper(username: username, brokerInfo: brokerInfo, passwordNoteContents: jsonData, partialIdentity: partialIdentity) {
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
                    return completionHandler(.failure(error))
                }
            }
        }
    }

    func registerBrokerEmailHelper(username: String, brokerInfo: ClientInfo, email: String, firstName: String?, lastName: String?, partialIdentity: PartialIdentity, passwordNoteContents: NoteData, completionHandler: @escaping (Error?) -> Void) {
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

            let brokerKeyNoteData = ["brokerKey": brokerKey, "username": username]
            partialIdentity.writeNote(data: brokerKeyNoteData, recipientEncryptionKey: brokerInfo.publicKey.curve25519, recipientSigningKey: brokerInfo.signingKey!.ed25519, options: brokerNoteOptions) {
                result -> Void in
                switch (result) {
                case .failure(let error):
                    return completionHandler(error)
                case .success(let brokerKeyNote):
                    let brokerPassNoteOptions = NoteOptions(IdString: brokerNoteCreds.name, maxViews: -1, expires: false, eacp: LastAccessEacp(lastReadNoteId: brokerKeyNote.noteID!))
                    partialIdentity.writeNote(data: passwordNoteContents, recipientEncryptionKey: brokerNoteCreds.encryptionKeyPair.publicKey, recipientSigningKey: brokerNoteCreds.signingKeyPair.publicKey, options: brokerPassNoteOptions) {
                        result -> Void in
                        switch (result) {
                        case .failure(let error):
                            return completionHandler(error)
                        case .success:
                            return completionHandler(nil)
                        }
                    }
                }
            }
        } catch {
            completionHandler(error)
        }
    }


    func registerBrokerOTPHelper(username: String, brokerInfo: ClientInfo, passwordNoteContents: NoteData, partialIdentity: PartialIdentity, completionHandler: @escaping (Error?) -> Void) {
        do {
            let brokerToznyOTPKeyNoteName = try Crypto.hash(stringToHash: String(format: "broker_otp:%@@realm:%@", username, self.realmName))
            let brokerToznyOTPKey = try Crypto.randomBytes(length: 64)
            let brokerToznyOTPNoteCreds = try Crypto.deriveNoteCreds(realmName: self.realmName, username: username, password: brokerToznyOTPKey, type: "tozny_otp")
            let brokerOtpNoteOptions = NoteOptions(IdString: brokerToznyOTPKeyNoteName, maxViews: -1, expires: false, eacp: TozOtpEacp(include: true))
            partialIdentity.writeNote(data: ["brokerKey": brokerToznyOTPKey, "username": username], recipientEncryptionKey: brokerInfo.publicKey.curve25519, recipientSigningKey: brokerInfo.signingKey!.ed25519, options: brokerOtpNoteOptions) {
                result -> Void in
                switch (result) {
                case .failure(let error):
                    return completionHandler(error)
                case .success(let writtenBrokerNote):
                    let brokerPassNoteOptions = NoteOptions(IdString: brokerToznyOTPNoteCreds.name, maxViews: -1, expires: false, eacp: LastAccessEacp(lastReadNoteId: writtenBrokerNote.noteID!))
                    partialIdentity.writeNote(data: passwordNoteContents, recipientEncryptionKey: brokerToznyOTPNoteCreds.encryptionKeyPair.publicKey, recipientSigningKey: brokerToznyOTPNoteCreds.signingKeyPair.publicKey, options: brokerPassNoteOptions) {
                        result -> Void in
                        switch (result) {
                        case .failure(let error):
                            return completionHandler(error)
                        case .success:
                            return completionHandler(nil)
                        }
                    }
                }
            }
        } catch {
            completionHandler(error)
        }
    }
}
