import UIKit
import XCTest
import E3db

class IntegrationTests: XCTestCase, TestUtils {

    func testIntermediaryUseCase() {
        let (e3db, config) = clientWithConfig()
        let id   = config.clientId
        let test = #function + UUID().uuidString
        let type = "ticket"

        // register mock server client
        let (serverClient, serverConfig) = clientWithConfig()
        let signatureOfClientKey = try? serverClient.sign(document: config.publicSigKey)
        XCTAssertNotNil(signatureOfClientKey)
        let header = [
            "client_pub_sig_key": config.publicSigKey,
            "server_sig_of_client_sig_key": signatureOfClientKey!.signature
        ]

        // pre-share document type to ensure EAK is available (`createWriterKey` and `share` can happen in either order)
        var eakInfo1: EAKInfo?
        asyncTest(test + "createWriterKey") { (expect) in
            // online operation
            e3db.createWriterKey(type: type) { (result) in
                defer { expect.fulfill() }
                guard case .success(let eak1) = result else {
                    return XCTFail()
                }
                eakInfo1 = eak1
            }
        }
        XCTAssertNotNil(eakInfo1)
        asyncTest(test + "share") { (expect) in
            e3db.share(type: type, readerId: serverConfig.clientId) { (result) in
                defer { expect.fulfill() }
                guard case .success = result else {
                    return XCTFail()
                }
            }
        }

        // offline operations
        let data   = RecordData(cleartext: ["test_field": "test_value"])
        let encDoc = try? e3db.encrypt(type: type, data: data, eakInfo: eakInfo1!, plain: header)
        XCTAssertNotNil(encDoc)

        let signed = try? e3db.sign(document: encDoc!)
        XCTAssertNotNil(signed)

        // emulates intermediary operations

        // 1. verify server sig of client key
        let signedKeyDocument = SignedDocument(document: signed!.document.clientMeta.plain!["client_pub_sig_key"]!, signature: signed!.document.clientMeta.plain!["server_sig_of_client_sig_key"]!)
        let keyVerification   = try? e3db.verify(signed: signedKeyDocument, pubSigKey: serverConfig.publicSigKey)
        XCTAssertNotNil(keyVerification)
        XCTAssert(keyVerification!)

        // 2. verify signed document
        let docVerification = try? e3db.verify(signed: signed!, pubSigKey: config.publicSigKey)
        XCTAssertNotNil(docVerification)
        XCTAssert(docVerification!)

        // emulates server operations (i.e. document arrived at destination)
        asyncTest(test + "getReaderKey") { (expect) in
            serverClient.getReaderKey(writerId: id, userId: id, type: type) { (result) in
                defer { expect.fulfill() }
                guard case .success(let eakInfo2) = result else {
                    return XCTFail()
                }

                let decDoc = try? serverClient.decrypt(encryptedDoc: encDoc!, eakInfo: eakInfo2)
                XCTAssertNotNil(decDoc)
                XCTAssertEqual(decDoc!.data, data.cleartext)
            }
        }

    }

