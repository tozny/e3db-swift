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

public typealias RecordData = [String: String]
public typealias Plain      = [String: String]

public struct Meta: Encodable, Decodable {
    let recordId: String?
    let writerId: String
    let userId: String
    let type: String
    let plain: Plain
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
            <*> (j <|? "plain" >>- { Plain.decode($0 ?? JSON.object([:])) })
            <*> j <|? "created"
            <*> j <|? "last_modified"
            <*> j <|? "version"
    }
}

public struct Record: Encodable, Decodable {
    let meta: Meta
    let data: RecordData

    public func encode() -> JSON {
        return JSON.object([
            "meta": meta.encode(),
            "data": data.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<Record> {
        return curry(Record.init)
            <^> j  <| "meta"
            <*> (j <| "data" >>- { RecordData.decode($0) })
    }
}


public struct ClientInfo: Encodable, Decodable {
    let clientId: String
    let publicKey: PublicKey
    let validated: Bool

    public func encode() -> JSON {
        return JSON.object([
            "client_id": clientId.encode(),
            "public_key": publicKey.encode(),
            "validated": validated.encode()
        ])
    }

    public static func decode(_ j: JSON) -> Decoded<ClientInfo> {
        return curry(ClientInfo.init)
            <^> j <| "client_id"
            <*> j <| "public_key"
            <*> j <| "validated"
    }
}
