//
//  Authenticator.swift
//  E3db
//
//  Created by michael lee on 2/19/20.
//

import Foundation


// Extend URLSession to use Swift5's result type
extension URLSession {
    func dataTask(with url: URLRequest, result: @escaping (Result<(URLResponse, Data), Error>) -> Void) -> URLSessionDataTask {
        return dataTask(with: url) { (data, response, error) in
            if let error = error {
                result(.failure(error))
                return
            }
            guard let response = response, let data = data else {
                let error = NSError(domain: "error", code: 0, userInfo: nil)
                result(.failure(error))
                return
            }
            result(.success((response, data)))
        }
    }
}


public struct AuthenticatorConfig {
    let publicSigningKey: String
    let privateSigningKey: String
    let baseApiUrl: String
    let clientId: String?
}

// Authenticator to make TSV1 authenticated calls
public class Authenticator {
    let config: AuthenticatorConfig
    let urlSession: URLSession

    let TSV1_SUPPORTED_ALGORITHMS = ["TSV1-ED25519-BLAKE2B"]
    
    init(config: AuthenticatorConfig, urlSession: URLSession) {
        self.config = config
        self.urlSession = urlSession
    }

    public func tsv1AuthHeader(url: URL?, method: String?) -> String? {
        guard let url = url else {
            return nil
        }
        guard let method = method  else {
            return nil
        }
        
        let path = url.path
        var queryString = url.query
        if queryString != nil  {
            queryString = sortQueryParameters(query: queryString!)
        } else {
            queryString = ""
        }
        let timeStamp = Int(NSDate().timeIntervalSince1970)
        let authMethod = TSV1_SUPPORTED_ALGORITHMS[0]
        let nonce = UUID().uuidString.lowercased()
        let userId = self.config.clientId ?? ""
        
        let headerString = String(format: "%@; %@; %d; %@; uid:%@", authMethod, self.config.publicSigningKey, timeStamp, nonce, userId)
        let stringToSign = String(format: "%@; %@; %@; %@", path, queryString!, method, headerString)
        guard let hashToSign = try? Crypto.hash(stringToHash: stringToSign) else {
            return nil
        }
        guard let fullSignature = try? Crypto.sign(document: signableString(hashToSign), privateSigningKey: self.config.privateSigningKey) else {
            return nil
        }
        return String(format:"%@; %@", headerString, fullSignature.signature)
    }
    
    public func tsv1AuthenticatedRequest(request unauthedReq: URLRequest, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        guard let authHeader = tsv1AuthHeader(url: unauthedReq.url, method: unauthedReq.httpMethod) else {
            let error = NSError(domain: "header error", code: 0, userInfo: nil)
            completionHandler(.failure(error))
            return
        }
        var req = unauthedReq
        req.addValue(authHeader, forHTTPHeaderField: "Authorization")
        let task = self.urlSession.dataTask(with: req, result: completionHandler)
        task.resume()
    }
    
    static func request(request unauthedReq: URLRequest, urlSession: URLSession = URLSession.shared, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        let task = urlSession.dataTask(with: unauthedReq, result: completionHandler)
        task.resume()
    }
}

public struct signableString: Signable {
    let message: String
    init(_ message: String) {
        self.message = message
    }
    public func serialized() -> String {
        return message
    }
}
