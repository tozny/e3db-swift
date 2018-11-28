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
    
//    override func setUp() {
//        super.setUp()
//        let (c, cfg) = clientWithConfig()
//        (self.client, self.config) = (c, cfg)
//    }
    
    func testCanGenerateRandomAccessKey() {
        let someKey = CommonCrypto.generateRandomAccessKey(length: 8)
        XCTAssert(someKey != nil)
        XCTAssert(someKey?.count == 8)
    }
    
    func testCanGenerateCCKey() {
        do {
            let _ = try CommonCrypto.generateCCKey()
//            XCTAssert(ccKey.aesKey.utf8.count == 128)
//            XCTAssert(ccKey.aesIV.utf8.count == 128)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testCanEncryptAndDecryptDataWithCC() {
//        do {
//            throw
//        } catch {
//            XCTFail(error.localizedDescription)
//        }
//
    }
    
}
