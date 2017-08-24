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
    public let clearText: [String: String]
    public init(clearText: [String: String]) {
        self.clearText = clearText
    }
}

struct MetaRequest: Ogra.Encodable {
    let writerId: UUID
    let userId: UUID
    let type: String
    let plain: PlainMeta?

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
    public let recordId: UUID
    public let writerId: UUID
    public let userId: UUID
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

public struct RecordResponse: Argo.Decodable {
    public let meta: Meta
    public let cypherData: CypherData

    public static func decode(_ j: JSON) -> Decoded<RecordResponse> {
        return curry(RecordResponse.init)
            <^> j  <| "meta"
            <*> (j <| "data").flatMap(CypherData.decode)
    }
}

public struct Record {
    public let meta: Meta
    public let data: RecordData

    public func updated(data: RecordData) -> Record {
        return Record(meta: self.meta, data: data)
    }
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

    private func write(_ type: String, data: RecordData, plain: PlainMeta?, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {

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

    public func write(_ type: String, data: RecordData, plain: PlainMeta? = nil, completion: @escaping E3dbCompletion<Record>) {
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

// MARK: Read Record / Read Raw

extension E3db {
    private struct RecordRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
                .appendingPathComponent(recordId.uuidString)
            let req = URLRequest(url: url)
            return req
        }
    }

    internal func decrypt(data: CypherData, accessKey: AccessKey) -> E3dbResult<RecordData> {
        return Result(try Crypto.decrypt(cypherData: data, ak: accessKey))
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

    public func readRaw(recordId: UUID, completion: @escaping E3dbCompletion<RecordResponse>) {
        let req = RecordRequest(api: api, recordId: recordId)
        authedClient.performDefault(req, completion: completion)
    }

    public func read(recordId: UUID, completion: @escaping E3dbCompletion<Record>) {
        readRaw(recordId: recordId) { (result) in
            switch result {
            case .success(let r):
                self.decryptRecord(record: r, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Update Record

extension E3db {
    private struct RecordUpdateRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID
        let version: String
        let record: RecordRequest

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
                .appendingPathComponent("safe")
                .appendingPathComponent(recordId.uuidString)
                .appendingPathComponent(version)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.PUT, payload: record.encode())
        }
    }

    private func update(meta: Meta, data: RecordData, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {
        let cypher: CypherData
        switch self.encrypt(data, ak: ak) {
        case .success(let c):
            cypher = c
        case .failure(let err):
            return completion(Result(error: err))
        }
        let metaReq = MetaRequest(
            writerId: meta.writerId,
            userId: meta.userId,
            type: meta.type,
            plain: meta.plain
        )
        let record = RecordRequest(meta: metaReq, data: cypher)
        let req    = RecordUpdateRequest(api: api, recordId: meta.recordId, version: meta.version ?? "", record: record)
        authedClient.perform(req) { (result) in
            let resp = result
                .map { Record(meta: $0.meta, data: data) }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    public func update(record: Record, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        let meta     = record.meta
        getAccessKey(writerId: meta.writerId, userId: meta.userId, readerId: clientId, recordType: meta.type) { (result) in
            switch result {
            case .success(let ak):
                self.update(meta: meta, data: record.data, ak: ak, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Delete Record

extension E3db {
    private struct DeleteRecordRequest: Request {
        typealias ResponseObject = Void
        let api: Api
        let recordId: UUID
        let version: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
                .appendingPathComponent("safe")
                .appendingPathComponent(recordId.uuidString)
                .appendingPathComponent(version)
            var req = URLRequest(url: url)
            req.httpMethod = RequestMethod.DELETE.rawValue
            return req
        }
    }

    public func delete(record: Record, completion: @escaping E3dbCompletion<Void>) {
        let req = DeleteRecordRequest(api: api, recordId: record.meta.recordId, version: record.meta.version ?? "")
        authedClient.performDefault(req, completion: completion)
    }
}
