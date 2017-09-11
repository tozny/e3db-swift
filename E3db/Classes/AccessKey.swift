//
//  AccessKey.swift
//  E3db
//

import Foundation
import Swish
import Result
import Sodium
import Heimdallr

import Argo
import Ogra
import Curry
import Runes

// MARK: Access Key Management

struct EAKResponse: Argo.Decodable {
    let eak: String
    let authorizerId: UUID
    let authorizerPublicKey: ClientKey

    static func decode(_ j: JSON) -> Decoded<EAKResponse> {
        return curry(EAKResponse.init)
            <^> j <| "eak"
            <*> j <| "authorizer_id"
            <*> j <| "authorizer_public_key"
    }
}

// MARK: Get Access Key

extension Client {
    private struct GetEAKRequest: Request {
        typealias ResponseObject = EAKResponse
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

    func decryptEak(eakResponse: EAKResponse, clientPrivateKey: String) -> E3dbResult<AccessKey> {
        return Result(try Crypto.decrypt(eakResponse: eakResponse, clientPrivateKey: clientPrivateKey))
    }

    func getAccessKey(writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        let cacheKey = AkCacheKey(recordType: recordType, writerId: writerId, readerId: readerId)

        // Check for AK in local cache
        if let ak = Client.akCache[cacheKey] {
            return completion(Result(value: ak))
        }

        // Get AK from server
        let req = GetEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.perform(req) { result in

            // Server had EAK entry
            if case .success(let akResponse) = result {
                let akResult = self.decryptEak(eakResponse: akResponse, clientPrivateKey: self.config.privateKey)

                // store in cache
                Client.akCache[cacheKey] = akResult.value
                return completion(akResult)
            }

            // EAK not found on server, generate one
            guard case .failure(.serverError(404, _)) = result,
                let ak = Crypto.generateAccessKey() else {
                return completion(Result(error: .cryptoError("Could not create access key")))
            }

            // stores AK on server and local cache before returning it to caller
            self.putAccessKey(ak: ak, cacheKey: cacheKey, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType, completion: completion)
        }
    }
}

// MARK: Put Access Key

extension Client {
    private struct PutEAKRequest: Request {
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
            return req.asJsonRequest(.PUT, payload: JSON.object(["eak": eak.encode()]))
        }
    }

    private func putAccessKey(eak: EncryptedAccessKey, writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<Void>) {
        let req = PutEAKRequest(api: api, eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.performDefault(req, completion: completion)
    }

    func putAccessKey(ak: AccessKey, cacheKey: AkCacheKey, writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        getClientInfo(clientId: readerId) { result in
            switch result {
            case .success(let client):
                // encrypt ak
                guard let authorizerPrivKey = Box.SecretKey(base64URLEncoded: self.config.privateKey),
                      let eak = Crypto.encrypt(accessKey: ak, readerClientKey: client.publicKey, authorizerPrivKey: authorizerPrivKey) else {
                        return completion(Result(error: .cryptoError("Failed to encrypt access key")))
                }

                // update server
                self.putAccessKey(eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType) { result in
                    // update local cache
                    if case .success = result {
                        Client.akCache[cacheKey] = ak
                    }
                    completion(result.map { ak })
                }
            case .failure(let error):
                completion(Result(error: error))
            }
        }
    }
}

// MARK: Delete Access Key

extension Client {
    private struct DeleteEAKRequest: Request {
        typealias ResponseObject = Void
        let api: Api
        let writerId: UUID
        let userId: UUID
        let readerId: UUID
        let recordType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .accessKeys)
            let url  = base / writerId.uuidString / userId.uuidString / readerId.uuidString / recordType
            var req  = URLRequest(url: url)
            req.httpMethod = RequestMethod.DELETE.rawValue
            return req
        }
    }

    func deleteAccessKey(writerId: UUID, userId: UUID, readerId: UUID, recordType: String, completion: @escaping E3dbCompletion<Void>) {
        // remove from cache
        let cacheKey = AkCacheKey(recordType: recordType, writerId: writerId, readerId: readerId)
        Client.akCache[cacheKey] = nil

        // remove from server
        let req = DeleteEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.performDefault(req, completion: completion)
    }
}
