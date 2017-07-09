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
    let eak: String
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
    // non-throwing function type '(Result<_.ResponseObject, SwishError>) -> Void'
    private func decryptEak(eakResponse: EAKResponse, clientPrivateKey: String) -> Result<AccessKey, E3dbError> {
        return Result(try Crypto.decrypt(eakResponse: eakResponse, clientPrivateKey: clientPrivateKey))
    }

    func getAccessKey(writerId: String, userId: String, readerId: String, recordType: String, completion: @escaping E3dbCompletion<AccessKey>) {
        let cacheKey = AkCacheKey(writerId: writerId, readerId: readerId, recordType: recordType)

        // Found AK in local cache
        if let ak = E3db.akCache[cacheKey] {
            return completion(Result(value: ak))
        }

        let req = GetEAKRequest(api: api, writerId: writerId, userId: userId, readerId: readerId, recordType: recordType)
        authedClient.perform(req) { (result) in
            // Got AK from server
            if case .success(let akResponse) = result {
                let akResult = self.decryptEak(eakResponse: akResponse, clientPrivateKey: self.config.privateKey)

                // store in cache
                E3db.akCache[cacheKey] = akResult.value
                return completion(akResult)
            }

            // AK not found on server
            if case .failure(.serverError(404, _)) = result,
                let ak = try? Crypto.generateAccessKey() {


                // TODO: putAccessKey
                E3db.akCache[cacheKey] = ak
                return completion(Result(value: ak))
            }

            // TODO: Better error handling
            completion(Result(error: E3dbError.error))
        }
    }
}

// MARK: Put Access Key

extension E3db {


}
