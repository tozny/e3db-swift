import UIKit
import XCTest
import E3db

class Tests: XCTestCase {

    func testRegistration() {
        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in
            E3db.register(token: TestData.token, clientName: test, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                expect.fulfill()
            }
        }
    }
    
    func testGetClientInfo() {
        let e3db = client()
        asyncTest(#function) { (expect) in
            e3db.getClientInfo { (result) in
                XCTAssertNotNil(result.value)
                expect.fulfill()
            }
        }
    }

    func testWriteReadRecord() {
        let e3db = client()
        let data = RecordData(clearText: ["test": "message"])
        var record: Record?

        // write record
        asyncTest(#function + "write") { (expect) in
            e3db.write("test-data", data: data) { (result) in
                XCTAssertNotNil(result.value)
                record = result.value
                expect.fulfill()
            }
        }

        // read it back out
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record!.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data.clearText, data.clearText)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record!, e3db: e3db)
    }

    func testReadRaw() {
        let e3db   = client()
        let data   = RecordData(clearText: ["test": "message"])
        let record = writeTestRecord(e3db)

        // read it back out raw
        asyncTest(#function + "readRaw") { (expect) in
            e3db.readRaw(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertNotEqual(result.value!.cypherData, data.clearText)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record, e3db: e3db)
    }

    func testDeleteRecord() {
        let e3db   = client()
        let data   = RecordData(clearText: ["test": "message"])
        let record = writeTestRecord(e3db)

        // delete record
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(record: record) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // read to confirm it is no longer present
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.error)
                defer { expect.fulfill() }
                guard case .failure(.apiError(404, _)) = result else {
                    return XCTFail("Should have deleted record")
                }
            }
        }
    }

    func testUpdateRecord() {
        let e3db   = client()
        var record = writeTestRecord(e3db)

        // update record
        let newData = RecordData(clearText: ["test": "updated"])
        let updated = record.updated(data: newData)
        asyncTest(#function + "update") { (expect) in
            e3db.update(record: updated) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.meta.recordId, record.meta.recordId)
                XCTAssertEqual(result.value!.data.clearText, newData.clearText)
                record = result.value!
                expect.fulfill()
            }
        }

        // read to confirm record has changed
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data.clearText, newData.clearText)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record, e3db: e3db)
    }

    func testQueryNoParams() {
        let e3db   = client()
        let record = writeTestRecord(e3db)

        // query for record
        let query = QueryParams()
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertGreaterThan(result.value!.records.count, 0)
                XCTAssert(result.value!.records.contains(where: { $0.meta.recordId == record.meta.recordId }))
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record, e3db: e3db)
    }

    func testQueryNext() {
        let e3db = client()
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        var last: Double?

        let tests = { (result: E3dbResult<QueryResponse>) in
            XCTAssertNotNil(result.value)
            XCTAssert(
                result.value!.records.contains {
                    $0.meta.recordId == rec1.meta.recordId ||
                    $0.meta.recordId == rec2.meta.recordId
                }
            )
        }

        // query for 1st record
        let q1 = QueryParams(count: 1)
        asyncTest(#function) { (expect) in
            e3db.query(params: q1) { (result) in
                tests(result)
                last = result.value!.last
                expect.fulfill()
            }
        }

        // query for 2nd record
        let q2 = q1.next(after: last!)
        asyncTest(#function) { (expect) in
            e3db.query(params: q2) { (result) in
                tests(result)
                expect.fulfill()
            }
        }

        // clean up
        [rec1, rec2].forEach { deleteRecord($0, e3db: e3db) }
    }

    func testQueryCount() {
        let e3db = client()
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        let rec3 = writeTestRecord(e3db)
        let rec4 = writeTestRecord(e3db)

        // query for record
        let limit = 2
        let query = QueryParams(count: limit)
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.records.count, limit)
                expect.fulfill()
            }
        }

        // clean up
        [rec1, rec2, rec3, rec4].forEach { deleteRecord($0, e3db: e3db) }
    }

    func testQueryIncludeData() {
        let e3db   = client()
        let record = writeTestRecord(e3db)

        // query for record
        let query = QueryParams(includeData: true)
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.map { $0.data.clearText }.contains { $0 == record.data.clearText })
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record, e3db: e3db)
    }

    func testShareUnshare() {
        let mainClient = client()
        let (shareClient, sharedId) = clientWithId()
        let record = writeTestRecord(mainClient)

        // shared client should not see records initially
        let query = QueryParams(includeAllWriters: true)
        asyncTest(#function + "read first") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 0)
                expect.fulfill()
            }
        }

        // share record type
        asyncTest(#function + "share") { (expect) in
            mainClient.share(record.meta.type, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // shared client should now see record
        asyncTest(#function + "read again") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 1)
                XCTAssert(result.value!.records[0].meta.recordId == record.meta.recordId)
                expect.fulfill()
            }
        }

        // unshare record type
        asyncTest(#function + "unshare") { (expect) in
            mainClient.unshare(record.meta.type, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // shared client should no longer see record
        asyncTest(#function + "read last") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 0)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record, e3db: mainClient)
    }

    func testGetPolicies() {
        let mainClient = client()
        let (shareClient, sharedId) = clientWithId()

        // current policies should be empty
        asyncTest(#function + "main incoming policy check1") { (expect) in
            mainClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main outgoing policy check1") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check1") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared outgoing policy check1") { (expect) in
            shareClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }

        // set share policy from main to shared
        asyncTest(#function + "share") { (expect) in
            mainClient.share(#function, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // confirm the right policies have changed
        asyncTest(#function + "main incoming policy check2") { (expect) in
            mainClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main outgoing policy check2") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check3") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared outgoing policy check4") { (expect) in
            shareClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count == 0)
                expect.fulfill()
            }
        }

        // reset share policy
        asyncTest(#function + "unshare") { (expect) in
            mainClient.unshare(#function, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }
    }
}

extension Tests {

    func asyncTest(_ testName: String, test: @
        escaping (XCTestExpectation) -> Void) {
        test(expectation(description: testName))
        waitForExpectations(timeout: 10, handler: { XCTAssertNil($0) })
    }

    func clientWithId() -> (E3db, UUID) {
        var e3db: E3db?
        var uuid: UUID?
        let newClient = #function + UUID().uuidString
        asyncTest(newClient) { (expect) in
            E3db.register(token: TestData.token, clientName: newClient, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                uuid = result.value!.clientId
                e3db = E3db(config: result.value!)
                expect.fulfill()
            }
        }
        return (e3db!, uuid!)
    }

    func client(useStaticClient: Bool = true) -> E3db {
        let e3db: E3db
        if useStaticClient {
            e3db = E3db(config: TestData.config)
        } else {
            (e3db, _) = clientWithId()
        }
        return e3db
    }

    func writeTestRecord(_ e3db: E3db) -> Record {
        var record: Record?
        asyncTest(#function + "write") { (expect) in
            e3db.write("test-data", data: RecordData(clearText: ["test": "message"])) { (result) in
                record = result.value!
                expect.fulfill()
            }
        }
        return record!
    }

    func deleteRecord(_ record: Record, e3db: E3db) {
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(record: record) { _ in expect.fulfill() }
        }
    }
}
