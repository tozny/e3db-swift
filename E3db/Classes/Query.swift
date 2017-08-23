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
    let afterIndex: Int?
    let plain: [String: String]?
    let includeAllWriters: Bool?

    public init(
        count: Int? = nil,
        includeData: Bool? = nil,
        writerIds: [UUID]? = nil,
        userIds: [UUID]? = nil,
        recordIds: [UUID]? = nil,
        contentTypes: [String]? = nil,
        afterIndex: Int? = nil,
        plain: [String: String]? = nil,
        includeAllWriters: Bool? = nil
    ) {
        self.count = count
        self.includeData = includeData
        self.writerIds = writerIds
        self.userIds = userIds
        self.recordIds = recordIds
        self.contentTypes = contentTypes
        self.afterIndex = afterIndex
        self.plain = plain
        self.includeAllWriters = includeAllWriters
    }
}

extension QueryParams {

    func next(index: Int) -> QueryParams {
        return QueryParams(
            count: self.count,
            includeData: self.includeData,
            writerIds: self.writerIds,
            userIds: self.userIds,
            recordIds: self.recordIds,
            contentTypes: self.contentTypes,
            afterIndex: index,
            plain: self.plain,
            includeAllWriters: self.includeAllWriters
        )
    }
}

extension QueryParams: Ogra.Encodable {
    public func encode() -> JSON {
        return JSON.object([
            "count": count.encode(),
            "include_data": includeData.encode(),
            "writer_ids": writerIds.encode(),
            "user_ids": userIds.encode(),
            "record_ids": recordIds.encode(),
            "content_types": contentTypes.encode(),
            "after_index": afterIndex.encode(),
            "plain": plain.encode(),
            "include_all_writers": includeAllWriters.encode()
        ])
    }
}

struct SearchRecord {
    let meta: Meta
    let data: CypherData?
    let eakResponse: EAKResponse?
}

extension SearchRecord: Argo.Decodable {
    static func decode(_ j: JSON) -> Decoded<SearchRecord> {
        return curry(SearchRecord.init)
            <^> j <| "meta"
            <*> .optional((j <| "record_data").flatMap(CypherData.decode))
            <*> j <|? "access_key"
    }
}

struct SearchResponse {
    let results: [SearchRecord]
    let lastIndex: Int
}

extension SearchResponse: Argo.Decodable {
    static func decode(_ j: JSON) -> Decoded<SearchResponse> {
        return curry(SearchResponse.init)
            <^> j <|| "results"
            <*> j <|  "last_index"
    }
}

public struct QueryResponse {
    public let records: [Record]
    public let last: Int
}

// MARK: Search

extension E3db {
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
              let eakResp = searchRecord.eakResponse else {
                return Result(value: Record(meta: searchRecord.meta, data: RecordData(data: [:])))
        }

        return decryptEak(eakResponse: eakResp, clientPrivateKey: self.config.privateKey)
            .flatMap { decrypt(data: cypherData, accessKey: $0) }
            .map { Record(meta: searchRecord.meta, data: $0) }
    }

    private func decryptResults(response: SearchResponse) -> E3dbResult<QueryResponse> {
        return response
            .results
            .map(self.decryptSearchRecord)
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
