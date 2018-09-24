//
//  File.swift
//  E3db
//

import Foundation

public struct FileMeta: Codable {
    let fileUrl: URL?
    let fileName: String?
    let checksum: String
    let compression: String
    let size: UInt64?

    enum CodingKeys: String, CodingKey {
        case fileUrl     = "file_url"
        case fileName    = "file_name"
        case checksum
        case compression
        case size
    }
}

struct PendingFile: Decodable {
    let fileUrl: URL
    let id: UUID

    enum CodingKeys: String, CodingKey {
        case fileUrl = "file_url"
        case id
    }
}

// MARK: Write File

extension Client {

    private typealias MetaInfo = (writerId: UUID, userId: UUID, type: String, plain: PlainMeta?)

    private struct CreateFileRequest: E3dbRequest {
        typealias ResponseObject = PendingFile
        let api: Api

        let recordInfo: RecordRequestInfo
        func build() -> URLRequest {
            let url = api.url(endpoint: .files)
            var req = URLRequest(url: url)
            return req.asJsonRequest(.post, payload: recordInfo)
        }
    }

    private struct UploadFileRequest: E3dbRequest {
        typealias ResponseObject = Void
        let fileUrl: URL
        let fileMd5: String

        func build() -> URLRequest {
            var req = URLRequest(url: fileUrl)
            req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.setValue(fileMd5, forHTTPHeaderField: "Content-MD5")
            return req
        }
    }

    private struct CommitFileRequest: E3dbRequest {
        typealias ResponseObject = RecordResponse
        let api: Api
        let fileId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .files) / fileId.uuidString
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            return req
        }
    }

    public func writeFile(type: String, fileUrl: URL, plain: PlainMeta? = nil, completion: @escaping E3dbCompletion<Meta>) {
        let clientId = config.clientId
        getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: type) { result in
            switch result {
            case .success(let accessKey):
                let info: MetaInfo = (writerId: clientId, userId: clientId, type: type, plain: plain)
                self.write(file: fileUrl, ak: accessKey.rawAk, info: info, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func write(file: URL, ak: RawAccessKey, info: MetaInfo, completion: @escaping E3dbCompletion<Meta>) {
        DispatchQueue.global().async {
            do {
                // creates a temp encrypted file
                let encrypted = try Crypto.encrypt(fileAt: file, ak: ak)
                let fileName  = file.lastPathComponent
                let fileMeta  = FileMeta(fileUrl: nil, fileName: fileName, checksum: encrypted.md5, compression: "raw", size: encrypted.size)
                let meta      = ClientMeta(writerId: info.writerId, userId: info.userId, type: info.type, plain: info.plain, fileMeta: fileMeta)
                let recInfo   = RecordRequestInfo(meta: meta, data: [:])

                // remove temp encrypted file when done,
                // regardless of success or error
                let withCleanup: E3dbCompletion<Meta> = { result in
                    _ = try? FileManager.default.removeItem(at: encrypted.url)
                    return completion(result)
                }
                let createReq = CreateFileRequest(api: self.api, recordInfo: recInfo)
                self.authedClient.performDefault(createReq) { result in
                    switch result {
                    case .success(let pending):
                        self.upload(file: encrypted, pendingInfo: pending, completion: withCleanup)
                    case .failure(let error):
                        withCleanup(.failure(error))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard case let err as E3dbError = error else {
                        return completion(.failure(.cryptoError("Failed to write file")))
                    }
                    completion(.failure(err))
                }
            }
        }
    }

    private func upload(file: EncryptedFileInfo, pendingInfo: PendingFile, completion: @escaping E3dbCompletion<Meta>) {
        let uploadReq = UploadFileRequest(fileUrl: pendingInfo.fileUrl, fileMd5: file.md5)
        authedClient.upload(fileAt: file.url, request: uploadReq, session: session) { result in
            switch result {
            case .success:
                self.commit(fileId: pendingInfo.id, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func commit(fileId: UUID, completion: @escaping E3dbCompletion<Meta>) {
        let commitReq = CommitFileRequest(api: api, fileId: fileId)
        authedClient.performDefault(commitReq) { resp in completion(resp.map { $0.meta }) }
    }
}

// MARK: Read File

extension Client {

    private struct ReadFileRequest: E3dbRequest {
        typealias ResponseObject = RecordResponse
        let api: Api
        let recordId: UUID

        func build() -> URLRequest {
            let url = api.url(endpoint: .files) / recordId.uuidString
            return URLRequest(url: url)
        }
    }

    public func readFile(recordId: UUID, destination: URL, completion: @escaping E3dbCompletion<Meta>) {
        let readReq = ReadFileRequest(api: api, recordId: recordId)
        authedClient.performDefault(readReq) { result in
            switch result {
            case .success(let record):
                self.download(fileFrom: record.meta, to: destination, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func download(fileFrom meta: Meta, to destination: URL, completion: @escaping E3dbCompletion<Meta>) {
        guard let downloadUrl = meta.fileMeta?.fileUrl else {
            return completion(.failure(.apiError(code: 400, message: "Record missing file url")))
        }
        getStoredAccessKey(writerId: meta.writerId, userId: meta.userId, readerId: self.config.clientId, recordType: meta.type) { result in
            switch result {
            case .success(let eak):
                self.decrypt(fileAt: downloadUrl, to: destination, accessKey: eak) { result in
                    completion(result.map { _ in meta })
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func decrypt(fileAt downloadUrl: URL, to destination: URL, accessKey: AccessKey, completion: @escaping E3dbCompletion<Void>) {
        let downloadReq = URLRequest(url: downloadUrl)
        authedClient.download(downloadReq, session: self.session) { result in
            switch result {
            case .success(let local):
                DispatchQueue.global().async {
                    let resp: E3dbResult<()>
                    do {
                        try Crypto.decrypt(fileAt: local, to: destination, ak: accessKey.rawAk)
                        resp = .success(())
                    } catch let error as E3dbError {
                        resp = .failure(error)
                    } catch {
                        resp = .failure(.cryptoError("Failed to decrypt file"))
                    }
                    DispatchQueue.main.async {
                        completion(resp)
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
