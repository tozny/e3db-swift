//
//  Share.swift
//  E3db
//

import Foundation
import ToznySwish

// MARK: Sharing

enum Policy: Encodable {
    case allowRead, denyRead, allowAuthorizer, denyAuthorizer

    private typealias PolicyRepresentation = [String: [[String: [String: String]]]]

    func encode(to encoder: Encoder) throws {
        let policy: PolicyRepresentation
        switch self {
        case .allowRead:
            policy = ["allow": [["read": [:]]]]
        case .denyRead:
            policy = ["deny": [["read": [:]]]]
        case .allowAuthorizer:
            policy = ["allow": [["authorizer": [:]]]]
        case .denyAuthorizer:
            policy = ["deny": [["authorizer": [:]]]]
        }
        try policy.encode(to: encoder)
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
        case type       = "record_type"
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
        case type       = "record_type"
        case writerName = "writer_name"
    }
}

/// A type to describe an existing policy for clients that
/// are authorized to perform sharing and revoking operations
public struct AuthorizerPolicy: Decodable {

    /// The identifier of the client that can share on the writer's behalf
    public let authorizerId: UUID

    /// The identifier of the writer producing the records
    public let writerId: UUID

    /// An identifier for the user of the record
    public let userId: UUID

    /// The kind of records that are being shared
    public let recordType: String

    /// The identifier for the client that performed the authorization
    public let authorizedBy: UUID

    enum CodingKeys: String, CodingKey {
        case authorizerId = "authorizer_id"
        case writerId     = "writer_id"
        case userId       = "user_id"
        case recordType   = "record_type"
        case authorizedBy = "authorized_by"
    }
}

// MARK: Share and Revoke

extension Client {
    struct ShareRequest: E3dbRequest {
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

