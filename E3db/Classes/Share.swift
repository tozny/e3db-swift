//
//  Share.swift
//  E3db
//

import Foundation
import Swish
import Result

// MARK: Sharing

enum Policy: Encodable {
    case allow, deny

    private typealias PolicyRepresentation = [String: [[String: [String: String]]]]

    func encode(to encoder: Encoder) throws {
        switch self {
        case .allow:
            let allow: PolicyRepresentation = ["allow": [["read": [:]]]]
            try allow.encode(to: encoder)
        case .deny:
            let deny: PolicyRepresentation = ["deny": [["read": [:]]]]
            try deny.encode(to: encoder)
        }
    }
}

/// A type to describe an existing policy for records
/// written by the client to share with a given user
public struct OutgoingSharingPolicy: Decodable {

    /// An identifier for a user with whom to share
    public let readerId: UUID

    /// The type of record to share
    public let type: String

    /// A name for the given user
    public let readerName: String?

    enum CodingKeys: String, CodingKey {
        case readerId   = "reader_id"
        case type       = "recordType"
        case readerName = "reader_name"
    }
}

/// A type to describe an existing policy for records
/// written by others and shared with the client
public struct IncomingSharingPolicy: Decodable {

    /// The identifier for the user sharing with the client
    public let writerId: UUID

    /// The type of record shared
    public let type: String

    /// A name for the given user
    public let writerName: String?

    enum CodingKeys: String, CodingKey {
        case writerId   = "writer_id"
        case type       = "recordType"
        case writerName = "writer_name"
    }
}

// MARK: Share and Revoke

extension Client {
    private struct ShareRequest: E3dbRequest {
        typealias ResponseObject = EmptyResponse
        let api: Api
        let policy: Policy

        let clientId: UUID
        let readerId: UUID
        let contentType: String

        func build() -> URLRequest {
            let base = api.url(endpoint: .policy)
            let url  = base / clientId.uuidString / clientId.uuidString / readerId.uuidString / contentType
            var req  = URLRequest(url: url)
            return req.asJsonRequest(.put, payload: policy)
        }
    }

    private func addSharePolicy(ak: RawAccessKey, type: String, clientId: UUID, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
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
                self.addSharePolicy(ak: ak.rawAk, type: type, clientId: clientId, readerId: readerId, completion: completion)
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
    private struct GetOutgoingRequest: E3dbRequest {
        typealias ResponseObject = [OutgoingSharingPolicy]
        let api: Api

        func build() -> URLRequest {
            let url = api.url(endpoint: .policy) / "outgoing"
            return URLRequest(url: url)
        }
    }

    private struct GetIncomingRequest: E3dbRequest {
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
