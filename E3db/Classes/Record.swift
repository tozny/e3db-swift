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

public typealias CipherData = [String: String]
public typealias PlainMeta  = [String: String]

public struct RecordData {
    public let cleartext: [String: String]
    public init(cleartext: [String: String]) {
        self.cleartext = cleartext
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

    /// :nodoc:
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
    let data: CipherData

    public func encode() -> JSON {
        return JSON.object([
            "meta": meta.encode(),
            "data": data.encode()
        ])
    }
}

struct RecordResponse: Argo.Decodable {
    let meta: Meta
    let cipherData: CipherData

    static func decode(_ j: JSON) -> Decoded<RecordResponse> {
        return curry(RecordResponse.init)
            <^> j  <| "meta"
            <*> (j <| "data").flatMap(CipherData.decode)
    }
}

public struct Record {
    public let meta: Meta
    public let data: RecordData

    public func update(data: RecordData) -> Record {
        return Record(meta: self.meta, data: data)
    }
}

// MARK: Write Record

extension Client {
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

    func encrypt(_ data: RecordData, ak: AccessKey) -> E3dbResult<CipherData> {
        return Result(try Crypto.encrypt(recordData: data, ak: ak))
    }

    private func write(_ type: String, data: RecordData, plain: PlainMeta?, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {

        let cipher: CipherData
        switch encrypt(data, ak: ak) {
        case .success(let c):
            cipher = c
        case .failure(let err):
            return completion(Result(error: err))
        }

        let meta = MetaRequest(
            writerId: config.clientId,
            userId: config.clientId,    // for now
            type: type,
            plain: plain
        )
        let record = RecordRequest(meta: meta, data: cipher)

        let req = CreateRecordRequest(api: api, record: record)
        authedClient.perform(req) { result in
            let resp = result
                .map { Record(meta: $0.meta, data: data) }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    public func write(type: String, data: RecordData, plain: PlainMeta? = nil, completion: @escaping E3dbCompletion<Record>) {
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

extension Client {
    private struct RecordRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / recordId.uuidString
            let req = URLRequest(url: url)
            return req
        }
    }

    internal func decrypt(data: CipherData, accessKey: AccessKey) -> E3dbResult<RecordData> {
        return Result(try Crypto.decrypt(cipherData: data, ak: accessKey))
    }

    private func decryptRecord(record r: RecordResponse, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: r.meta.writerId, userId: r.meta.userId, readerId: clientId, recordType: r.meta.type) { (akResult) in
            let result = akResult
                .flatMap { self.decrypt(data: r.cipherData, accessKey: $0) }
                .map { Record(meta: r.meta, data: $0) }
            completion(result)
        }
    }

    private func readRaw(recordId: UUID, completion: @escaping E3dbCompletion<RecordResponse>) {
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

extension Client {
    private struct RecordUpdateRequest: Request {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID
        let version: String
        let record: RecordRequest

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / "safe" / recordId.uuidString / version
            var req = URLRequest(url: url)
            return req.asJsonRequest(.PUT, payload: record.encode())
        }
    }

    private func update(meta: Meta, data: RecordData, ak: AccessKey, completion: @escaping E3dbCompletion<Record>) {
        let cipher: CipherData
        switch self.encrypt(data, ak: ak) {
        case .success(let c):
            cipher = c
        case .failure(let err):
            return completion(Result(error: err))
        }
        let metaReq = MetaRequest(
            writerId: meta.writerId,
            userId: meta.userId,
            type: meta.type,
            plain: meta.plain
        )
        let record = RecordRequest(meta: metaReq, data: cipher)
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

extension Client {
    private struct DeleteRecordRequest: Request {
        typealias ResponseObject = Void
        let api: Api
        let recordId: UUID
        let version: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / "safe" / recordId.uuidString / version
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
