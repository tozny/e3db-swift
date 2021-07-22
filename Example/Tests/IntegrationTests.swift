import UIKit
import XCTest
@testable import E3db

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
            let session = IntegrationTests.verboseUrlSession()
            Client.register(token: TestData.token, clientName: test, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
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
            let session = IntegrationTests.verboseUrlSession()
            Client.register(token: TestData.token, clientName: test, publicKey: keyPair.publicKey, signingKey: sigPair.publicKey, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssertEqual(result.value!.publicKey, keyPair.publicKey)
                XCTAssertEqual(result.value!.signingKey, sigPair.publicKey)
                expect.fulfill()
            }
        }
    }

//    Currently the Tozny API DOES allow registration with invalid keys :-/
//    func testRegisterFailsWithInvalidKey() {
//        let test    = #function + UUID().uuidString
//        let keyPair = Client.generateKeyPair()!
//        let sigPair = Client.generateSigningKeyPair()!
//        let badKey  = String(keyPair.publicKey.dropFirst(5))
//        let session = IntegrationTests.verboseUrlSession()
//        asyncTest(test) { (expect) in
//            Client.register(token: TestData.token, clientName: test, publicKey: badKey, signingKey: sigPair.publicKey, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
//                defer { expect.fulfill() }
//                guard case .failure(.apiError) = result else {
//                    return XCTFail("Should not accept invalid key for registration")
//                }
//                XCTAssert(true)
//            }
//        }
//
//        let badSigK = String(sigPair.publicKey + "badness")
//        asyncTest(test) { (expect) in
//            Client.register(token: TestData.token, clientName: test, publicKey: keyPair.publicKey, signingKey: badSigK, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
//                defer { expect.fulfill() }
//                guard case .failure(.apiError) = result else {
//                    return XCTFail("Should not accept invalid key for registration")
//                }
//                XCTAssert(true)
//            }
//        }
//    }
    
