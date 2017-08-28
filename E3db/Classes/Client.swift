//
//  Client.swift
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

#if DEBUG
import ResponseDetective
#endif

public typealias E3dbResult<T>     = Result<T, E3dbError>
public typealias E3dbCompletion<T> = (E3dbResult<T>) -> Void

public final class Client {
    internal let api: Api
    internal let config: Config
    internal let authedClient: APIClient

    internal static let session: URLSession = {
        #if DEBUG
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)
        return URLSession(configuration: configuration)
        #else
        return URLSession.shared
        #endif
    }()

    internal static var akCache = [AkCacheKey: AccessKey]()

    public init(config: Config) {
        self.api    = Api(baseUrl: config.baseApiUrl)
        self.config = config

        let httpClient    = HeimdallrHTTPClientURLSession(urlSession: Client.session)
        let credentials   = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let tokenStore    = OAuthAccessTokenKeychainStore(service: config.clientId.uuidString)
        let heimdallr     = Heimdallr(tokenURL: api.tokenUrl, credentials: credentials, accessTokenStore: tokenStore, httpClient: httpClient)
        let authPerformer = AuthedRequestPerformer(authenticator: heimdallr, session: Client.session)
        self.authedClient = APIClient(requestPerformer: authPerformer)
    }
}

// MARK: Key Generation

public struct KeyPair {
    public let publicKey: String
    public let secretKey: String
}

extension Client {
    public static func generateKeyPair() -> KeyPair? {
        guard let keyPair = Crypto.generateKeyPair() else { return nil }
        let pubKey  = keyPair.publicKey.base64URLEncodedString()
        let privKey = keyPair.secretKey.base64URLEncodedString()
        return KeyPair(publicKey: pubKey, secretKey: privKey)
    }
}

// MARK: Get Client Info

struct ClientInfo: Argo.Decodable {
    let clientId: UUID
    let publicKey: ClientKey
    let validated: Bool

    static func decode(_ j: JSON) -> Decoded<ClientInfo> {
        return curry(ClientInfo.init)
            <^> j <| "client_id"
            <*> j <| "public_key"
            <*> j <| "validated"
    }
}

extension Client {
    private struct ClientInfoRequest: Request {
        typealias ResponseObject = ClientInfo
        let api: Api
        let clientId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .clients) / clientId.uuidString
            return URLRequest(url: url)
        }
    }

    func getClientInfo(clientId: UUID? = nil, completion: @escaping E3dbCompletion<ClientInfo>) {
        let req = ClientInfoRequest(api: api, clientId: clientId ?? config.clientId)
        authedClient.performDefault(req, completion: completion)
    }
}

