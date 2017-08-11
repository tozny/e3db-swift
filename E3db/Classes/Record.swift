//
//  Record.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes
import Result

public typealias CypherData = [String: String]
public typealias PlainMeta  = [String: String]

public struct RecordData {
    let data: [String: String]

    public init(data: [String: String]) {
        self.data = data
    }
}

struct MetaRequest: Ogra.Encodable {
    let writerId: String
    let userId: String
    let type: String
    let plain: PlainMeta

    public func encode() -> JSON {
        return JSON.object([
            "writer_id": writerId.encode(),
            "user_id": userId.encode(),
            "type": type.encode(),
            "plain": plain.encode(),
        ])
    }
}

public struct Meta: Argo.Decodable {
    public let recordId: String
    public let writerId: String
    public let userId: String
    public let type: String
    public let plain: PlainMeta
    public let created: Date
    public let lastModified: Date
    public let version: String?

    public static func decode(_ j: JSON) -> Decoded<Meta> {
        let tmp = curry(Meta.init)
            <^> j <| "record_id"
            <*> j <| "writer_id"
            <*> j <| "user_id"
            <*> j <| "type"

        // split decode fixes: "expression was too complex
        // to be solved in reasonable time."
        //
        // The >>- (flatMap) decodes to [String: String]
        // and ?? coalesces to empty default value
        return tmp
            <*> ((j <|? "plain").flatMap { PlainMeta.decode($0 ?? JSON.object([:])) })
            <*> j <|  "created"
            <*> j <|  "last_modified"
            <*> j <|? "version"
    }
}

struct RecordRequest: Ogra.Encodable {
    let meta: MetaRequest
    let data: CypherData

    public func encode() -> JSON {
        return JSON.object([
            "meta": meta.encode(),
            "data": data.encode()
        ])
    }
}

public struct Record: Argo.Decodable {
    public let meta: Meta
    public let data: CypherData

    public static func decode(_ j: JSON) -> Decoded<Record> {
        return curry(Record.init)
            <^> j  <| "meta"
            <*> ((j <| "data").flatMap { CypherData.decode($0) })
    }
}

// MARK: Write Record

extension E3db {
    private struct CreateRecordRequest: Request {
        typealias ResponseObject = Record
        let api: Api
        let record: RecordRequest

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.POST, payload: record.encode())
        }
    }

    private func write(_ type: String, data: RecordData, plain: PlainMeta, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {
        guard let cypher = try? Crypto.encrypt(recordData: data, ak: ak) else {
            return completion(Result(error: .cryptoError("Failed to encrypt record")))
        }

        let meta = MetaRequest(
            writerId: config.clientId,
            userId: config.clientId,    // for now
            type: type,
            plain: plain
        )
        let record = RecordRequest(meta: meta, data: cypher)

        let req = CreateRecordRequest(api: api, record: record)
        authedClient.perform(req) { result in

            // TODO: Better error handling
            completion(result.mapError { _ in E3dbError.error })
        }
    }

    public func write(_ type: String, data: RecordData, plain: PlainMeta, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { (result) in
            switch result {
            case .success(let ak):
                self.write(type, data: data, plain: plain, ak: ak, completion: completion)
            case .failure(let error):
                completion(Result(error: error))
            }
        }
    }
}

// MARK: Read Record

extension E3db {
    private struct RecordRequest: Request {
        typealias ResponseObject = Record
        let api: Api
        let recordId: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
                .appendingPathComponent(recordId)
            let req = URLRequest(url: url)
            return req
        }
    }

    // Workaround for strange scoping issue related to Result(try ...) inside "perform" callback,
    // error reads: "Invalid conversion from throwing function of type '(_) throws -> _' to
    // non-throwing function type '(Result<_.ResponseObject, SwishError>) -> Void'"
    private func decryptRecord(record: Record, accessKey: AccessKey) -> Result<RecordData, E3dbError> {
        return Result(try Crypto.decrypt(cypherData: record.data, ak: accessKey))
    }

    private func readRaw(_ recordId: String, completion: @escaping E3dbCompletion<Record>) {
        let req = RecordRequest(api: api, recordId: recordId)
        authedClient.perform(req) { (result) in
            switch result {
            case .success(let r):
                completion(Result(value: r))
            case .failure(.serverError(code: 401, data: _)):
                completion(Result(error: .apiError(401, "Unauthorized")))
            case .failure(.serverError(code: 404, data: _)):
                completion(Result(error: .apiError(404, "Record \(recordId) not found.")))
            case .failure(_):
                completion(Result(error: .error))
            }
        }
    }

    public func read(recordId: String, completion: @escaping E3dbCompletion<RecordData>) {
        readRaw(recordId) { (result) in
            switch result {
            case .success(let r):
                let clientId = self.config.clientId
                self.getAccessKey(writerId: r.meta.writerId, userId: r.meta.userId, readerId: clientId, recordType: r.meta.type) { (akResult) in
                    switch akResult {
                    case .success(let ak):
                        completion(self.decryptRecord(record: r, accessKey: ak))
                    case .failure(let err):
                        completion(Result(error: err))
                    }
                }
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}
