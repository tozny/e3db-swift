//
//  Utils.swift
//  E3db
//

import Foundation
import Sodium
import Result
import Argo
import Swish

public enum E3dbError: Swift.Error {
    case cryptoError(String)        // Message
    case configError(String)        // Message
    case jsonError(String, String)  // (Expected, Actual)
    case apiError(Int, String)      // (StatusCode, Message)
    case error
}

struct Api {
    let baseUrl: URL

    func url(endpoint: Endpoint) -> URL {
        return baseUrl.appendingPathComponent(endpoint.rawValue)
    }
}

enum Endpoint: String {
    case records, clients
}

extension URLRequest {
    mutating func asJsonRequest(_ method: RequestMethod, payload: JSON) -> URLRequest {
        self.httpMethod  = method.rawValue
        self.jsonPayload = payload.JSONObject()
        self.setValue("appication/json", forHTTPHeaderField: "Accept")
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return self
    }
}
