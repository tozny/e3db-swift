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
        formatter.calendar   = Calendar(identifier: .iso8601)
        formatter.locale     = Locale(identifier: "en_US_POSIX")
        formatter.timeZone   = TimeZone(secondsFromGMT: 0)
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
        return iso8601.encode()
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
        return absoluteString.encode()
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
        return uuidString.lowercased().encode()
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
        self.setValue("application/json", forHTTPHeaderField: "Accept")
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return self
    }
}

extension URL {
    static func / (lhs: URL, rhs: String) -> URL {
        return lhs.appendingPathComponent(rhs)
    }
}

extension Array where Element: ResultProtocol {
    public func sequence<T, E>() -> Result<[T], E> {
        var accum: [T] = []
        accum.reserveCapacity(count)

        for case let result as Result<T, E> in self {
            switch result {
            case let .success(value):
                accum.append(value)
            case let .failure(error):
                return .failure(error)
            }
        }

        return Result(accum)
    }
}

extension APIClient {
    func performDefault<T: Request>(_ request: T, completion: @escaping (Result<T.ResponseObject, E3dbError>) -> Void) {
        perform(request) { completion($0.mapError(E3dbError.init)) }
    }
}

extension JSON: Signable {
    // swiftlint:disable switch_case_on_newline
    func serialize() -> String {
        switch self {
        case .null:                 return "null"
        case .bool(let b):          return b ? "true" : "false"
        case .number(let num):      return "\(num)"
        case .string(let string):   return "\"\(string)\""
        case .array(let array):     return "[\(array.map { $0.serialize() }.joined(separator: ","))]"
        case .object(let object):
            let inner = object
                .sorted { $0.key.compare($1.key, options: [.literal]) == .orderedAscending }
                .map { elem in "\"\(elem.key)\":\(elem.value.serialize())" }
                .joined(separator: ",")
            return "{\(inner)}"
        }
    }
}

extension Dictionary where Key == String, Value == String {
    func serialized() -> String {
        return JSON.object(mapValues(JSON.string)).serialize()
    }
}

extension String: Signable {
    public func serialized() -> String {
        return self
    }
}
