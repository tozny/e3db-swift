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
    let writerIds: [String]?
    let userIds: [String]?
    let recordIds: [String]?
    let contentTypes: [String]?
    let afterIndex: Int?
    let plain: [String: String]?
    let includeAllWriters: Bool?

    public init(
        count: Int? = nil,
        includeData: Bool? = nil,
        writerIds: [String]? = nil,
        userIds: [String]? = nil,
        recordIds: [String]? = nil,
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
    public let lastIndex: Int
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

    private func queryResultsB(_ response: SearchResponse, params: QueryParams, onRecord: @escaping (Record) -> Void, done: @escaping (E3dbError?) -> Void) {
        let recs: E3dbResult<[Record]> = response
            .results
            .map(self.decryptSearchRecord)
            .sequence()

        switch recs {
        case .success(let records):
            records.forEach(onRecord)
            if records.count > 0 && records.count < (params.count ?? 50) {
                let nextQuery = params.next(index: response.lastIndex)
                self.queryB(params: nextQuery, onRecord: onRecord, done: done)
            } else {
                done(nil)
            }
        case .failure(let err):
            return done(err)
        }
    }

    public func queryB(params: QueryParams, onRecord: @escaping (Record) -> Void, done: @escaping (E3dbError?) -> Void) {
        let req = SearchRequest(api: api, q: params)
        authedClient.perform(req) { (result) in
            switch result {
            case .success(let response):
                self.queryResultsB(response, params: params, onRecord: onRecord, done: done)
            case .failure(let err):
                return done(E3dbError(swishError: err))
            }
        }
    }

    public func queryA(query: QueryParams, completion: @escaping E3dbCompletion<[Record]>) {
        let req = SearchRequest(api: api, q: query)
        authedClient.perform(req) { (result) in
            let resp: E3dbResult<[Record]> = result
                .flatMap { $0.results.map(self.decryptSearchRecord).sequence() }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    private func queryResultsC(_ response: SearchResponse, params: QueryParams, completion: @escaping E3dbCompletion<QueryResponse>) {
        let recs: E3dbResult<[Record]> = response
            .results
            .map(self.decryptSearchRecord)
            .sequence()

        switch recs {
        case .success(let records):
            if records.count > 0 && records.count < (params.count ?? 50) {
                let nextQuery = params.next(index: response.lastIndex)
                self.queryC(params: nextQuery, completion: completion)
            } else {

            }
        case .failure(let err):
            return completion(Result(error: err))
        }
    }

    public func queryC(params: QueryParams, completion: @escaping E3dbCompletion<QueryResponse>) {
        let req = SearchRequest(api: api, q: params)
        authedClient.perform(req) { (result) in
            switch result {
            case .success(let response):
                let records: E3dbResult<[Record]> = response
                    .results
                    .map(self.decryptSearchRecord)
                    .sequence()
                let resp = records.map { QueryResponse(records: $0, lastIndex: response.lastIndex) }
                completion(resp)
            case .failure(let err):
                completion(Result(error: E3dbError(swishError: err)))
            }
        }
    }

}
