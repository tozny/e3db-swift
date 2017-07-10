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

public typealias RecordData = [String: Data]
public typealias CypherData = [String: String]
public typealias PlainMeta  = [String: String]

public struct Meta: Ogra.Encodable, Argo.Decodable {
    let recordId: String?
    let writerId: String
    let userId: String
    let type: String
    let plain: PlainMeta
    let created: Date?
    let lastModified: Date?
    let version: String?

    public func encode() -> JSON {
        return JSON.object([
            "record_id": recordId.encode(),
            "writer_id": writerId.encode(),
            "user_id": userId.encode(),
            "type": type.encode(),
            "plain": plain.encode(),
            "created": created.encode(),
            "last_modified": lastModified.encode(),
            "version": version.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<Meta> {
        let tmp = curry(Meta.init)
            <^> j <|? "record_id"
            <*> j <|  "writer_id"
            <*> j <|  "user_id"
            <*> j <|  "type"

        // split decode fixes: "expression was too complex
        // to be solved in reasonable time."
        //
        // The >>- (flatMap) decodes to [String: String]
        // and ?? coalesces to empty default value
        return tmp
            <*> ((j <|? "plain").flatMap { PlainMeta.decode($0 ?? JSON.object([:])) })
            <*> j <|? "created"
            <*> j <|? "last_modified"
            <*> j <|? "version"
    }
}

public struct Record: Ogra.Encodable, Argo.Decodable {
    let meta: Meta
    let data: CypherData

    public func encode() -> JSON {
        return JSON.object([
            "meta": meta.encode(),
            "data": data.encode()
        ])
    }

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
        let record: Record

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

        let meta = Meta(
            recordId: nil,
            writerId: config.clientId,
            userId: config.clientId,    // for now
            type: type,
            plain: plain,
            created: nil,
            lastModified: nil,
            version: nil
        )
        let record = Record(meta: meta, data: cypher)

        let req = CreateRecordRequest(api: api, record: record)
        authedClient.perform(req) { result in
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
