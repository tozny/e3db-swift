//
//  Identity.swift
//  E3db
//
//  Created by michael lee on 1/7/20.
//

import Foundation
import ToznySwish
import ToznyHeimdallr

public final class Identity {
    let authedClient: APIClient
    let storeClient: Client
    let api: Api
    let config: Config
    

    init(config: Config, urlSession: URLSession, scheduler: @escaping Scheduler) {
        self.api     = Api(baseUrl: config.baseApiUrl)
        self.config  = config
        let httpClient    = HeimdallrHTTPClientURLSession(urlSession: urlSession)
        let credentials   = OAuthClientCredentials(id: config.apiKeyId, secret: config.apiSecret)
        let tokenStore    = OAuthAccessTokenKeychainStore(service: config.clientId.uuidString)
        let heimdallr     = Heimdallr(tokenURL: api.tokenUrl, credentials: credentials, accessTokenStore: tokenStore, httpClient: httpClient)
        let authPerformer = AuthedRequestPerformer(authenticator: heimdallr, session: urlSession)
        self.authedClient = APIClient(requestPerformer: authPerformer, scheduler: scheduler)
        self.storeClient = Client(config: config, urlSession: urlSession)
    }
    
    public convenience init(config: Config, urlSession: URLSession = .shared) {
        self.init(config: config, urlSession: urlSession, scheduler: mainQueueScheduler)
    }
    
    // First Party Login
    public func login(username: String, password: String) {
        
        
    }
    // ReadNote
    
    //
}

func deriveNoteCreds(realmName: String, username: String, password: String) throws -> String {
    let nameSeed = String(format:"%@@realm:%@", username, realmName)
    let noteName = try Crypto.hash(stringToHash: nameSeed)
    return noteName
}
