//
//  Extensions.swift
//  E3db
//

import Foundation
import Result
import Swish

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

extension URLRequest {
    mutating func asJsonRequest<T: Encodable>(_ method: RequestMethod, payload: T) -> URLRequest {
        self.httpMethod = method.rawValue
        self.httpBody   = try? kStaticJsonEncoder.encode(payload)
        self.setValue("application/json", forHTTPHeaderField: "Accept")
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return self
    }
}

// Extends Swish.Request to override their `parse`
// method to replace with custom json decoder
extension E3dbRequest where ResponseObject: Decodable {
    func parse(_ data: Data) throws -> ResponseObject {
        return try kStaticJsonDecoder.decode(ResponseObject.self, from: data)
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
    private func parse<T: Request>(_ data: Data, request: T) -> Result<T.ResponseObject, SwishError> {
        do {
            let parsed = try request.parse(data)
            return .success(parsed)
        } catch {
            return .failure(.decodingError(error))
        }
    }

    private func validate(_ httpResponse: HTTPResponse) -> Result<Data, SwishError> {
        guard case (200...299) = httpResponse.code else {
            return .failure(.serverError(code: httpResponse.code, data: httpResponse.data))
        }
        return .success(httpResponse.data)
    }

    func performDefault<T: Request>(_ request: T, completion: @escaping E3dbCompletion<T.ResponseObject>) {
        perform(request) { completion($0.mapError(E3dbError.init)) }
    }

    func upload<T: Request>(fileAt: URL, request: T, session: URLSession, completion: @escaping E3dbCompletion<T.ResponseObject>) {
        let req  = request.build()
        let task = session.uploadTask(with: req, fromFile: fileAt) { data, response, error in
            let resp: Result<T.ResponseObject, SwishError>
            switch (data, response, error) {
            case let (_, urlResp as HTTPURLResponse, .some(err)):
                resp = .failure(.urlSessionError(err, response: urlResp))
            case let (.some(body), urlResp as HTTPURLResponse, _):
                let httpResp = HTTPResponse(data: body, response: urlResp)
                resp = self.validate(httpResp).flatMap { self.parse($0, request: request) }
            default:
                resp = .failure(.serverError(code: 400, data: nil))
            }
            completion(resp.mapError(E3dbError.init))
        }
        task.resume()
    }

    func download(_ request: URLRequest, session: URLSession, completion: @escaping E3dbCompletion<URL>) {
        let task = session.downloadTask(with: request) { localUrl, response, error in
            let resp: Result<URL, SwishError>
            switch (localUrl, response, error) {
            case let (_, urlResp as HTTPURLResponse, .some(err)):
                resp = .failure(.urlSessionError(err, response: urlResp))
            case let (.some(local), urlResp as HTTPURLResponse, _):
                let httpResp = HTTPResponse(data: Data(), response: urlResp)
                resp = self.validate(httpResp).map { _ in local }
            default:
                resp = .failure(.serverError(code: 400, data: nil))
            }
            completion(resp.mapError(E3dbError.init))
        }
        task.resume()
    }
}

extension Data {
    public init?(base64UrlEncoded string: String) {
        guard let data = try? Crypto.base64UrlDecoded(string: string) else {
            return nil
        }
        self = data
    }

    public func base64UrlEncodedString() -> String? {
        return try? Crypto.base64UrlEncoded(data: self)
    }
}

extension FileManager {
    static func tempBinFile() -> URL? {
        let tempUrl: URL
        if #available(iOS 10.0, *) {
            tempUrl = FileManager.default.temporaryDirectory
        } else {
            tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let fullUrl = tempUrl
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        guard FileManager.default.createFile(atPath: fullUrl.path, contents: nil) else { return nil }
        return fullUrl
    }
}

extension FileHandle {
    func read(until byte: UInt8) -> Data {
        var buffer = Data()
        var next   = readData(ofLength: 1)
        while !next.isEmpty && next[0] != byte {
            buffer.append(next)
            next = readData(ofLength: 1)
        }
        return buffer
    }
}

extension SignedDocument: Decodable where T: Decodable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sig    = try values.decode(String.self, forKey: .signature)
        let doc    = try values.decode(T.self, forKey: .document)
        self.init(document: doc, signature: sig)
    }
}

extension SignedDocument: Encodable where T: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signature, forKey: .signature)
        try container.encode(document, forKey: .document)
    }
}

extension ClientMeta: Signable {
    public func serialized() -> String {
        return [
            CodingKeys.writerId.rawValue: AnySignable(writerId),
            CodingKeys.userId.rawValue: AnySignable(userId),
            CodingKeys.type.rawValue: AnySignable(type),
            CodingKeys.plain.rawValue: AnySignable(plain ?? PlainMeta()) // default to empty object for serialization
        ].serialized()
    }
}

// MARK: Signable Extensions

extension Bool: Signable {
    public func serialized() -> String {
        return self ? "true" : "false"
    }
}

extension NSNumber: Signable {
    public func serialized() -> String {
        return "\(self)"
    }
}

extension String: Signable {
    /// Encodes the string using the JSONEncoder, with modifications to match other SDKs
    /// (e.g. Java's Jackson Object Mapper, and JavaScript's JSON.stringify). Matching other
    /// E3db SDK implementations is required for document signature verification.
    ///
    /// The Swift JSONEncoder will escape a forward slash, as shown here:
    /// https://github.com/apple/swift-corelibs-foundation/blob/d23f4d7a4151d959ac185eca1c0f14de2c8dc73a/Foundation/JSONSerialization.swift#L407
    /// so this function will unescape it, again to match implementations in other languages.
    ///
    /// - Returns: An encoded string, matching other E3db SDK implementations, for signature verification.
    public func serialized() -> String {
        // Encodes the string as part of an array, then removes the first and last bytes
        // (representing the opening and closing brackets). This will provide the proper
        // escaping for most string values, but it also escapes a forward slash, so we
        // replace any occurrences of those.
        let array   = try? kStaticJsonEncoder.encode([self])
        let string  = array?.advanced(by: 1).dropLast(1)
        let value   = string.flatMap { String(bytes: $0, encoding: .utf8) }
        let escaped = value?.replacingOccurrences(of: "\\/", with: "/")
        return escaped ?? ""
    }
}

extension UUID: Signable {
    public func serialized() -> String {
        return uuidString.lowercased().serialized()
    }
}

extension Array: Signable where Element: Signable {
    public func serialized() -> String {
        return "[\(self.map { $0.serialized() }.joined(separator: ","))]"
    }
}

extension Dictionary: Signable where Key == String, Value: Signable {
    public func serialized() -> String {
        let joined = self
            .sorted { $0.key.compare($1.key, options: [.literal]) == .orderedAscending }
            .map { elem in "\"\(elem.key)\":\(elem.value.serialized())" }
            .joined(separator: ",")
        return "{\(joined)}"
    }
}

extension Optional: Signable where Wrapped: Signable {
    public func serialized() -> String {
        return self.map { $0.serialized() } ?? "null"
    }
}
