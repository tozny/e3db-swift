//
//  Record.swift
//  E3db
//

import Foundation
import Result
import Swish

/// A type that holds arbitrary metadata for a record in cleartext
public typealias PlainMeta = [String: String]

/// A key-value store of unencrypted data
public typealias Cleartext = [String: String]

/// The ciphertext from a record after it has been encrypted
public typealias CipherData = [String: String]

/// A wrapper to hold unencrypted values
public struct RecordData {

    /// A key-value store of unencrypted data
    public let cleartext: Cleartext

    /// Initializer to create a structure to hold unencrypted data.
    /// The keys from the provided dictionary remain as unencrypted plaintext.
    /// The values are encrypted before transit to the E3db service,
    /// and decrypted after read back out from the service to support
    /// full end-to-end encryption.
    ///
    /// - Parameter cleartext: Unencrypted data
    public init(cleartext: [String: String]) {
        self.cleartext = cleartext
    }
}

// encoding and signing pass through to underlying cleartext
extension RecordData: Encodable, Signable {
    public func encode(to encoder: Encoder) throws {
        try cleartext.encode(to: encoder)
    }

    public func serialized() -> String {
        return cleartext.serialized()
    }
}

/// A type to hold metadata information created by a client
public struct ClientMeta: Codable {
    /// An identifier for the writer of the document
    public let writerId: UUID

    /// An identifier for the user of the document
    public let userId: UUID

    /// The kind of data this document represents
    public let type: String

    /// A user-defined, key-value store of metadata
    /// associated with the document that remains as plaintext
    public let plain: PlainMeta?

    public let fileMeta: FileMeta?

    enum CodingKeys: String, CodingKey {
        case writerId = "writer_id"
        case userId   = "user_id"
        case type
        case plain
        case fileMeta = "file_meta"
    }
}

/// A type to hold metadata information about a given record
public struct Meta: Decodable {

    /// An identifier for the record
    public let recordId: UUID

    /// An identifier for the writer of the record
    public let writerId: UUID

    /// An identifier for the user of the record
    public let userId: UUID

    /// The kind of data this record represents
    public let type: String

    /// A user-defined, key-value store of metadata
    /// associated with the record that remains as plaintext
    public let plain: PlainMeta?

    /// The timestamp marking the record's creation date, in ISO 8601 format
    public let created: Date

    /// The timestamp marking the record's most recent change, in ISO 8601 format
    public let lastModified: Date

    /// An identifier for the current version of the record
    public let version: String

    public let fileMeta: FileMeta?

    enum CodingKeys: String, CodingKey {
        case recordId     = "record_id"
        case writerId     = "writer_id"
        case userId       = "user_id"
        case type
        case plain
        case created
        case lastModified = "last_modified"
        case version
        case fileMeta     = "file_meta"
    }
}

struct RecordRequestInfo: Encodable {
    let meta: ClientMeta
    let data: CipherData
}

struct RecordResponse: Decodable {
    let meta: Meta
    let cipherData: CipherData

    enum CodingKeys: String, CodingKey {
        case meta
        case cipherData = "data"
    }
}

/// A type that holds unencrypted values and associated metadata
public struct Record {

    /// Metadata about the record, such as record ID, creation date, etc.
    public let meta: Meta

    /// The unencrypted values for the record
    public let data: Cleartext
}

// MARK: Write Record

extension Client {
    private struct CreateRecordRequest: E3dbRequest {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordInfo: RecordRequestInfo

