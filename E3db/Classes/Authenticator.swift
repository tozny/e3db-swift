//
//  Authenticator.swift
//  E3db
//

import Foundation
import Result

public struct AuthenticatorConfig {
    let publicSigningKey: String
    let privateSigningKey: String
    let apiUrl: String
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

    init(anonConfig config: AuthenticatorConfig, urlSession: URLSession = URLSession.shared) {
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


    public func handledTsv1Request<T: Decodable, Z: Any>(request: URLRequest, errorHandler: @escaping E3dbCompletion<Z>, successHandler: @escaping (T) -> Void) {
        tsv1Request(request: request) {
            result -> Void in
            Authenticator.handleURLResponse(result, errorHandler, completionHandler: successHandler)
        }
    }
    
    static func request(unauthedReq request: URLRequest, urlSession: URLSession = URLSession.shared, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
        let task = urlSession.dataTask(with: request, result: completionHandler)
        task.resume()
    }

    static func handledRequest<T: Decodable, Z: Any>(unauthedReq request: URLRequest, urlSession: URLSession = URLSession.shared, errorHandler: @escaping E3dbCompletion<Z>, successHandler: @escaping (T) -> Void) {
        let task = urlSession.dataTask(with: request) {
            result -> Void in
            Authenticator.handleURLResponse(result, errorHandler, completionHandler: successHandler)
        }
        task.resume()
    }

    public func tsv1Request(request unauthedReq: URLRequest, completionHandler: @escaping (Result<(URLResponse, Data), Error>) -> Void) {
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

    static func handleURLResponse<T: Decodable, Z: Any>(_ result: Result<(URLResponse, Data), Error>,_ errorHandler: @escaping E3dbCompletion<Z>, completionHandler: @escaping (T) -> Void) {
        let handleError = errorCompletion(errorHandler)
        switch (result) {
        case .failure(let error):
            let err = E3dbError.networkError(error.localizedDescription)
            return handleError(err)
        case .success(let response, let data):
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                    return handleError(E3dbError.apiError(code: httpResponse.statusCode, message: String(decoding: data, as: UTF8.self)))
                }
                guard let response = try? Api.decoder.decode(T.self, from: data) else {
                    return handleError(E3dbError.jsonError(expected: String(describing: type(of: T.self)), actual: String(decoding: data, as: UTF8.self)))
                }
                completionHandler(response)
            } else {
                return handleError(E3dbError.networkError("invalid network response"))
            }
        }
    }
}

public func errorCompletion<T: Any>(_ errorHandler: @escaping E3dbCompletion<T>) -> (E3dbError) -> Void {
    return {
        error -> Void in
        errorHandler(.failure(error))
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

public func encodeBodyAsUrl(_ data: [String: Any]) throws -> String {
    var urlEncodedValues = ""
    for (key, value) in data {
        if let value = value as? [String: Any] {
            urlEncodedValues += try encodeBodyAsUrl(value)
        }
        if let value = value as? String {
            guard let encodedValue = value.encodeURIComponent() else {
                throw E3dbError.generalError("value \(value) could not be urlencoded")
            }
            urlEncodedValues += key + "=" + encodedValue + "&"
        } else {
            throw E3dbError.apiError(code: 400, message: "body could not be url encoded")
        }
    }
    if urlEncodedValues.last! == "&" { 
        return String(urlEncodedValues.dropLast())
    }
    return urlEncodedValues
}

extension String {
    func encodeURIComponent() -> String? {
        var characterSet = CharacterSet.alphanumerics
        characterSet.insert(charactersIn: "-_.!~*'()")
        return self.addingPercentEncoding(withAllowedCharacters: characterSet)
    }
}

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
