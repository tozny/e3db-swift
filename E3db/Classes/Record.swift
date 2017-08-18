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

public struct RecordData {
    public let data: [String: String]
    public init(data: [String: String]) {
        self.data = data
    }
}

public typealias CypherData = [String: String]
public typealias PlainMeta  = [String: String]

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
        // the <|> provides a default empty value
        return tmp
            <*> ((j <| "plain").flatMap(PlainMeta.decode) <|> .success(PlainMeta()))
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

struct RecordResponse: Argo.Decodable {
    let meta: Meta
    let cypherData: CypherData

    static func decode(_ j: JSON) -> Decoded<RecordResponse> {
        return curry(RecordResponse.init)
            <^> j  <| "meta"
            <*> (j <| "data").flatMap(CypherData.decode)
    }
}

public struct Record {
    public let meta: Meta
    public let data: RecordData
}

// MARK: Write Record

extension E3db {
    private struct CreateRecordRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let record: RecordRequest

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.POST, payload: record.encode())
        }
    }

    internal func encrypt(_ data: RecordData, ak: AccessKey) -> E3dbResult<CypherData> {
        return Result(try Crypto.encrypt(recordData: data, ak: ak))
    }

    private func write(_ type: String, data: RecordData, plain: PlainMeta, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {

        let cypher: CypherData
        switch encrypt(data, ak: ak) {
        case .success(let c):
            cypher = c
        case .failure(let err):
            return completion(Result(error: err))
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
            let resp = result
                .map { Record(meta: $0.meta, data: data) }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    public func write(_ type: String, data: RecordData, plain: PlainMeta, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { (result) in
            switch result {
            case .success(let ak):
                self.write(type, data: data, plain: plain, ak: ak, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Read Record

extension E3db {
    private struct RecordRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
                .appendingPathComponent(recordId)
            let req = URLRequest(url: url)
            return req
        }
    }

    internal func decrypt(data: CypherData, accessKey: AccessKey) -> E3dbResult<RecordData> {
        return Result(try Crypto.decrypt(cypherData: data, ak: accessKey)).map(RecordData.init)
    }

    private func decryptRecord(record r: RecordResponse, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: r.meta.writerId, userId: r.meta.userId, readerId: clientId, recordType: r.meta.type) { (akResult) in
            let result = akResult
                .flatMap { self.decrypt(data: r.cypherData, accessKey: $0) }
                .map { Record(meta: r.meta, data: $0) }
            completion(result)
        }
    }

    private func readRaw(_ recordId: String, completion: @escaping E3dbCompletion<RecordResponse>) {
        let req = RecordRequest(api: api, recordId: recordId)
        authedClient.perform(req, completionHandler: { completion($0.mapError(E3dbError.init)) })
    }

    public func read(recordId: String, completion: @escaping E3dbCompletion<Record>) {
        readRaw(recordId) { (result) in
            switch result {
            case .success(let r):
                self.decryptRecord(record: r, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}
