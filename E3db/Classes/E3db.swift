//
//  E3db.swift
//  E3db
//

import Foundation
import Swish
import Result
import Sodium

import ResponseDetective

public class E3db {
    private let api: Api

    private static let debugClient: APIClient = {
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)

        let session   = URLSession(configuration: configuration)
        let performer = NetworkRequestPerformer(session: session)
        return APIClient(requestPerformer: performer)
    }()

    static let defaultClient = E3db.debugClient // or APIClient()

    public init?(config: Config) {
        guard let url = URL(string: config.baseApiUrl) else { return nil }
        self.api = Api(baseUrl: url)
    }
}

public struct Record {
}

// MARK: Registration

extension E3db {
    public static func register(email: String, findByEmail: Bool, apiUrl: String, completion: @escaping (Result<Config, E3dbError>) -> Void) {
        // ensure api url is valid
        guard let url = URL(string: apiUrl) else {
            return completion(Result(error: .configError("Invalid apiUrl: \(apiUrl)")))
        }

        // create key pair
        guard let keyPair = Sodium()?.box.keyPair() else {
            return completion(Result(error: .cryptoError("Could not create key pair.")))
        }

        // send registration request
        let api  = Api(baseUrl: url)
        let pubK = PublicKey(curve25519: keyPair.publicKey.base64URLEncodedString())
        let req  = RegisterRequest(api: api, email: email, publicKey: pubK, findByEmail: findByEmail)
        defaultClient.perform(req) { result in
            let resp = result
                .mapError { E3dbError.configError($0.localizedDescription) }
                .map { reg in
                    Config(
                        version: 1,
                        baseApiUrl: api.baseUrl.absoluteString,
                        apiKeyId: reg.apiKeyId,
                        apiSecret: reg.apiSecret,
                        clientId: reg.clientId,
                        clientEmail: email,
                        publicKey: pubK.curve25519,
                        privateKey: keyPair.secretKey.base64URLEncodedString()
                    )
            }
            completion(resp)
        }
    }
}
