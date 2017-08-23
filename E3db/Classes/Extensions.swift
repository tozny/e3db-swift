//
//  Extensions.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes
import Result

extension Formatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}

extension Date {
    var iso8601: String {
        return Formatter.iso8601.string(from: self)
    }
}

extension String {
    var dateFromISO8601: Date? {
        return Formatter.iso8601.date(from: self)
    }
}

extension Date: Ogra.Encodable, Argo.Decodable {
    public func encode() -> JSON {
        return self.iso8601.encode()
    }

    public static func decode(_ json: JSON) -> Decoded<Date> {
        guard case let .string(s) = json,
            let d = s.dateFromISO8601 else {
                return .typeMismatch(expected: "Date", actual: json)
        }
        return pure(d)
    }
}

extension URL: Ogra.Encodable, Argo.Decodable {
    public func encode() -> JSON {
        return self.absoluteString.encode()
    }

    public static func decode(_ json: JSON) -> Decoded<URL> {
        guard case let .string(s) = json,
            let url = URL(string: s) else {
                return .typeMismatch(expected: "URL", actual: json)
        }
        return pure(url)
    }
}

extension UUID: Ogra.Encodable, Argo.Decodable {
    public func encode() -> JSON {
        return self.uuidString.encode()
    }

    public static func decode(_ json: JSON) -> Decoded<UUID> {
        guard case let .string(s) = json,
            let uuid = UUID(uuidString: s) else {
                return .typeMismatch(expected: "UUID", actual: json)
        }
        return pure(uuid)
    }
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

extension String {
    func capitalizedFirst() -> String {
        let firstIndex = self.index(startIndex, offsetBy: 1)
        return self.substring(to: firstIndex).capitalized + self.substring(from: firstIndex)
    }
}

extension Array where Element: ResultProtocol {
    public func sequence<T, E>() -> Result<[T], E> {
        var accum: [T] = []
        accum.reserveCapacity(self.count)

        for case let result as Result<T, E> in self {
            switch result {
            case let .success(value): accum.append(value)
            case let .failure(error): return .failure(error)
            }
        }

        return Result(accum)
    }
}

extension APIClient {
    func performDefault<T: Request>(_ request: T, completion: @escaping (Result<T.ResponseObject, E3dbError>) -> Void) {
        perform(request, completionHandler: { completion($0.mapError(E3dbError.init)) })
    }
}
