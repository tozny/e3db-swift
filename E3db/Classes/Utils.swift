//
//  Utils.swift
//  E3db
//

import Foundation
import Sodium
import Result
import Argo

public enum E3dbError: Swift.Error {
    case cryptoError(String)        // Message
    case configError(String)        // Message
    case jsonError(String, String)  // (Expected, Actual)
    case apiError(Int, String)      // (StatusCode, Message)
    case error
}

enum Endpoints: String {
    case records, clients

    static let apiUrl = URL(string: "https://dev.e3db.com/v1/storage")!

    func url() -> URL {
        return Endpoints.apiUrl.appendingPathComponent(self.rawValue)
    }
}

extension URLRequest {
    mutating func setJsonPost(payload: JSON) -> URLRequest {
        self.httpMethod  = "POST"
        self.jsonPayload = payload.JSONObject()
        self.setValue("appication/json", forHTTPHeaderField: "Accept")
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return self
    }
}