//var creds = ClientCredentials(apiKey: "4ad16b108b216cadd1fbcfcafdd083094baa3c9fea62e602858d69a55768dcfb",
//                              apiSecret: "ca35aa13978f697998acbfc5337f1efa3f520141320a4df087ddee759883115b",
//                              clientId: "9a1b707c-6f9d-428f-8bbb-672ad5e0ec10",
//                              publicKey: "O4ZbyyYKpntFrkVlt0d-RwjoriCEHDjbz-HfBKTMkGc",
//                              privateKey: "G6IA8XFF6x7nyNyWeGCKr26gNdn-ilR2wGXtENKFpXs",
//                              publicSignKey: "-lSD4QiNUQEBW7_e1Ovp8H7Q5zzI0pqz37OwDBz_7cY",
//                              privateSigningKey: "TNSP7ArORR54jJe6O2ZEZKUNV9WR1nSdcnieT--3MID6VIPhCI1RAQFbv97U6-nwftDnPMjSmrPfs7AMHP_txg",
//                              host: "https://b6f631c1ae84.ngrok.io",
//                              email: "",
//                              clientName: "clientWithConfig()3CD1C236-A8E7-4731-A05C-9310CBA3204A");

    func testGetAccessKey() {
        let conf = Config(clientName: "clientWithConfig()3CD1C236-A8E7-4731-A05C-9310CBA3204A", clientId: UUID(uuidString: "9a1b707c-6f9d-428f-8bbb-672ad5e0ec10")!, apiKeyId: "4ad16b108b216cadd1fbcfcafdd083094baa3c9fea62e602858d69a55768dcfb", apiSecret: "ca35aa13978f697998acbfc5337f1efa3f520141320a4df087ddee759883115b", publicKey: "O4ZbyyYKpntFrkVlt0d-RwjoriCEHDjbz-HfBKTMkGc", privateKey: "G6IA8XFF6x7nyNyWeGCKr26gNdn-ilR2wGXtENKFpXs", baseApiUrl: URL(string: "https://b6f631c1ae84.ngrok.io")!, publicSigKey: "-lSD4QiNUQEBW7_e1Ovp8H7Q5zzI0pqz37OwDBz_7cY", privateSigKey: "TNSP7ArORR54jJe6O2ZEZKUNV9WR1nSdcnieT--3MID6VIPhCI1RAQFbv97U6-nwftDnPMjSmrPfs7AMHP_txg")
        let e3db = Client(config: conf, urlSession: .shared)
        let clientId = conf.clientId
        
        let data = RecordData(cleartext: ["test": "message"])

        asyncTest(#function + "write") { (expect) in
            e3db.write(type: "testType1", data: data) { (result) in
                XCTAssertNotNil(result.value)
                
                /// Get access key after write
                e3db.getAccessKey(writerId: clientId, userId: clientId, readerId: clientId, recordType: "testType1") { (akResult) in
                    XCTAssertNotNil(akResult.value)
                    /// String(...) fails "Unexpectedly found nil while unwrapping an Optional value"
//                    let string = String(bytes: akResult.value!.rawAk, encoding: .utf8)!
                    let encoded = try? Crypto.base64UrlEncoded(bytes: akResult.value!.rawAk)
                    print(encoded!)
                }
                expect.fulfill()
            }
        }
    }

    func testWriteReadRecord() {
        let e3db = client()
        let data = RecordData(cleartext: ["test": "message"])
        var record: Record?
        
        /// E3db Client
//        var client: Client?
//        var conf: Config?
//        let newClient = #function + UUID().uuidString
//        Client.register(token: TestData.token, clientName: newClient, apiUrl: TestData.apiUrl) { (result) in
//            conf = result.value
//            client = Client(config: conf!)
//        }
//        
//        /// HTTP Client
//        let parameters: [String: String] = ["grant_type": "client_credentials"]
//        let url = URL(string: "http://b6f631c1ae84.ngrok.io/v1/auth/token")!
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
//        request.setHTTPBody(parameters: parameters as [String: AnyObject])
//
//        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
//            guard let data = data else { return }
//            print(String(data: data, encoding: .utf8)!)
//        }
//        task.resume()

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

                // plain defaults to empty map on write (for now)
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

                // plain should be nil
                XCTAssertNotNil(record.meta.plain)
                XCTAssertNil(result.value!.meta.plain)

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

    func testFileUpload() {
        guard let srcUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open file")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
        }
        let e3db = client()
        let data = Data(repeatElement("testing", count: 100).joined().utf8)

        guard let _ = try? data.write(to: srcUrl) else {
            return XCTFail("Failed to write data")
        }

        asyncTest(#function) { (expect) in
            e3db.writeFile(type: "test-file", fileUrl: srcUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                expect.fulfill()
            }
        }
    }

    func testFileRoundTrip() {
        guard let srcUrl = FileManager.tempBinFile(),
              let dstUrl = FileManager.tempBinFile() else {
                return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
            try! FileManager.default.removeItem(at: dstUrl)
        }
        let e3db = client()
        let data = Data(repeatElement("testing", count: 100).joined().utf8)

        guard let _ = try? data.write(to: srcUrl) else {
            return XCTFail("Failed to write data")
        }

        var recordId: UUID?
        asyncTest(#function + "write") { (expect) in
            e3db.writeFile(type: "test-file", fileUrl: srcUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                recordId = result.value!.recordId
                expect.fulfill()
            }
        }

        asyncTest(#function + "read") { (expect) in
            e3db.readFile(recordId: recordId!, destination: dstUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                expect.fulfill()
            }
        }

        do {
            let result = try Data(contentsOf: dstUrl)
            XCTAssertEqual(result, data)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testReadFileRecord() {
        guard let srcUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
        }
        let e3db = client()
        let data = Data(repeatElement("testing", count: 100).joined().utf8)

        guard let _ = try? data.write(to: srcUrl) else {
            return XCTFail("Failed to write data")
        }

        var recordId: UUID?
        asyncTest(#function + "write") { (expect) in
            e3db.writeFile(type: "test-file", fileUrl: srcUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                recordId = result.value!.recordId
                expect.fulfill()
            }
        }

        asyncTest(#function + "read record") { (expect) in
            e3db.read(recordId: recordId!) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.meta.fileMeta)
                XCTAssertEqual(result.value!.data, [:])
                expect.fulfill()
            }
        }
    }

    func testQueryFileRecord() {
        guard let srcUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
        }
        let e3db = client()
        let data = Data(repeatElement("testing", count: 100).joined().utf8)
        let type = "test-file"

        guard let _ = try? data.write(to: srcUrl) else {
            return XCTFail("Failed to write data")
        }

        asyncTest(#function + "write") { (expect) in
            e3db.writeFile(type: type, fileUrl: srcUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                expect.fulfill()
            }
        }

        let query = QueryParams(includeData: true, types: [type])
        asyncTest(#function + "read record") { (expect) in
            e3db.query(params: query) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 1)
                XCTAssertEqual(result.value!.records.first!.data, [:])
                expect.fulfill()
            }
        }
    }

    func testReadNonExistentFile() {
        guard let dstUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: dstUrl)
        }
        let e3db = client()

        asyncTest(#function) { (expect) in
            e3db.readFile(recordId: UUID(), destination: dstUrl) { (result) in
                XCTAssertNil(result.value)
                XCTAssertNotNil(result.error)
                expect.fulfill()
            }
        }
        let fileData = try! Data(contentsOf: dstUrl)
        XCTAssert(fileData.isEmpty, "File should have no contents")
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
                XCTAssert(result.value!.records.isEmpty)
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
                XCTAssert(result.value!.records.isEmpty)
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
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main outgoing policy check1") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check1") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared outgoing policy check1") { (expect) in
            shareClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
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
                XCTAssert(result.value!.isEmpty)
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
                XCTAssert(result.value!.isEmpty)
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

    func testShareRevokeFile() {
        let mainClient = client()
        let (shareClient, sharedId) = clientWithId()
        guard let srcUrl = FileManager.tempBinFile(),
              let dstUrl = FileManager.tempBinFile() else {
                return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
            try! FileManager.default.removeItem(at: dstUrl)
        }
        let data = Data(repeatElement("testing", count: 100).joined().utf8)
        let type = "test-file"

        guard let _ = try? data.write(to: srcUrl) else {
            return XCTFail("Failed to write data")
        }
        var meta: Meta?

        // write initial file
        asyncTest(#function + "write") { (expect) in
            mainClient.writeFile(type: type, fileUrl: srcUrl) { (result) in
                XCTAssertNil(result.error)
                XCTAssertNotNil(result.value)
                XCTAssertNotNil(result.value?.fileMeta?.fileName)
                meta = result.value
                expect.fulfill()
            }
        }

        // shared client should not see records initially
        let query = QueryParams(includeData: true, includeAllWriters: true)
        asyncTest(#function + "read first") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 0)
                expect.fulfill()
            }
        }

        // shared client should not see file contents
        asyncTest(#function + "read file failure") { (expect) in
            shareClient.readFile(recordId: meta!.recordId, destination: dstUrl) { (result) in
                XCTAssertNil(result.value)
                XCTAssertNotNil(result.error)
                expect.fulfill()
            }
        }

        // share record type
        asyncTest(#function + "share") { (expect) in
            mainClient.share(type: meta!.type, readerId: sharedId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // shared client should now see full record
        asyncTest(#function + "read again") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.count == 1)
                XCTAssert(result.value!.records[0].meta.recordId == meta!.recordId)
                XCTAssert(result.value!.records[0].data.isEmpty)
                expect.fulfill()
            }
        }

        // shared client should now see file contents
        asyncTest(#function + "read file") { (expect) in
            shareClient.readFile(recordId: meta!.recordId, destination: dstUrl) { (result) in
                XCTAssertNil(result.error)
                do {
                    let contents = try Data(contentsOf: dstUrl)
                    XCTAssertEqual(contents, data)
                } catch {
                    XCTFail(error.localizedDescription)
                }
                expect.fulfill()
            }
        }

        // unshare record type
        asyncTest(#function + "revoke") { (expect) in
            mainClient.revoke(type: meta!.type, readerId: sharedId) { (result) in
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

    func testShareRevokeBehalfOf() {
        let (mainClient, mainId)   = clientWithId()
        let (authzClient, authzId) = clientWithId()
        let (shareClient, shareId) = clientWithId()
        let record  = writeTestRecord(mainClient)
        let recType = record.meta.type
        defer { deleteRecord(record, e3db: mainClient) }

        // shared client should not see records initially
        let query = QueryParams(includeData: true, includeAllWriters: true)
        asyncTest(#function + "read first") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.isEmpty)
                expect.fulfill()
            }
        }

        // main client authorize the authz client
        asyncTest(#function + "authorize") { (expect) in
            mainClient.add(authorizerId: authzId, type: recType) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // authz client share record type
        asyncTest(#function + "share on behalf of") { (expect) in
            authzClient.share(onBehalfOf: mainId, type: recType, readerId: shareId) { (result) in
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
        asyncTest(#function + "revoke on behalf of") { (expect) in
            authzClient.revoke(onBehalfOf: mainId, type: recType, readerId: shareId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // shared client should no longer see record
        asyncTest(#function + "read last") { (expect) in
            shareClient.query(params: query) { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.records.isEmpty)
                expect.fulfill()
            }
        }
    }

    func testAuthorizerPolicies() {
        let (mainClient, mainId)   = clientWithId()
        let (authzClient, authzId) = clientWithId()
        let (shareClient, shareId) = clientWithId()
        let record  = writeTestRecord(mainClient)
        let recType = record.meta.type
        defer { deleteRecord(record, e3db: mainClient) }

        // current policies should be empty
        asyncTest(#function + "main outgoing policy check1") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main get authorizers check1") { (expect) in
            mainClient.getAuthorizers() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "authz get authorized by check1") { (expect) in
            authzClient.getAuthorizedBy() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check1") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }

        // authorize the authz client
        asyncTest(#function + "authorize") { (expect) in
            mainClient.add(authorizerId: authzId, type: recType) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // confirm the right policies have changed
        asyncTest(#function + "main outgoing policy check2") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty) // not shared yet
                expect.fulfill()
            }
        }
        asyncTest(#function + "main get authorizers check2") { (expect) in
            mainClient.getAuthorizers() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                XCTAssert(result.value!.first!.authorizedBy == mainId)
                XCTAssert(result.value!.first!.authorizerId == authzId)
                expect.fulfill()
            }
        }
        asyncTest(#function + "authz get authorized by check2") { (expect) in
            authzClient.getAuthorizedBy() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                XCTAssert(result.value!.first!.authorizedBy == mainId)
                XCTAssert(result.value!.first!.authorizerId == authzId)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check2") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty) // not shared yet
                expect.fulfill()
            }
        }

        // authz client share record type
        asyncTest(#function + "share on behalf of") { (expect) in
            authzClient.share(onBehalfOf: mainId, type: recType, readerId: shareId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }

        // confirm the right policies have changed
        asyncTest(#function + "main outgoing policy check3") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                XCTAssert(result.value!.first!.readerId == shareId)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check3") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.count > 0)
                XCTAssert(result.value!.first!.writerId == mainId)
                expect.fulfill()
            }
        }

        // unshare record type
        asyncTest(#function + "revoke on behalf of") { (expect) in
            authzClient.revoke(onBehalfOf: mainId, type: recType, readerId: shareId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main outgoing policy check3") { (expect) in
            mainClient.getOutgoingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "shared incoming policy check3") { (expect) in
            shareClient.getIncomingSharing() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }

        // reset authorizer policy
        asyncTest(#function + "revoke") { (expect) in
            mainClient.remove(authorizerId: authzId) { (result) in
                XCTAssertNil(result.error)
                expect.fulfill()
            }
        }
        asyncTest(#function + "main get authorizers check1") { (expect) in
            mainClient.getAuthorizers() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
        asyncTest(#function + "authz get authorized by check1") { (expect) in
            authzClient.getAuthorizedBy() { (result) in
                XCTAssertNotNil(result.value)
                XCTAssert(result.value!.isEmpty)
                expect.fulfill()
            }
        }
    }
}

class ValidCertIntegrationTests: XCTestCase, TestUtils, PinnedCertificate, URLSessionDelegate {

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping CertificateCompletion) {
        validateCertificate(TestData.validCert, for: session, challenge: challenge, completion: completionHandler)
    }

    func testClientRegistrationWithValidPinnedCert() {
        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in

            // use pinned session delegate
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            Client.register(token: TestData.token, clientName: test, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
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

    func testClientConfigWithValidPinnedCert() {
        let (_, config) = clientWithConfig()

        // use pinned session delegate
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let client  = Client(config: config, urlSession: session)

        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in
            client.getIncomingSharing() { (result) in
                defer { expect.fulfill() }
                switch result {
                case .success(let policies):
                    XCTAssert(policies.isEmpty, "New client should have empty policies")
                case .failure(let error):
                    XCTFail("Failed to get incoming policies: \(error.description)")
                }
            }
        }
    }
}

class InvalidCertIntegrationTests: XCTestCase, TestUtils, PinnedCertificate, URLSessionDelegate {

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping CertificateCompletion) {
        validateCertificate(TestData.invalidCert, for: session, challenge: challenge, completion: completionHandler)
    }

    func testClientRegistrationWithInvalidPinnedCert() {
        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in
            // use pinned session delegate
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            Client.register(token: TestData.token, clientName: test, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
                defer { expect.fulfill() }
                switch result {
                case .success(let config):
                    XCTFail("Should not be able to register with invalid pinned cert: \(config)")
                case .failure(_):
                    XCTAssert(true)
                }
            }
        }
    }

    func testClientConfigWithInvalidPinnedCert() {
        let (_, config) = clientWithConfig()

        // use pinned session delegate
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let client  = Client(config: config, urlSession: session)

        let test = #function + UUID().uuidString
        asyncTest(test) { (expect) in
            client.getIncomingSharing() { (result) in
                defer { expect.fulfill() }
                switch result {
                case .success(let policies):
                    XCTFail("Should not be able to make API call with invalid pinned cert: \(policies)")
                case .failure(_):
                    XCTAssert(true)
                }
            }
        }
    }
}
