import UIKit
import XCTest
@testable import E3db

import let Swish.immediateScheduler

// non-sensitive test data
// for running integration tests
struct TestData {
    static let apiUrl = ""
    static let token  = ""
}

protocol TestUtils {
    func asyncTest(_ testName: String, test: @escaping (XCTestExpectation) -> Void)
    func clientWithConfig() -> (Client, Config)
    func clientWithId() -> (Client, UUID)
    func client() -> Client
    func writeTestRecord(_ e3db: Client, _ contentType: String) -> Record
    func deleteRecord(_ record: Record, e3db: Client)
    func deleteAllRecords(_ e3db: Client)
    static func createClientSync() -> Client
    static func createKeySync(client: Client, recordType: String) -> EAKInfo
}

extension TestUtils where Self: XCTestCase {

    func asyncTest(_ testName: String, test: @escaping (XCTestExpectation) -> Void) {
        test(expectation(description: testName))
        waitForExpectations(timeout: 10, handler: { XCTAssertNil($0) })
    }

    func clientWithConfig() -> (Client, Config) {
        var e3db: Client?
        var conf: Config?
        let newClient = #function + UUID().uuidString
        asyncTest(newClient) { (expect) in
            Client.register(token: TestData.token, clientName: newClient, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                conf = result.value
                e3db = Client(config: conf!)
                expect.fulfill()
            }
        }
        return (e3db!, conf!)
    }

    func clientWithId() -> (Client, UUID) {
        let (e3db, conf) = clientWithConfig()
        return (e3db, conf.clientId)
    }

    func client() -> Client {
        let (e3db, _) = clientWithConfig()
        return e3db
    }

    func writeTestRecord(_ e3db: Client, _ contentType: String = "test-data") -> Record {
        var record: Record?
        asyncTest(#function + "write") { (expect) in
            e3db.write(type: contentType, data: RecordData(cleartext: ["test": "message"])) { (result) in
                record = result.value!
                expect.fulfill()
            }
        }
        return record!
    }

    func deleteRecord(_ record: Record, e3db: Client) {
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(recordId: record.meta.recordId, version: record.meta.version) { _ in expect.fulfill() }
        }
    }

    func deleteAllRecords(_ e3db: Client) {
        let test = #function + "delete all"
        var records = [Record]()
        asyncTest(test) { (expect) in
            e3db.query(params: QueryParams()) { (result) in
                records = result.value!.records
                expect.fulfill()
            }
        }
        records.forEach { (record) in
            deleteRecord(record, e3db: e3db)
        }
    }

    static func createClientSync() -> Client {
        var e3db: Client?
        let newClient = #function + UUID().uuidString
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .background).async {
            Client.register(token: TestData.token, clientName: newClient, apiUrl: TestData.apiUrl, scheduler: immediateScheduler) { (result) in
                XCTAssertNotNil(result.value)
                e3db = Client(config: result.value!, scheduler: immediateScheduler)
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + 20) == .success else {
            fatalError("Timed out")
        }
        return e3db!
    }

    static func createKeySync(client: Client, recordType: String) -> EAKInfo {
        var eakInfo: EAKInfo?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .background).async {
            client.createWriterKey(type: recordType) { result in
                guard case .success(let eak) = result else {
                    return XCTFail("Failed to get eak")
                }
                eakInfo = eak
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + 20) == .success else {
            fatalError("Timed out")
        }
        return eakInfo!
    }
}

// MARK: - Collect the memory sizes from different types

protocol MemoryReportable {
    var byteCount: Int { get }
}

extension String: MemoryReportable {
    var byteCount: Int {
        return [UInt8](self.utf8).count
    }
}

extension UUID: MemoryReportable {
    var byteCount: Int {
        return MemoryLayout.size(ofValue: self)
    }
}

extension Dictionary where Key == String, Value == String {
    var byteCount: Int {
        return self.reduce(0) { $0 + $1.key.byteCount + $1.value.byteCount }
    }
}

extension RecordData: MemoryReportable {
    var byteCount: Int {
        return cleartext.byteCount
    }
}

extension ClientMeta: MemoryReportable {
    var byteCount: Int {
        return writerId.byteCount + userId.byteCount + type.byteCount + (plain?.byteCount ?? 0)
    }
}

extension EncryptedDocument: MemoryReportable {
    var byteCount: Int {
        return clientMeta.byteCount + encryptedData.byteCount + recordSignature.byteCount
    }
}

extension SignedDocument: MemoryReportable {
    var byteCount: Int {
        return document.serialized().byteCount + signature.byteCount
    }
}

extension Data {
    func asciiMasked() -> Data {
        let maskedBytes = [UInt8](self).map { $0 & 127 }
        return Data(bytes: maskedBytes)
    }
}