    func testRegistrationDefault() {
        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in
            Client.register(token: TestData.token, clientName: test, apiUrl: TestData.apiUrl) { (result) in
                defer { expect.fulfill() }
                switch result {
                case .success(let config):
                    // also test config save and load
                    XCTAssert(config.save(profile: test))
                    let loaded = Config(loadProfile: test)
                    XCTAssertNotNil(loaded)
                    XCTAssertEqual(config.clientId, loaded!.clientId)
                case .failure(let error):
                    XCTFail("Could not register: \(error.description)")
                }
            }
        }
    }

    func testRegistrationCustom() {
        let test    = #function + UUID().uuidString
        let keyPair = Client.generateKeyPair()!
        let sigPair = Client.generateSigningKeyPair()!
        asyncTest(test) { (expect) in
            Client.register(token: TestData.token, clientName: test, publicKey: keyPair.publicKey, signingKey: sigPair.publicKey, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.publicKey, keyPair.publicKey)
                XCTAssertEqual(result.value!.signingKey, sigPair.publicKey)
                expect.fulfill()
            }
        }
    }

    func testRegisterFailsWithInvalidKey() {
        let test    = #function + UUID().uuidString
        let keyPair = Client.generateKeyPair()!
        let sigPair = Client.generateSigningKeyPair()!
        let badKey  = String(keyPair.publicKey.dropFirst(5))
        asyncTest(test) { (expect) in
            Client.register(token: TestData.token, clientName: test, publicKey: badKey, signingKey: sigPair.publicKey, apiUrl: TestData.apiUrl) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError) = result else {
                    return XCTFail("Should not accept invalid key for registration")
                }
                XCTAssert(true)
            }
        }

        let badSigK = String(sigPair.publicKey + "badness")!
        asyncTest(test) { (expect) in
            Client.register(token: TestData.token, clientName: test, publicKey: keyPair.publicKey, signingKey: badSigK, apiUrl: TestData.apiUrl) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError) = result else {
                    return XCTFail("Should not accept invalid key for registration")
                }
                XCTAssert(true)
            }
        }
    }

    func testWriteReadRecord() {
        let e3db = client()
        let data = RecordData(cleartext: ["test": "message"])
        var record: Record?

        // write record
        asyncTest(#function + "write") { (expect) in
            e3db.write(type: "test-data", data: data) { (result) in
                XCTAssertNotNil(result.value)
                record = result.value
                expect.fulfill()
            }
        }

        // read it back out
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record!.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, data.cleartext)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record!, e3db: e3db)
    }

    func testReadFields() {
        let e3db = client()
        let filered = ["test": "message", "other": "hi"]
        let full = filered.merging(["hidden": "not shown"], uniquingKeysWith:{ a,_ in a })
        let data = RecordData(cleartext: full)
        var record: Record?

        // write record
        asyncTest(#function + "write") { (expect) in
            e3db.write(type: "test-data", data: data) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, full)
                record = result.value
                expect.fulfill()
            }
        }

        // read it back out, only two fields specified
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record!.meta.recordId, fields: Array(filered.keys)) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, filered)
                expect.fulfill()
            }
        }

        // clean up
        deleteRecord(record!, e3db: e3db)
    }

    func testWriteFailsWithEmptyData() {
        let e3db = client()
        let data = RecordData(cleartext: [:])

        // attempt to write record
        asyncTest(#function + "write") { (expect) in
            e3db.write(type: "test-data", data: data) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError(400, _)) = result else {
                    return XCTFail("Should not accept empty record data")
                }
                XCTAssert(true)
            }
        }
    }

    func testDeleteRecord() {
        let e3db   = client()
        let data   = RecordData(cleartext: ["test": "message"])
        let record = writeTestRecord(e3db)

        // delete record
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(recordId: record.meta.recordId, version: record.meta.version) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // read to confirm it is no longer present
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError(404, _)) = result else {
                    return XCTFail("Should have deleted record")
                }
                XCTAssert(true)
            }
        }
    }

    func testDeleteFailsForUnknownRecordId() {
        let e3db = client()

        // delete record
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(recordId: UUID(), version: UUID().uuidString) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError(403, _)) = result else {
                    return XCTFail("Should not find record")
                }
                XCTAssert(true)
            }
        }
    }

    func testUpdateRecord() {
        let e3db   = client()
        var record = writeTestRecord(e3db)
        defer { deleteRecord(record, e3db: e3db) }

        // update record
        let newData = RecordData(cleartext: ["test": "updated"])
        asyncTest(#function + "update") { (expect) in
            e3db.update(meta: record.meta, newData: newData, plain: nil) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.meta.recordId, record.meta.recordId)
                XCTAssertEqual(result.value!.data, newData.cleartext)
                record = result.value!
                expect.fulfill()
            }
        }

        // read to confirm record has changed
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, newData.cleartext)
                expect.fulfill()
            }
        }
    }

    func testUpdatePlain() {
        let e3db   = client()
        var record = writeTestRecord(e3db)
        defer { deleteRecord(record, e3db: e3db) }

        // update record with new plain
        let newData = RecordData(cleartext: ["test": "updated"])
        asyncTest(#function + "update") { (expect) in
            e3db.update(meta: record.meta, newData: newData, plain: ["new": "plain"]) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.meta.recordId, record.meta.recordId)
                XCTAssertEqual(result.value!.data, newData.cleartext)

                // plain defaults to empty map (for now)
                XCTAssertNotNil(record.meta.plain)
                XCTAssert(record.meta.plain!.isEmpty)
                XCTAssertNotNil(result.value!.meta.plain)
                XCTAssertNotEqual(record.meta.plain!, result.value!.meta.plain!)

                record = result.value!
                expect.fulfill()
            }
        }

        // read to confirm data and meta have changed
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, newData.cleartext)
                XCTAssertNotNil(result.value!.meta.plain)
                XCTAssertFalse(result.value!.meta.plain!.isEmpty)
                expect.fulfill()
            }
        }

        // update record with nil plain to clear it
        asyncTest(#function + "update") { (expect) in
            e3db.update(meta: record.meta, newData: newData, plain: nil) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.meta.recordId, record.meta.recordId)
                XCTAssertEqual(result.value!.data, newData.cleartext)

                // plain defaults to empty map (for now)
                XCTAssertNotNil(record.meta.plain)
                XCTAssertNotNil(result.value!.meta.plain)
                XCTAssertNotEqual(record.meta.plain!, result.value!.meta.plain!)

                record = result.value!
                expect.fulfill()
            }
        }

        // read to confirm data and meta have changed
        asyncTest(#function + "read") { (expect) in
            e3db.read(recordId: record.meta.recordId) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.data, newData.cleartext)
                XCTAssertNotNil(result.value!.meta.plain)
                XCTAssert(result.value!.meta.plain!.isEmpty)
                expect.fulfill()
            }
        }
    }

    func testUpdateFailsForConflictingVersions() {
        let e3db   = client()
        let record = writeTestRecord(e3db)
        defer { deleteRecord(record, e3db: e3db) }

        // first update should succeed
        let newData = RecordData(cleartext: ["test": "updated"])
        asyncTest(#function + "update1") { (expect) in
            e3db.update(meta: record.meta, newData: newData, plain: record.meta.plain) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.meta.recordId, record.meta.recordId)
                XCTAssertEqual(result.value!.data, newData.cleartext)
                expect.fulfill()
            }
        }

        // second update (with initial record meta version) should fail
        let moreNewData = RecordData(cleartext: ["test": "should fail"])
        asyncTest(#function + "update1") { (expect) in
            e3db.update(meta: record.meta, newData: moreNewData, plain: record.meta.plain) { (result) in
                defer { expect.fulfill() }
                guard case .failure(.apiError(409, _)) = result else {
                    return XCTFail("Should not update on version conflict")
                }
                XCTAssert(true)
            }
        }
    }

    func testQueryNoParams() {
        let e3db   = client()
        let record = writeTestRecord(e3db)
        defer { deleteRecord(record, e3db: e3db) }

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
    }

    func testQueryNext() {
        let e3db = client()
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        var last: Double?
        defer { [rec1, rec2].forEach { deleteRecord($0, e3db: e3db) } }

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
    }

    func testQueryCount() {
        let e3db = client()
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        let rec3 = writeTestRecord(e3db)
        let rec4 = writeTestRecord(e3db)
        defer { [rec1, rec2, rec3, rec4].forEach { deleteRecord($0, e3db: e3db) } }

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
    }

    func testQueryIncludeData() {
        let e3db   = client()
        let record = writeTestRecord(e3db)
        defer { deleteRecord(record, e3db: e3db) }

        // query for record
        let query = QueryParams(includeData: true)
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.map { $0.data }.contains { $0 == record.data })
                expect.fulfill()
            }
        }
    }

    func testQueryByType() {
        let e3db = client()
        let type = "other-type"
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        let rec3 = writeTestRecord(e3db, type)
        let rec4 = writeTestRecord(e3db, type)
        defer { [rec1, rec2, rec3, rec4].forEach { deleteRecord($0, e3db: e3db) } }

        // query for records filtered on custom type
        let query = QueryParams(types: [type])
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                result.value!.records.forEach { XCTAssert($0.meta.type == type) }
                expect.fulfill()
            }
        }
    }

    func testQueryByRecordId() {
        let e3db = client()
        let rec1 = writeTestRecord(e3db)
        let rec2 = writeTestRecord(e3db)
        let rec3 = writeTestRecord(e3db)
        let rec4 = writeTestRecord(e3db)
        defer { [rec1, rec2, rec3, rec4].forEach { deleteRecord($0, e3db: e3db) } }

        // query for records filtered on record IDs
        let query = QueryParams(recordIds: [rec2.meta.recordId, rec4.meta.recordId])
        asyncTest(#function) { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                result.value!.records.forEach {
                    XCTAssert($0.meta.recordId == rec2.meta.recordId || $0.meta.recordId == rec4.meta.recordId)
                }
                expect.fulfill()
            }
        }
    }

    func testQueryByWriterId() {
        let mainClient = client()
        let (shareClient, sharedId) = clientWithId()
        let record = writeTestRecord(mainClient)
        let unused = writeTestRecord(shareClient)
        defer {
            deleteRecord(record, e3db: mainClient)
            deleteRecord(unused, e3db: shareClient)
        }

        // share record type
        asyncTest(#function + "share") { (expect) in
            mainClient.share(type: record.meta.type, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // query for records filtered on writer ID
        let query = QueryParams(writerIds: [record.meta.writerId])
        asyncTest(#function + "query by writer") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 1)
                XCTAssert(result.value!.records[0].meta.writerId == record.meta.writerId)
                expect.fulfill()
            }
        }
    }

    func testShareRevoke() {
        let mainClient = client()
        let (shareClient, sharedId) = clientWithId()
        let record = writeTestRecord(mainClient)
        defer { deleteRecord(record, e3db: mainClient) }

        // shared client should not see records initially
        let query = QueryParams(includeData: true, includeAllWriters: true)
        asyncTest(#function + "read first") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 0)
                expect.fulfill()
            }
        }

        // share record type
        asyncTest(#function + "share") { (expect) in
            mainClient.share(type: record.meta.type, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // shared client should now see full record
        asyncTest(#function + "read again") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 1)
                XCTAssert(result.value!.records[0].meta.recordId == record.meta.recordId)
                XCTAssert(result.value!.records[0].data == record.data)
                expect.fulfill()
            }
        }

        // unshare record type
        asyncTest(#function + "revoke") { (expect) in
            mainClient.revoke(type: record.meta.type, readerId: sharedId) { (result) in
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
            mainClient.share(type: #function, readerId: sharedId) { (result) in
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
        asyncTest(#function + "revoke") { (expect) in
            mainClient.revoke(type: #function, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }
    }
}
