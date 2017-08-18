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

struct GetEAKRequest: Request {
    typealias ResponseObject = EAKResponse
    let api: Api
    let writerId: String
    let userId: String
    let readerId: String
    let recordType: String

    func build() -> URLRequest {
        let url = api.url(endpoint: .accessKeys)
            .appendingPathComponent(writerId)
            .appendingPathComponent(userId)
            .appendingPathComponent(readerId)
            .appendingPathComponent(recordType)
        return URLRequest(url: url)
    }
}

struct PutEAKRequest: Request {
    typealias ResponseObject = EmptyResponse
    let api: Api
    let eak: EncryptedAccessKey
    let writerId: String
    let userId: String
    let readerId: String
    let recordType: String

    func build() -> URLRequest {
        let url = api.url(endpoint: .accessKeys)
            .appendingPathComponent(writerId)
            .appendingPathComponent(userId)
            .appendingPathComponent(readerId)
            .appendingPathComponent(recordType)
        var req = URLRequest(url: url)
        return req.asJsonRequest(.PUT, payload: JSON.object(["eak": eak.encode()]))
    }
}

struct EAKResponse: Argo.Decodable {
    let eak: String
    let authorizerId: String
    let authorizerPublicKey: ClientKey

    static func decode(_ j: JSON) -> Decoded<EAKResponse> {
        return curry(EAKResponse.init)
            <^> j <| "eak"
            <*> j <| "authorizer_id"
            <*> j <| "authorizer_public_key"
    }
}

// MARK: Get Access Key

extension E3db {

    // Workaround for strange scoping issue related to Result(try ...) inside "perform" callback,
    // error reads: "Invalid conversion from throwing function of type '(_) throws -> _' to
    // non-throwing function type '(Result<_.ResponseObject, SwishError>) -> Void'"
    internal func decryptEak(eakResponse: EAKResponse, clientPrivateKey: String) -> E3dbResult<AccessKey> {
        return Result(try Crypto.decrypt(eakResponse: eakResponse, clientPrivateKey: clientPrivateKey))
    }

    func getAccessKey(writerId: String, userId: String, readerId: String, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        let cacheKey = AkCacheKey(writerId: writerId, readerId: readerId, recordType: recordType)

        // Check for AK in local cache
        if let ak = E3db.akCache[cacheKey] {
            return completion(Result(value: ak))
        }

        // Get AK from server
        let req = GetEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.perform(req) { (result) in

            // Server had EAK entry
            if case .success(let akResponse) = result {
                let akResult = self.decryptEak(eakResponse: akResponse, clientPrivateKey: self.config.privateKey)

                // store in cache
                E3db.akCache[cacheKey] = akResult.value
                return completion(akResult)
            }

            // EAK not found on server, generate one
            guard case .failure(.serverError(404, _)) = result,
                let ak = Crypto.generateAccessKey() else {

                // TODO: Better error handling
                return completion(Result(error: E3dbError.error))
            }

            // stores AK on server and local cache before returning it to caller
            self.putAccessKey(ak: ak, cacheKey: cacheKey, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType, completion: completion)
        }
    }
}

// MARK: Put Access Key

extension E3db {

    private func putAccessKey(eak: EncryptedAccessKey, writerId: String, userId: String, readerId: String, recordType: String, completion: @escaping E3dbCompletion<Void>) {
        let req = PutEAKRequest(api: api, eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.perform(req) { (result) in
            // TODO: Better error handling
            completion(result.mapError { _ in E3dbError.error })
        }
    }

    func putAccessKey(ak: AccessKey, cacheKey: AkCacheKey, writerId: String, userId: String, readerId: String, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        getClientInfo(clientId: readerId) { (result) in
            switch result {
            case .success(let client):
                // encrypt ak
                guard let authorizerPrivKey = Box.SecretKey(base64URLEncoded: self.config.privateKey),
                    let eak = Crypto.encrypt(accessKey: ak, readerClientKey: client.publicKey, authorizerPrivKey: authorizerPrivKey) else {
                        return completion(Result(error: .cryptoError("Failed to encrypt access key")))
                }

                // update server
                self.putAccessKey(eak: eak, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType) { (result) in
                    // update local cache
                    if case .success = result {
                        E3db.akCache[cacheKey] = ak
                    }
                    completion(result.map { ak })
                }
            case .failure(let error):
                completion(Result(error: error))
            }
        }
    }
}
