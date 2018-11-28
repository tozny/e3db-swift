//
//  CommonCryptoTests.swift
//  E3db_Tests
//
//  Created by Michael Lee on 11/28/18.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import XCTest

@testable import E3db

class CommonCryptoTests: XCTestCase, TestUtils {

    var client: Client?
    var config: Config?
    
    let type1 = "type1"
    
    private func createWriterKey(client: Client, type: String) -> EAKInfo {
        var eakInfo: EAKInfo?
        asyncTest("createWriterKey") { (expect) in
            client.createWriterKey(type: type) { (result) in
                defer { expect.fulfill() }
                guard case .success(let eak) = result else {
                    return XCTFail()
                }
                eakInfo = eak
            }
        }
        return eakInfo!
    }
    
    override func setUp() {
        super.setUp()
        let (c, cfg) = clientWithConfig()
        (self.client, self.config) = (c, cfg)
    }
    
    func testCanGenerateRandomAccessKey() {
        let someKey = CommonCrypto.generateRandomAccessKey(length: 8)
        XCTAssert(someKey != nil)
        XCTAssert(someKey?.count == 8)
    }
    
    func testCanGenerateCCKey() {
        do {
            let ccKey = try CommonCrypto.generateCCKey()
            XCTAssert(Data(base64Encoded: ccKey.aesKey)?.count == 16)
            XCTAssert(Data(base64Encoded: ccKey.aesIV)?.count == 16)

        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testCanEncryptAndDecryptDataWithCC() {
        let eakInfo = self.createWriterKey(client: client!, type: type1)

        do {
            let testData = ["test": "data"]
            let ccKey = try CommonCrypto.generateCCKey()
            let encrypted = try client!.encryptWrapCC(ccKey: ccKey, type: type1, data: RecordData(cleartext: testData), eakInfo: eakInfo)
            
            XCTAssert(encrypted.clientMeta.writerId == config!.clientId)
            XCTAssert(testData != encrypted.encryptedData)
            
            let decrypted = try client!.decryptWrapCC(ccKey: ccKey, encryptedDoc: encrypted, eakInfo: eakInfo)
            XCTAssert(decrypted.clientMeta.writerId == config!.clientId)
            XCTAssertEqual(decrypted.data, testData)
            
            print("decrypted data \(decrypted.data) should match initial string: \(testData)")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
}
