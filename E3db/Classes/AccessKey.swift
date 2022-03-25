//
//  AccessKey.swift
//  E3db
//

import Foundation
//import ToznyHeimdallr
import Result
import Sodium
import Swish

// MARK: Access Key Management

class AkCacheKey: NSObject {
    let writerId: UUID
    let userId: UUID
    let recordType: String

    init(writerId: UUID, userId: UUID, recordType: String) {
        self.writerId   = writerId
        self.userId     = userId
        self.recordType = recordType
    }
}

class AccessKey: NSObject {
    let rawAk: RawAccessKey
    let eakInfo: EAKInfo

    init(rawAk: RawAccessKey, eakInfo: EAKInfo) {
        self.rawAk   = rawAk
        self.eakInfo = eakInfo
    }
}

/// Encrypted Access Key information type to facilitate offline crypto
public struct EAKInfo: Codable {

    /// encrypted key used for encryption operations
    public let eak: String

    /// client ID of user authorizing access (typically the writer)
    public let authorizerId: UUID

    /// public key of the authorizer
    public let authorizerPublicKey: ClientKey

    /// client ID of user performing the signature (typically the writer)
    public let signerId: UUID?

    /// public signing key of the signer
    public let signerSigningKey: SigningKey?

    enum CodingKeys: String, CodingKey {
        case eak
        case authorizerId        = "authorizer_id"
        case authorizerPublicKey = "authorizer_public_key"
        case signerId            = "signer_id"
        case signerSigningKey    = "signer_signing_key"
    }
}

// MARK: Get Access Key

extension Client {
    private struct GetEAKRequest: E3dbRequest {
        typealias ResponseObject = EAKInfo
        let api: Api
        let writerId: UUID
        let userId: UUID
        let readerId: UUID
        let recordType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .accessKeys)
            let url  = base / writerId.uuidString / userId.uuidString / readerId.uuidString / recordType
            return URLRequest(url: url)
        }
    }

    func decryptEak(eakInfo: EAKInfo, clientPrivateKey: String) -> E3dbResult<RawAccessKey> {
        return Result(try Crypto.decrypt(eakInfo: eakInfo, clientPrivateKey: clientPrivateKey))
    }

    // checks cache and server for access key, returning error if not found
    func getStoredAccessKey(writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        let cacheKey = AkCacheKey(writerId: writerId, userId: userId, recordType: recordType)

        // Check for EAKInfo in local cache
        if let storedAk = akCache.object(forKey: cacheKey) {
            return completion(Result(value: storedAk))
        }

        // Get AK from server
        let req = GetEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.perform(req) { result in
            // Server had EAK entry
            switch result {
            case .success(let eakInfo):
                let res = self.decryptEak(eakInfo: eakInfo, clientPrivateKey: self.config.privateKey)
                    .map { AccessKey(rawAk: $0, eakInfo: eakInfo) }
                completion(res)
            case .failure(let err):
                completion(Result(error: E3dbError(swishError: err)))
            }
        }
    }

    // checks cache and server for access key, generating one if not found
    func getAccessKey(writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        let cacheKey = AkCacheKey(writerId: writerId, userId: userId, recordType: recordType)
        getStoredAccessKey(writerId: writerId, userId: userId, readerId: readerId, recordType: recordType) { result in
            // found access key, return it immediately
            guard case .failure(let error) = result else {
                return completion(result)
            }

            // access key not found in cache and eak not found on server, generate raw ak
            guard case .apiError(code: 404, message: _) = error,
                let ak = Crypto.generateAccessKey() else {
                    return completion(Result(error: .cryptoError("Could not create access key")))
            }

            // encrypts and stores AK on server and local cache before returning it to caller
            self.putAccessKey(ak: ak, cacheKey: cacheKey, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType, completion: completion)
        }
    }
}

// MARK: Put Access Key

