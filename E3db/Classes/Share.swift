//
//  Share.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes

// MARK: Sharing

enum Policy: Ogra.Encodable {
    case allow, deny

    func encode() -> JSON {
        switch self {
        case .allow:
            return .object(["allow": .array([.object(["read": .object([:])])])])
        case .deny:
            return .object(["deny": .array([.object(["read": .object([:])])])])
        }
    }
}

public struct OutgoingSharingPolicy: Argo.Decodable {
    public let readerId: UUID
    public let type: String
    public let readerName: String?

    public static func decode(_ j: JSON) -> Decoded<OutgoingSharingPolicy> {
        return curry(OutgoingSharingPolicy.init)
            <^> j <|  "reader_id"
            <*> j <|  "record_type"
            <*> j <|? "reader_name"
    }
}

public struct IncomingSharingPolicy: Argo.Decodable {
    public let writerId: UUID
    public let type: String
    public let writerName: String?

    public static func decode(_ j: JSON) -> Decoded<IncomingSharingPolicy> {
        return curry(IncomingSharingPolicy.init)
            <^> j <|  "writer_id"
            <*> j <|  "record_type"
            <*> j <|? "writer_name"
    }
}

// MARK: Share and Unshare

extension Client {
    private struct ShareRequest: Request {
        typealias ResponseObject = Void
        let api: Api
        let policy: Policy

        let clientId: UUID
        let readerId: UUID
        let contentType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .policy)
            let url  = base / clientId.uuidString / clientId.uuidString / readerId.uuidString / contentType
            var req  = URLRequest(url: url)
            return req.asJsonRequest(.PUT, payload: policy.encode())
        }
    }

    public func share(_ type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let req = ShareRequest(api: api, policy: .allow, clientId: config.clientId, readerId: readerId, contentType: type)
        authedClient.performDefault(req, completion: completion)
    }

    public func revoke(_ type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let req = ShareRequest(api: api, policy: .deny, clientId: config.clientId, readerId: readerId, contentType: type)
        authedClient.performDefault(req, completion: completion)
    }
}

// MARK: Current Sharing Policies

extension Client {
    private struct GetOutgoingRequest: Request {
        typealias ResponseObject = [OutgoingSharingPolicy]
        let api: Api

        func build() -> URLRequest {
            let url = api.url(endpoint: .policy) / "outgoing"
            return URLRequest(url: url)
        }
    }

    private struct GetIncomingRequest: Request {
        typealias ResponseObject = [IncomingSharingPolicy]
        let api: Api

        func build() -> URLRequest {
            let url = api.url(endpoint: .policy) / "incoming"
            return URLRequest(url: url)
        }
    }

    public func getOutgoingSharing(completion: @escaping E3dbCompletion<[OutgoingSharingPolicy]>) {
        let req = GetOutgoingRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }

    public func getIncomingSharing(completion: @escaping E3dbCompletion<[IncomingSharingPolicy]>) {
        let req = GetIncomingRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }
}
