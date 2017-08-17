//
//  E3db.swift
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

import ResponseDetective

public typealias E3dbResult<T>     = Result<T, E3dbError>
public typealias E3dbCompletion<T> = (E3dbResult<T>) -> Void

public class E3db {
    internal let api: Api
    internal let config: Config
    internal let authedClient: APIClient

    private static let debugSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)
        return URLSession(configuration: configuration)
    }()

    internal static let staticClient: APIClient = {
        let session   = E3db.debugSession
        let performer = NetworkRequestPerformer(session: session)
        return APIClient(requestPerformer: performer)
    }()

    internal static var akCache = [AkCacheKey: AccessKey]()

    public init(config: Config) {
        // TODO: refactor the URL optional
        self.api    = Api(baseUrl: URL(string: config.baseApiUrl)!)
        self.config = config

        let credentials   = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let httpClient    = HeimdallrHTTPClientURLSession(urlSession: E3db.debugSession)
        let heimdallr     = Heimdallr(tokenURL: api.tokenUrl(), credentials: credentials, httpClient: httpClient)
        let reqPerformer  = AuthedRequestPerformer(authenticator: heimdallr, session: E3db.debugSession)
        self.authedClient = APIClient(requestPerformer: reqPerformer)
    }
}

// MARK: Get Client Info

extension E3db {
    public struct ClientInfo: Ogra.Encodable, Argo.Decodable {
        let clientId: String
        let publicKey: ClientKey
        let validated: Bool

        public func encode() -> JSON {
            return JSON.object([
                "client_id": clientId.encode(),
                "public_key": publicKey.encode(),
                "validated": validated.encode()
                ])
        }

        public static func decode(_ j: JSON) -> Decoded<ClientInfo> {
            return curry(ClientInfo.init)
                <^> j <| "client_id"
                <*> j <| "public_key"
                <*> j <| "validated"
        }
    }

    struct ClientInfoRequest: Request {
        typealias ResponseObject = ClientInfo
        let api: Api
        let clientId: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .clients)
                .appendingPathComponent(clientId)
            return URLRequest(url: url)
        }
    }

    // TODO: defaults to current client, probably change later
    public func getClientInfo(clientId: String? = nil, completion: @escaping E3dbCompletion<ClientInfo>) {
        let req = ClientInfoRequest(api: api, clientId: clientId ?? config.clientId)
        authedClient.perform(req) { result in
            // TODO: Better error handling
            completion(result.mapError { _ in E3dbError.error })
        }
    }
}

