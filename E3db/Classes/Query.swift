//
//  Query.swift
//  E3db
//

import Foundation
import Swish
import Result

/// Data type to specify filters for querying records
public struct QueryParams: Encodable {

    /// Limit the number of records returned by the query beyond the E3db default
    let count: Int?

    /// Supply the full decrypted record data in the result records
    let includeData: Bool?

    /// Filter to records written by these IDs
    let writerIds: [UUID]?

    /// Filter to records with these user IDs
    let userIds: [UUID]?

    /// Filter to only the records identified by these IDs
    let recordIds: [UUID]?

    /// Filter to records that match the given types
    let types: [String]?

    /// Number to facilitate paging the results -- used with the `last` property of the `QueryResponse`
    let after: Double?

    /// Set this flag to include records that have been shared with you, defaults to `false`
    let includeAllWriters: Bool?

    /// Initializer to specify filters for querying records
    ///
    /// - Parameters:
    ///   - count: Limit the number of records returned by the query beyond the E3db default
    ///   - includeData: Supply the full decrypted record set in the results
    ///   - writerIds: Filter to records written by these IDs
    ///   - userIds: Filter to records with these user IDs
    ///   - recordIds: Filter to only the records identified by these IDs
    ///   - contentTypes: Filter to records that match the given types
    ///   - after: Number to facilitate paging the results -- used with the `last` property of the `QueryResponse`
    ///   - includeAllWriters: Set this flag to include records that have been shared with you, defaults to `false`
    public init(
        count: Int? = nil,
        includeData: Bool? = nil,
        writerIds: [UUID]? = nil,
        userIds: [UUID]? = nil,
        recordIds: [UUID]? = nil,
        types: [String]? = nil,
        after: Double? = nil,
        includeAllWriters: Bool? = nil
    ) {
        self.count = count
        self.includeData = includeData
        self.writerIds = writerIds
        self.userIds = userIds
        self.recordIds = recordIds
        self.types = types
        self.after = after
        self.includeAllWriters = includeAllWriters
    }

    /// Advance the query beyond the given value, leaving other parameters unchanged.
    ///
    /// - Parameter after: The value to start the results query
    /// - Returns: A new `QueryParams` object initialized with existing parameters
    ///   and a new starting value
    public func next(after: Double) -> QueryParams {
        return QueryParams(
            count: self.count,
            includeData: self.includeData,
            writerIds: self.writerIds,
            userIds: self.userIds,
            recordIds: self.recordIds,
            types: self.types,
            after: after,
            includeAllWriters: self.includeAllWriters
        )
    }

    enum CodingKeys: String, CodingKey {
        case count
        case includeData       = "include_data"
        case writerIds         = "writer_ids"
        case userIds           = "user_ids"
        case recordIds         = "record_ids"
        case types             = "content_types"
        case after             = "after_index"
        case includeAllWriters = "include_all_writers"
    }

    // build json object incrementally to omit null fields
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(includeData, forKey: .includeData)
        try container.encodeIfPresent(writerIds, forKey: .writerIds)
        try container.encodeIfPresent(userIds, forKey: .userIds)
        try container.encodeIfPresent(recordIds, forKey: .recordIds)
        try container.encodeIfPresent(types, forKey: .types)
        try container.encodeIfPresent(after, forKey: .after)
        try container.encodeIfPresent(includeAllWriters, forKey: .includeAllWriters)
    }
}

struct SearchRecord: Decodable {
    let meta: Meta
    let data: CipherData?
    let eakInfo: EAKInfo?

    enum CodingKeys: String, CodingKey {
        case meta
        case data    = "record_data"
        case eakInfo = "access_key"
    }
}

struct SearchResponse: Decodable {
    let results: [SearchRecord]
    let lastIndex: Double

    enum CodingKeys: String, CodingKey {
        case results
        case lastIndex = "last_index"
    }
}

/// A structure to hold a response from a query operation
public struct QueryResponse {

    /// A list of records matching the provided query.
    /// If the `includeData` flag was not set in the query,
    /// these records will contain empty `RecordData` values.
    public let records: [Record]

    /// An identifier for the final result of the query.
    /// Use this value in a subsequent query by setting the
    /// `after` property of a `QueryParams` object.
    ///
    /// - SeeAlso: `next(after:)` for a convenient way to query
    ///   for the next result set.
    public let last: Double
}

// MARK: Search

extension Client {
    private struct SearchRequest: E3dbRequest {
        typealias ResponseObject = SearchResponse
        let api: Api
        let params: QueryParams

        func build() -> URLRequest {
            let url = api.url(endpoint: .search)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.post, payload: params)
        }
    }

    private func decryptSearchRecord(_ searchRecord: SearchRecord) -> E3dbResult<Record> {
        guard let cipherData = searchRecord.data,
              let eakInfo    = searchRecord.eakInfo else {
                return Result(value: Record(meta: searchRecord.meta, data: Cleartext()))
        }

        return decryptEak(eakInfo: eakInfo, clientPrivateKey: self.config.privateKey)
            .flatMap { decrypt(data: cipherData, accessKey: $0) }
            .map { Record(meta: searchRecord.meta, data: $0.cleartext) }
    }

    private func decryptResults(response: SearchResponse) -> E3dbResult<QueryResponse> {
        return response
            .results
            .map(decryptSearchRecord)
            .sequence()
            .map { QueryResponse(records: $0, last: response.lastIndex) }
    }

    /// Search for records that match a given set of filters.
    ///
    /// - Note: If the `include_data` flag is not set in the given `QueryParams`,
    ///   the record results will contain empty `RecordData` values.
    ///
    /// - Parameters:
    ///   - params: A structure to specify a set of filters for matching records
    ///   - completion: A handler to call when this operation completes to provide the results of the query
    public func query(params: QueryParams, completion: @escaping E3dbCompletion<QueryResponse>) {
        let req = SearchRequest(api: api, params: params)
        authedClient.perform(req) { result in
            let resp = result
                .mapError(E3dbError.init)
                .flatMap(self.decryptResults)
            completion(resp)
        }
    }

}
