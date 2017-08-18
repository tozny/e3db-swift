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

public struct Query {
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

extension Query: Ogra.Encodable {
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
    public static func decode(_ j: JSON) -> Decoded<SearchRecord> {
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
    public static func decode(_ j: JSON) -> Decoded<SearchResponse> {
        return curry(SearchResponse.init)
            <^> j <|| "results"
            <*> j <|  "last_index"
    }
}

// MARK: Search

extension E3db {
    private struct SearchRequest: Request {
        typealias ResponseObject = SearchResponse
        let api: Api
        let q: Query

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

    public func search(query: Query, completion: @escaping E3dbCompletion<[Record]>) {
        let req = SearchRequest(api: api, q: query)
        authedClient.perform(req) { (result) in
            switch result {
            case .success(let resp):
                completion(resp.results.map(self.decryptSearchRecord).sequence())
            case .failure(.serverError(code: 401, data: _)):
                completion(Result(error: .apiError(401, "Unauthorized")))
            case .failure(let err):
                if case .serverError(code: let code, data: _) = err,
                    let desc = err.errorDescription {
                    return completion(Result(error: .apiError(code, desc)))
                }
                // TODO: Better error management
                completion(Result(error: .error))
            }
        }
    }

}
