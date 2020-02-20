//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 1/7/20.
//

import Foundation
import ToznySwish
import Sodium

public class Identity {
    let storeClient: Client
    let api: Api
    let config: Config
    let authClient: Authenticator
    

    init(config: Config, urlSession: URLSession, scheduler: @escaping Scheduler) {
        self.api     = Api(baseUrl: config.baseApiUrl)
        self.config  = config
        self.storeClient = Client(config: config, urlSession: urlSession)
        let authConfig = AuthenticatorConfig(publicSigningKey: config.publicSigKey, privateSigningKey: config.privateSigKey, baseApiUrl: config.baseApiUrl.absoluteString, clientId: config.clientId.uuidString.lowercased())
        self.authClient = Authenticator(config: authConfig, urlSession: urlSession)
    }
    
    public convenience init(config: Config, urlSession: URLSession = .shared) {
        self.init(config: config, urlSession: urlSession, scheduler: mainQueueScheduler)
    }
    
    // First Party Login
    public func login(username: String, password: String) {
    }
    
    public func register(username: String, password: String, token: String, realmName: String, email: String, firstName: String, lastName: String, emailEacpExpiryMinutes: Int = 60) throws {
        var username = username
        username = username.lowercased()
        
        let cryptoKeys = Client.generateKeyPair()
        let signingKeys = Client.generateSigningKeyPair()
        
        let payload = IdentityRegisterRequest(realmRegistationToken: token, realmName: realmName, username: username, publicEncryptionKey: cryptoKeys!.publicKey, publicSigningKey: signingKeys!.publicKey, firstName: firstName, lastName: lastName)
        
        var request = URLRequest(url: URL(string: self.authClient.config.baseApiUrl + "/v1/identity/register")!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(payload)
        self.authClient.tsv1AuthenticatedRequest(request: request) {
            result -> Void in
            switch(result) {
            case .failure:
                break
            case .success:
                
                
                
                
                
                break
            }
        }
        
        
        
        
        
        
    }
    
    public func readNoteByName(noteName: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["id_string": noteName]
        Identity.internalReadNote(params: params, authenticator: self.authClient) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self))))
                    }
                    guard let note = try? JSONDecoder().decode(Note.self, from: data) else {
                        return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                    }
                    guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: self.config.privateKey, publicEncryptionKey: self.config.publicKey, publicSigningKey: self.config.publicSigKey) else {
                        return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                    }
                    return completionHandler(.success(unencryptedNote))
                } else {
                    return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                }
            }
        }
    }
    
    static func readNoteByName(noteName: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, baseApiUrl: String = "https://api.e3db.com", completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["id_string": noteName]
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, baseApiUrl: baseApiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Identity.internalReadNote(params: params, authenticator: auth) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self))))
                    }
                    guard let note = try? JSONDecoder().decode(Note.self, from: data) else {
                        return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                    }
                    guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: publicEncryptionKey, publicSigningKey: publicSigningKey) else {
                        return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                    }
                    return completionHandler(.success(unencryptedNote))
                } else {
                    return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                }
            }
        }
    }
    
    
    // ReadNote
    public func readNote(noteID: String, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let params = ["note_id": noteID]
        Identity.internalReadNote(params: params, authenticator: self.authClient) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self))))
                    }
                    guard let note = try? JSONDecoder().decode(Note.self, from: data) else {
                        return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                    }
                    guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: self.config.privateKey, publicEncryptionKey: self.config.publicKey, publicSigningKey: self.config.publicSigKey) else {
                        return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                    }
                    return completionHandler(.success(unencryptedNote))
                } else {
                    return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                }
            }
        }
    }
    
    // TODO: default api constant
    static func readNote(noteID: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, baseApiUrl: String = "https://api.e3db.com", completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, baseApiUrl: baseApiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        let params = ["note_id": noteID]
        Identity.internalReadNote(params: params, authenticator: auth) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self))))
                    }
                    guard let note = try? JSONDecoder().decode(Note.self, from: data) else {
                        return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                    }
                    guard let unencryptedNote = try? Crypto.decryptNote(encryptedNote: note, privateEncryptionKey: privateEncryptionKey, publicEncryptionKey: publicEncryptionKey, publicSigningKey: publicSigningKey) else {
                        return completionHandler(.failure(E3dbError.cryptoError("Failed to decrypt note")))
                    }
                    return completionHandler(.success(unencryptedNote))
                } else {
                    return completionHandler(.failure(E3dbError.jsonError(expected: "JSON Note", actual: String(decoding: data, as: UTF8.self))))
                }
            }
        }
    }

    static func internalReadNote(params: [String: String], authenticator: Authenticator, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        var paramString: String = ""
        for (key, value) in params {
            paramString += key + "=" + value + "&"
        }
        var request = URLRequest(url: URL(string: authenticator.config.baseApiUrl + "/v2/storage/notes?" + paramString)!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        authenticator.tsv1AuthenticatedRequest(request: request, completionHandler: completionHandler)
    }
    
    public func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void){
        var options = options
        if options == nil {
            options = NoteOptions(clientId: self.config.clientId.uuidString)
        } else {
            options?.clientId = self.config.clientId.uuidString
        }
        
        let encryptionKeyPair = EncryptionKeyPair(privateKey: self.config.privateKey, publicKey: self.config.publicKey)
        let signingKeyPair = SigningKeyPair(privateKey: self.config.privateSigKey, publicKey: self.config.publicSigKey)
        
        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: self.authClient) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(NSError(domain: String(data: data, encoding: String.Encoding.utf8)!, code: httpResponse.statusCode, userInfo: nil)))
                    }
                    let note = try! JSONDecoder().decode(Note.self, from: data)

                    return completionHandler(.success(note))
                } else {
                    return completionHandler(.failure(NSError(domain: "Failed to decode response", code: 1, userInfo: nil)))
                }
            }
        }
    }
    
    static func writeNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String, privateSigningKey: String, urlSession: URLSession = URLSession.shared, baseApiUrl: String = "https://api.e3db.com", options: NoteOptions?, completionHandler: @escaping (Result<Note, Error>) -> Void) {
        let encryptionKeyPair = EncryptionKeyPair(privateKey: privateEncryptionKey, publicKey: publicEncryptionKey)
        let signingKeyPair = SigningKeyPair(privateKey: privateSigningKey, publicKey: publicSigningKey)
        let config = AuthenticatorConfig(publicSigningKey: publicSigningKey, privateSigningKey: privateSigningKey, baseApiUrl: baseApiUrl, clientId: nil)
        let auth = Authenticator(config: config, urlSession: urlSession)
        Identity.internalWriteNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeyPair, signingKeys: signingKeyPair, authenticator: auth) {
            result -> Void in
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                break
            case .success(let response, let data):
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                        return completionHandler(.failure(NSError(domain: String(data: data, encoding: String.Encoding.utf8)!, code: httpResponse.statusCode, userInfo: nil)))
                    }
                    let note = try! JSONDecoder().decode(Note.self, from: data)
                    return completionHandler(.success(note))
                } else {
                    return completionHandler(.failure(NSError(domain: "Failed to decode response", code: 1, userInfo: nil)))
                }
            }
        }
    }
    
    static func internalWriteNote(data: NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair, authenticator: Authenticator, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        let encryptedNote = createEncryptedNote(data: data, recipientEncryptionKey: recipientEncryptionKey, recipientSigningKey: recipientSigningKey, options: options, encryptionKeys: encryptionKeys, signingKeys: signingKeys)
                
        var request = URLRequest(url: URL(string: authenticator.config.baseApiUrl + "/v2/storage/notes")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(encryptedNote!)
        authenticator.tsv1AuthenticatedRequest(request: request, completionHandler: completionHandler)
    }
    
    
    static func createEncryptedNote(data:NoteData, recipientEncryptionKey: String, recipientSigningKey: String, options: NoteOptions?, encryptionKeys: EncryptionKeyPair, signingKeys: SigningKeyPair) -> Note? {
        let accessKey = Crypto.generateAccessKey()
        guard let authorizerPrivKey = Box.SecretKey(base64UrlEncoded: encryptionKeys.privateKey),
            let encryptedAccessKey = Crypto.encrypt(accessKey: accessKey!, readerClientKey: ClientKey(curve25519: recipientEncryptionKey), authorizerPrivKey: authorizerPrivKey) else {
                return nil
        }
        let noteKeys = NoteKeys(mode: "Sodium", recipientSigningKey: recipientSigningKey, writerSigningKey: signingKeys.publicKey, writerEncryptionKey: encryptionKeys.publicKey, encryptedAccessKey: encryptedAccessKey)
        let unencryptedNote = Note(data: data, noteKeys: noteKeys, noteOptions: options)
        return Crypto.encryptNote(note: unencryptedNote, accessKey: accessKey!, signingKey: signingKeys.privateKey)
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

func deriveNoteCreds(realmName: String, username: String, password: String) throws -> String {
    let nameSeed = String(format:"%@@realm:%@", username, realmName)
    let noteName = try Crypto.hash(stringToHash: nameSeed)
    return noteName
}
