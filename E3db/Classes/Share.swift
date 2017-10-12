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
import Result

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

/// A type to describe an existing policy for records
/// written by the client to share with a given user
public struct OutgoingSharingPolicy {

    /// An identifier for a user with whom to share
    public let readerId: UUID

    /// The type of record to share
    public let type: String

    /// A name for the given user
    public let readerName: String?
}

/// :nodoc:
extension OutgoingSharingPolicy: Argo.Decodable {
    public static func decode(_ j: JSON) -> Decoded<OutgoingSharingPolicy> {
        return curry(OutgoingSharingPolicy.init)
            <^> j <|  "reader_id"
            <*> j <|  "record_type"
            <*> j <|? "reader_name"
    }
}

/// A type to describe an existing policy for records
/// written by others and shared with the client
public struct IncomingSharingPolicy {

    /// The identifier for the user sharing with the client
    public let writerId: UUID

    /// The type of record shared
    public let type: String

    /// A name for the given user
    public let writerName: String?
}

/// :nodoc:
extension IncomingSharingPolicy: Argo.Decodable {
    public static func decode(_ j: JSON) -> Decoded<IncomingSharingPolicy> {
        return curry(IncomingSharingPolicy.init)
            <^> j <|  "writer_id"
            <*> j <|  "record_type"
            <*> j <|? "writer_name"
    }
}

// MARK: Share and Revoke

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

    private func addSharePolicy(ak: AccessKey, type: String, clientId: UUID, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let cacheKey = AkCacheKey(writerId: clientId, userId: clientId, recordType: type)
        putAccessKey(ak: ak, cacheKey: cacheKey, writerId: clientId, userId: clientId, readerId: readerId, recordType: type) { result in
            switch result {
            case .success:
                let req = ShareRequest(api: self.api, policy: .allow, clientId: clientId, readerId: readerId, contentType: type)
                self.authedClient.performDefault(req, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }

    /// Allow another user to view and decrypt records of a given type.
    ///
    /// - Parameters:
    ///   - type: The kind of records to allow a user to view and decrypt
    ///   - readerId: The identifier of the user to allow access
    ///   - completion: A handler to call when this operation completes
    public func share(type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { result in
            switch result {
            case .success(let ak):
                self.addSharePolicy(ak: ak, type: type, clientId: clientId, readerId: readerId, completion: completion)
            case .failure:
                completion(Result(error: .apiError(code: 404, message: "No applicable records exist to share")))
            }
        }
    }

    /// Remove a user's access to view and decrypt records of a given type.
    ///
    /// - Parameters:
    ///   - type: The kind of records to remove access
    ///   - readerId: The identifier of the user to remove access
    ///   - completion: A handler to call when this operation completes
    public func revoke(type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let clientId = config.clientId
        deleteAccessKey(writerId: clientId, userId: clientId, readerId: readerId, recordType: type) { result in
            switch result {
            case .success:
                let req = ShareRequest(api: self.api, policy: .deny, clientId: clientId, readerId: readerId, contentType: type)
                self.authedClient.performDefault(req, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
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

    /// Request the list of policies allowing other users to view and decrypt this client's records.
    ///
    /// - Parameter completion: A handler to call when this operation completes to provide
    ///   the list of `OutgoingSharingPolicy` objects
    public func getOutgoingSharing(completion: @escaping E3dbCompletion<[OutgoingSharingPolicy]>) {
        let req = GetOutgoingRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }

    /// Request the list of policies allowing this client to view and decrypt records written by other users.
    ///
    /// - Parameter completion: A handler to call when this operation completes to provide
    ///   the list of `IncomingSharingPolicy` objects
    public func getIncomingSharing(completion: @escaping E3dbCompletion<[IncomingSharingPolicy]>) {
        let req = GetIncomingRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }
}
