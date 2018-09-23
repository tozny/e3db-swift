//
//  CryptoTests.swift
//  E3db_Tests
//

import XCTest
@testable import E3db

class CryptoTests: XCTestCase, TestUtils {

    func testFileEncryptDecryptEqual() {
        let srcUrl = FileManager.tempBinFile()
        let data   = Data(repeatElement("testing", count: 100).joined().utf8)

        do {
            try data.write(to: srcUrl)
            let accessKey = Crypto.generateAccessKey()!
            let encrypted = try Crypto.encrypt(fileAt: srcUrl, ak: accessKey)
            let decrypted = FileManager.tempBinFile()
            try Crypto.decrypt(fileAt: encrypted, to: decrypted, ak: accessKey)

            guard let input = InputStream(url: decrypted) else {
                return XCTFail("Could not open decrypted file")
            }
            input.open()
            defer {
                input.close()
                try! FileManager.default.removeItem(at: srcUrl)
                try! FileManager.default.removeItem(at: encrypted)
                try! FileManager.default.removeItem(at: decrypted)
            }

            var buffer = Data(count: data.count)
            guard input.read(data: &buffer) != -1 else {
                return XCTFail("Failed to read file")
            }
            XCTAssertEqual(buffer, data)
        } catch {
            return XCTFail(error.localizedDescription)
        }
    }

    func testMD5() {
        let srcUrl = FileManager.tempBinFile()
        let data   = Data(repeatElement("testing", count: 10).joined().utf8)
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
        }
        do {
            try data.write(to: srcUrl)
            let expected = "DPb7oJVFD4O0cXsAkVRltA=="
            let actual   = try Crypto.computeInfo(ofFile: srcUrl)
            XCTAssertEqual(expected, actual.md5)
        } catch {
            return XCTFail(error.localizedDescription)
        }
    }

}