    func addPolicy(policy: Policy, ak: RawAccessKey, type: String, clientId: UUID, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let cacheKey = AkCacheKey(writerId: clientId, userId: clientId, recordType: type)
        putAccessKey(ak: ak, cacheKey: cacheKey, writerId: clientId, userId: clientId, readerId: readerId, recordType: type) { result in
            switch result {
            case .success:
                let req = ShareRequest(api: self.api, policy: policy, clientId: clientId, readerId: readerId, contentType: type)
                self.authedClient.performDefault(req, completion: completion)
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func share(writerId: UUID, initialReaderId: UUID, destinationReaderId: UUID, type: String, completion: @escaping E3dbCompletion<Void>) {
        getAccessKey(writerId: writerId, userId: writerId, readerId: initialReaderId, recordType: type) { result in
            switch result {
            case .success(let ak):
                self.addPolicy(policy: .allowRead, ak: ak.rawAk, type: type, clientId: writerId, readerId: destinationReaderId, completion: completion)
            case .failure:
                completion(.failure(.apiError(code: 404, message: "No applicable records exist to share")))
            }
        }
    }

    private func revoke(writerId: UUID, readerId: UUID, type: String, completion: @escaping E3dbCompletion<Void>) {
        deleteAccessKey(writerId: writerId, userId: writerId, readerId: readerId, recordType: type) { result in
            switch result {
            case .success:
                let req = ShareRequest(api: self.api, policy: .denyRead, clientId: writerId, readerId: readerId, contentType: type)
                self.authedClient.performDefault(req, completion: completion)
            case .failure(let err):
                completion(.failure(err))
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
        share(writerId: clientId, initialReaderId: clientId, destinationReaderId: readerId, type: type, completion: completion)
    }

    /// Share records written by the given writer with the given reader
    ///
    /// - Parameters:
    ///   - writerId: The identifier of the client that produced the records
    ///   - type: The kind of records to allow a user to view and decrypt
    ///   - readerId: The identifier of the user to allow access
    ///   - completion: A handler to call when this operation completes
    public func share(onBehalfOf writerId: UUID, type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        share(writerId: writerId, initialReaderId: config.clientId, destinationReaderId: readerId, type: type, completion: completion)
    }

    /// Remove a user's access to view and decrypt records of a given type.
    ///
    /// - Parameters:
    ///   - type: The kind of records to remove access
    ///   - readerId: The identifier of the user to remove access
    ///   - completion: A handler to call when this operation completes
    public func revoke(type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        revoke(writerId: config.clientId, readerId: readerId, type: type, completion: completion)
    }

    /// Remove permission for the given reader to read records produced by the given writer
    ///
    /// - Parameters:
    ///   - writerId: The identifier of the client that produced the records
    ///   - type: The kind of records to remove access
    ///   - readerId: The identifier of the user to remove access
    ///   - completion: A handler to call when this operation completes
    public func revoke(onBehalfOf writerId: UUID, type: String, readerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        revoke(writerId: writerId, readerId: readerId, type: type, completion: completion)
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

    private struct GetAuthorizersRequest: E3dbRequest {
        typealias ResponseObject = [AuthorizerPolicy]
        let api: Api

        func build() -> URLRequest {
            let url = api.url(endpoint: .policy) / "proxies"
            return URLRequest(url: url)
        }
    }

    private struct GetAuthorizedByRequest: E3dbRequest {
        typealias ResponseObject = [AuthorizerPolicy]
        let api: Api

        func build() -> URLRequest {
            let url = api.url(endpoint: .policy) / "granted"
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

    /// Request the list of policies allowing other clients to perform share and revoke operations
    /// on behalf of this client.
    ///
    /// - Parameter completion: A handler to call when this operation completes to provide
    ///   the list of `AuthorizerPolicy` objects
    public func getAuthorizers(completion: @escaping E3dbCompletion<[AuthorizerPolicy]>) {
        let req = GetAuthorizersRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }

    /// Request the list of policies allowing this client to perform share and revoke operations
    /// on behalf of other clients.
    ///
    /// - Parameter completion: A handler to call when this operation completes to provide
    ///   the list of `AuthorizerPolicy` objects
    public func getAuthorizedBy(completion: @escaping E3dbCompletion<[AuthorizerPolicy]>) {
        let req = GetAuthorizedByRequest(api: api)
        authedClient.performDefault(req, completion: completion)
    }
}

// MARK: Authorizer Policies

extension Client {
    struct DeletePolicyRequest: E3dbRequest {
        typealias ResponseObject = EmptyResponse
        let api: Api

        let clientId: UUID
        let readerId: UUID

        func build() -> URLRequest {
            let base = api.url(endpoint: .policy)
            let url  = base / clientId.uuidString / clientId.uuidString / readerId.uuidString
            var req  = URLRequest(url: url)
            req.httpMethod = "DELETE"
            return req
        }
    }

    /// Add an authorizer for records written by this client
    ///
    /// Calling this method will grant permission for the "authorizer" client to allow _other_
    /// clients to read records of the given type, written by this client.
    ///
    /// - Parameters:
    ///   - authorizerId: The identifier of the client that can share on the writer's behalf
    ///   - type: The kind of records being shared
    ///   - completion: A handler to call when this operation completes
    public func add(authorizerId: UUID, type: String, completion: @escaping E3dbCompletion<Void>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { result in
            switch result {
            case .success(let ak):
                self.addPolicy(policy: .allowAuthorizer, ak: ak.rawAk, type: type, clientId: clientId, readerId: authorizerId, completion: completion)
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Remove an authorizer for records of a given type written by this client
    ///
    /// This method removes the permission granted by `add(authorizerId:type:completion:)` for
    /// the provided record type.
    ///
    /// - Parameters:
    ///   - authorizerId: The identifier of the client that can share on the writer's behalf
    ///   - type: The kind of records being shared
    ///   - completion: A handler to call when this operation completes
    public func remove(authorizerId: UUID, type: String, completion: @escaping E3dbCompletion<Void>) {
        let req = ShareRequest(api: api, policy: .denyAuthorizer, clientId: config.clientId, readerId: authorizerId, contentType: type)
        authedClient.performDefault(req, completion: completion)
    }

    /// Remove an authorizer for all records written by this client
    ///
    /// This method removes the permission granted by `add(authorizerId:type:completion:)` for
    /// all record types.
    ///
    /// - Parameters:
    ///   - authorizerId: The identifier of the client that can share on the writer's behalf
    ///   - completion: A handler to call when this operation completes
    public func remove(authorizerId: UUID, completion: @escaping E3dbCompletion<Void>) {
        let req = DeletePolicyRequest(api: api, clientId: config.clientId, readerId: authorizerId)
        authedClient.performDefault(req, completion: completion)
    }
}
