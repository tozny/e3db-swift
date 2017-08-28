//
//  Query.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes
import Result

public struct QueryParams {
    let count: Int?
    let includeData: Bool?
    let writerIds: [UUID]?
    let userIds: [UUID]?
    let recordIds: [UUID]?
    let contentTypes: [String]?
    let after: Double?
    let plain: [String: String]?
    let includeAllWriters: Bool?

    public init(
        count: Int? = nil,
        includeData: Bool? = nil,
        writerIds: [UUID]? = nil,
        userIds: [UUID]? = nil,
        recordIds: [UUID]? = nil,
        contentTypes: [String]? = nil,
        after: Double? = nil,
        plain: [String: String]? = nil,
        includeAllWriters: Bool? = nil
    ) {
        self.count = count
        self.includeData = includeData
        self.writerIds = writerIds
        self.userIds = userIds
        self.recordIds = recordIds
        self.contentTypes = contentTypes
        self.after = after
        self.plain = plain
        self.includeAllWriters = includeAllWriters
    }
}

extension QueryParams {
    public func next(after: Double) -> QueryParams {
        return QueryParams(
            count: self.count,
            includeData: self.includeData,
            writerIds: self.writerIds,
            userIds: self.userIds,
            recordIds: self.recordIds,
            contentTypes: self.contentTypes,
            after: after,
            plain: self.plain,
            includeAllWriters: self.includeAllWriters
        )
    }
}

extension QueryParams: Ogra.Encodable {
    public func encode() -> JSON {
        // build json object incrementally to omit null fields
        var encoded = [String: JSON]()
        encoded["count"] = count?.encode()
        encoded["include_data"] = includeData?.encode()
        encoded["writer_ids"] = writerIds?.encode()
        encoded["user_ids"] = userIds?.encode()
        encoded["record_ids"] = recordIds?.encode()
        encoded["content_types"] = contentTypes?.encode()
        encoded["after_index"] = after?.encode()
        encoded["plain"] = plain?.encode()
        encoded["include_all_writers"] = includeAllWriters?.encode()
        return JSON.object(encoded)
    }
}

struct SearchRecord: Argo.Decodable {
    let meta: Meta
    let data: CypherData?
    let eakResponse: EAKResponse?

    static func decode(_ j: JSON) -> Decoded<SearchRecord> {
        return curry(SearchRecord.init)
            <^> j <| "meta"
            <*> .optional((j <| "record_data").flatMap(CypherData.decode))
            <*> j <|? "access_key"
    }
}

struct SearchResponse: Argo.Decodable {
    let results: [SearchRecord]
    let lastIndex: Double

    static func decode(_ j: JSON) -> Decoded<SearchResponse> {
        return curry(SearchResponse.init)
            <^> j <|| "results"
            <*> j <|  "last_index"
    }
}

public struct QueryResponse {
    public let records: [Record]
    public let last: Double
}

// MARK: Search

extension Client {
    private struct SearchRequest: Request {
        typealias ResponseObject = SearchResponse
        let api: Api
        let q: QueryParams

        func build() -> URLRequest {
            let url = api.url(endpoint: .search)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.POST, payload: q.encode())
        }
    }

    private func decryptSearchRecord(_ searchRecord: SearchRecord) -> E3dbResult<Record> {
        guard let cypherData = searchRecord.data,
              let eakResp    = searchRecord.eakResponse else {
                return Result(value: Record(meta: searchRecord.meta, data: RecordData(cleartext: [:])))
        }

        return decryptEak(eakResponse: eakResp, clientPrivateKey: self.config.privateKey)
            .flatMap { decrypt(data: cypherData, accessKey: $0) }
            .map { Record(meta: searchRecord.meta, data: $0) }
    }

    private func decryptResults(response: SearchResponse) -> E3dbResult<QueryResponse> {
        return response
            .results
            .map(decryptSearchRecord)
            .sequence()
            .map { QueryResponse(records: $0, last: response.lastIndex) }
    }

    public func query(params: QueryParams, completion: @escaping E3dbCompletion<QueryResponse>) {
        let req = SearchRequest(api: api, q: params)
        authedClient.perform(req) { (result) in
            let resp = result
                .mapError(E3dbError.init)
                .flatMap(self.decryptResults)
            completion(resp)
        }
    }

}