extension Client {
    private struct PutEAKRequest: E3dbRequest {
        typealias ResponseObject = EmptyResponse
        let api: Api
        let eak: EncryptedAccessKey
        let writerId: UUID
        let userId: UUID
        let readerId: UUID
        let recordType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .accessKeys)
            let url  = base / writerId.uuidString / userId.uuidString / readerId.uuidString / recordType
            var req  = URLRequest(url: url)
            return req.asJsonRequest(.put, payload: ["eak": eak])
        }
    }

    private func putAccessKey(eak: EncryptedAccessKey, writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<Void>) {
        let req = PutEAKRequest(api: api, eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.performDefault(req, completion: completion)
    }

    func putAccessKey(ak: RawAccessKey, cacheKey: AkCacheKey, writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        getClientInfo(clientId: readerId) { result in
            switch result {
            case .success(let client):
                // encrypt ak
                guard let authorizerPrivKey = Box.SecretKey(base64UrlEncoded: self.config.privateKey),
                      let eak = Crypto.encrypt(accessKey: ak, readerClientKey: client.publicKey, authorizerPrivKey: authorizerPrivKey) else {
                        return completion(Result(error: E3dbError.cryptoError("Failed to encrypt access key")))
                }

                // update server
                self.putAccessKey(eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType) { result in
                    let response  = EAKInfo(eak: eak, authorizerId: self.config.clientId, authorizerPublicKey: client.publicKey, signerId: self.config.clientId, signerSigningKey: client.signingKey)
                    let accessKey = AccessKey(rawAk: ak, eakInfo: response)

                    // update local cache
                    if case .success = result {
                        self.akCache.setObject(accessKey, forKey: cacheKey)
                    }

                    completion(result.map { accessKey })
                }
            case .failure(let error):
                completion(Result(error: error))
            }
        }
    }
}

// MARK: Delete Access Key

extension Client {
    private struct DeleteEAKRequest: E3dbRequest {
        typealias ResponseObject = EmptyResponse
        let api: Api
        let writerId: UUID
        let userId: UUID
        let readerId: UUID
        let recordType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .accessKeys)
            let url  = base / writerId.uuidString / userId.uuidString / readerId.uuidString / recordType
            var req  = URLRequest(url: url)
            req.httpMethod = RequestMethod.delete.rawValue
            return req
        }
    }

    func deleteAccessKey(writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<Void>) {
        // remove from cache
        let cacheKey = AkCacheKey(writerId: writerId, userId: userId, recordType: recordType)
        akCache.removeObject(forKey: cacheKey)

        // remove from server
        let req = DeleteEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.performDefault(req, completion: completion)
    }
}

// MARK: EAK Management

extension Client {

    /// Generate encrypted access key for offline encryption operations. `EAKInfo` objects are
    /// safe to store in insecure storage as they are encrypted with the current client's private key.
    /// This method will store the key with E3db for later access.
    ///
    /// - SeeAlso: `getReaderKey(writerId:userId:type:completion:)` for geting keys from E3db.
    ///
    /// - Parameters:
    ///   - type: The kind of data that will be encrypted with this key
    ///   - completion: A handler to call when this operation completes to provide the EAKInfo result
    public func createWriterKey(type: String, completion: @escaping E3dbCompletion<EAKInfo>) {
        let id = config.clientId
        getAccessKey(writerId: id, userId: id, readerId: id, recordType: type) { result in
            completion(result.map { $0.eakInfo })
        }
    }

    /// Get the encrypted access key for offline encryption operations. The EAKInfo object must have
    /// been created beforehand, and shared with this client.
    ///
    /// - SeeAlso: `createWriterKey(type:completion:)` for sending keys to E3db.
    ///
    /// - Parameters:
    ///   - writerId: The client ID of the writer of an encrypted document.
    ///   - userId: The client ID of the user for which an encrypted document was created.
    ///   - type: The kind of data that will be encrypted with this key
    ///   - completion: A handler to call when this operation completes to provide the EAKInfo result, or error if not found.
    public func getReaderKey(writerId: UUID, userId: UUID, type: String, completion: @escaping E3dbCompletion<EAKInfo>) {
        getStoredAccessKey(writerId: writerId, userId: userId, readerId: config.clientId, recordType: type) { result in
            completion(result.map { $0.eakInfo })
        }
    }
}
