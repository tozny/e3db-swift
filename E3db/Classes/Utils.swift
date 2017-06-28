//
//  Utils.swift
//  E3db
//

import Foundation
import Sodium

enum Endpoints: String {
    case records, clients

    private static let apiUrl = URL(string: "https://dev.e3db.com/v1/storage")!

    func url() -> URL {
        return Endpoints.apiUrl.appendingPathComponent(self.rawValue)
    }
}

public typealias JsonPayload = [String: Any]

protocol Encodable {
    var asJson: JsonPayload { get }
}

extension URLRequest {
    mutating func setJsonPost(payload: JsonPayload) -> URLRequest {
        self.httpMethod  = "POST"
        self.jsonPayload = payload
        self.setValue("appication/json", forHTTPHeaderField: "Accept")
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return self
    }
}
