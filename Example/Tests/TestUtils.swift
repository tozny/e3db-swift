import UIKit
import XCTest
import E3db

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
}