        func build() -> URLRequest {
            let url = api.url(endpoint: .records)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.post, payload: recordInfo)
        }
    }

    func encrypt(_ data: RecordData, ak: RawAccessKey) -> E3dbResult<CipherData> {
        return Result(try Crypto.encrypt(recordData: data, ak: ak))
    }

    private func write(_ type: String, data: RecordData, plain: PlainMeta?, ak: RawAccessKey, completion: @escaping E3dbCompletion<Record>) {

        let cipher: CipherData
        switch encrypt(data, ak: ak) {
        case .success(let thisCipher):
            cipher = thisCipher
        case .failure(let err):
            return completion(Result(error: err))
        }

        let meta = ClientMeta(
            writerId: config.clientId,
            userId: config.clientId,    // for now
            type: type,
            plain: plain,
            fileMeta: nil
        )
        let record = RecordRequestInfo(meta: meta, data: cipher)

        let req = CreateRecordRequest(api: api, recordInfo: record)
        authedClient.perform(req) { result in
            let resp = result
                .map { Record(meta: $0.meta, data: data.cleartext) }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    /// Write a record to the E3db service. This will encrypt the `RecordData` fields (leaving the keys as plaintext)
    /// then send to E3db for storage. The `Record` in the response will contain the unencrypted values and additional
    /// metadata associated with the record.
    ///
    /// - Parameters:
    ///   - type: The kind of data this record represents
    ///   - data: The unencrypted values for the record
    ///   - plain: A user-defined, key-value store associated with the record that remains as plaintext
    ///   - completion: A handler to call when this operation completes to provide the record result
    public func write(type: String, data: RecordData, plain: PlainMeta? = nil, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { result in
            switch result {
            case .success(let ak):
                self.write(type, data: data, plain: plain, ak: ak.rawAk, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Read Record

extension Client {
    private struct RecordRequest: E3dbRequest {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID
        let fields: [String]

        private func constructUrl(base: URL) -> URL {
            var comp = URLComponents(url: base, resolvingAgainstBaseURL: false)
            comp?.queryItems = fields.map { URLQueryItem(name: "field", value: $0) }
            return comp?.url ?? base
        }

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / recordId.uuidString
            let req = URLRequest(url: constructUrl(base: url))
            return req
        }
    }

    func decrypt(data: CipherData, accessKey: RawAccessKey) -> E3dbResult<RecordData> {
        return Result(try Crypto.decrypt(cipherData: data, ak: accessKey))
    }

    private func decryptRecord(record rec: RecordResponse, completion: @escaping E3dbCompletion<Record>) {
        let clientId = config.clientId
        getAccessKey(writerId: rec.meta.writerId, userId: rec.meta.userId, readerId: clientId, recordType: rec.meta.type) { akResult in
            let result = akResult
                .flatMap { self.decrypt(data: rec.cipherData, accessKey: $0.rawAk) }
                .map { Record(meta: rec.meta, data: $0.cleartext) }
            completion(result)
        }
    }

    private func readRaw(recordId: UUID, fields: [String]? = nil, completion: @escaping E3dbCompletion<RecordResponse>) {
        let req = RecordRequest(api: api, recordId: recordId, fields: fields ?? [])
        authedClient.performDefault(req, completion: completion)
    }

    /// Request and decrypt a record from the E3db service.
    ///
    /// - Parameters:
    ///   - recordId: The identifier for the `Record` to read
    ///   - fields: A list of fields to select from the data, instead of the full record data
    ///   - completion: A handler to call when the operation completes to provide the decrypted record
    public func read(recordId: UUID, fields: [String]? = nil, completion: @escaping E3dbCompletion<Record>) {
        readRaw(recordId: recordId, fields: fields) { result in
            switch result {
            case .success(let record):
                self.decryptRecord(record: record, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Update Record

extension Client {
    private struct RecordUpdateRequest: E3dbRequest {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID
        let version: String
        let recordInfo: RecordRequestInfo

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / "safe" / recordId.uuidString / version
            var req = URLRequest(url: url)
            return req.asJsonRequest(.put, payload: recordInfo)
        }
    }

    private func update(_ recordId: UUID, version: String, metaReq: ClientMeta, data: RecordData, ak: RawAccessKey, completion: @escaping E3dbCompletion<Record>) {
        let cipher: CipherData
        switch self.encrypt(data, ak: ak) {
        case .success(let thisCipher):
            cipher = thisCipher
        case .failure(let err):
            return completion(Result(error: err))
        }
        let record = RecordRequestInfo(meta: metaReq, data: cipher)
        let req    = RecordUpdateRequest(api: api, recordId: recordId, version: version, recordInfo: record)
        authedClient.perform(req) { result in
            let resp = result
                .map { Record(meta: $0.meta, data: data.cleartext) }
                .mapError(E3dbError.init)
            completion(resp)
        }
    }

    /// Replace the data and plain metadata for a record identified by its `Meta`. This will overwrite
    /// the existing data and metadata values.
    ///
    /// - Parameters:
    ///   - meta: The `Meta` information for the record to update
    ///   - newData: The unencrypted values to encrypt and replace for the record
    ///   - plain: The plaintext key-value store to replace for the record, pass in the existing plain for no changes
    ///   - completion: A handler to call when the operation completes to provide the updated record
    public func update(meta: Meta, newData: RecordData, plain: PlainMeta?, completion: @escaping E3dbCompletion<Record>) {
        getAccessKey(writerId: meta.writerId, userId: meta.userId, readerId: config.clientId, recordType: meta.type) { result in
            switch result {
            case .success(let ak):
                let metaReq = ClientMeta(
                    writerId: meta.writerId,
                    userId: meta.userId,
                    type: meta.type,
                    plain: plain,
                    fileMeta: nil
                )
                self.update(meta.recordId, version: meta.version, metaReq: metaReq, data: newData, ak: ak.rawAk, completion: completion)
            case .failure(let err):
                completion(Result(error: err))
            }
        }
    }
}

// MARK: Delete Record

extension Client {
    private struct DeleteRecordRequest: E3dbRequest {
        typealias ResponseObject = EmptyResponse
        let api: Api
        let recordId: UUID
        let version: String

        func build() -> URLRequest {
            let url = api.url(endpoint: .records) / "safe" / recordId.uuidString / version
            var req = URLRequest(url: url)
            req.httpMethod = RequestMethod.delete.rawValue
            return req
        }
    }

    /// Remove the record from the E3db service.
    ///
    /// - Parameters:
    ///   - recordId: The identifier for the `Record` to remove
    ///   - version: The version of the `Record` to delete
    ///   - completion: A handler to call when the operation completes
    public func delete(recordId: UUID, version: String, completion: @escaping E3dbCompletion<Void>) {
        let req = DeleteRecordRequest(api: api, recordId: recordId, version: version)
        authedClient.performDefault(req, completion: completion)
    }
}
