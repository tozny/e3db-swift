import UIKit
import XCTest
import E3db

class Tests: XCTestCase {

    let noErrorHandler: XCWaitCompletionHandler = { (err) in XCTAssertNil(err) }
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testRegistration() {
        let desc   = #function + UUID().uuidString
        let expect = expectation(description: desc)
        E3db.register(token: TestData.token, clientName: desc, apiUrl: TestData.apiUrl) { (result) in
            XCTAssertNotNil(result.value)
            expect.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }
    
    func testGetClientInfo() {
        let expect = expectation(description: #function)
        let e3db   = E3db(config: TestData.config)
        e3db.getClientInfo { (result) in
            XCTAssertNotNil(result.value)
            expect.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }

    func testWriteReadRecord() {
        let expect1 = expectation(description: #function + "write")
        let e3db    = E3db(config: TestData.config)
        let data    = RecordData(data: ["test": "message"])
        var recordId: UUID?

        // write record
        e3db.write("test-data", data: data) { (result) in
            XCTAssertNotNil(result.value)
            recordId = result.value?.meta.recordId
            expect1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // read it back out
        let expect2 = expectation(description: #function + "read")
        e3db.read(recordId: recordId!) { (result) in
            XCTAssertNotNil(result.value)
            XCTAssertEqual(result.value!.data.data, data.data)
            expect2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }

    func testWriteReadRaw() {
        let expect1 = expectation(description: #function + "write")
        let e3db    = E3db(config: TestData.config)
        let data    = RecordData(data: ["test": "message"])
        var recordId: UUID?

        // write record
        e3db.write("test-data", data: data) { (result) in
            XCTAssertNotNil(result.value)
            recordId = result.value?.meta.recordId
            expect1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // read it back out raw
        let expect2 = expectation(description: #function + "readRaw")
        e3db.readRaw(recordId: recordId!) { (result) in
            XCTAssertNotNil(result.value)
            XCTAssertNotEqual(result.value!.cypherData, data.data)
            expect2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }

    func testWriteDeleteRecord() {
        let expect1 = expectation(description: #function + "write")
        let e3db    = E3db(config: TestData.config)
        let data    = RecordData(data: ["test": "message"])
        var record: Record?

        // write record
        e3db.write("test-data", data: data) { (result) in
            XCTAssertNotNil(result.value)
            record = result.value
            expect1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // delete record
        let expect2 = expectation(description: #function + "delete")
        e3db.delete(record: record!) { (result) in
            XCTAssertNil(result.error)
            expect2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // read to confirm it is no longer present
        let expect3 = expectation(description: #function + "read")
        e3db.read(recordId: record!.meta.recordId) { (result) in
            XCTAssertNotNil(result.error)
            switch result {
            case .failure(.apiError(404, _)):
                XCTAssert(true)
            default:
                XCTFail("Should have deleted record")
            }
            expect3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }

    func testWriteUpdateRecord() {
        let expect1 = expectation(description: #function + "write")
        let e3db    = E3db(config: TestData.config)
        let oldData = RecordData(data: ["test": "message"])
        var record: Record?

        // write record
        e3db.write("test-data", data: oldData) { (result) in
            XCTAssertNotNil(result.value)
            record = result.value
            expect1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // update record
        let expect2 = expectation(description: #function + "update")
        let newData = RecordData(data: ["test": "updated"])
        let updated = record!.updated(data: newData)
        e3db.update(record: updated) { (result) in
            XCTAssertNotNil(result.value)
            XCTAssertEqual(result.value!.meta.recordId, record!.meta.recordId)
            XCTAssertEqual(result.value!.data.data, newData.data)
            expect2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)

        // read to confirm record has changed
        let expect3 = expectation(description: #function + "read")
        e3db.read(recordId: record!.meta.recordId) { (result) in
            XCTAssertNotNil(result.value)
            XCTAssertEqual(result.value!.data.data, newData.data)
            expect3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: noErrorHandler)
    }

}
